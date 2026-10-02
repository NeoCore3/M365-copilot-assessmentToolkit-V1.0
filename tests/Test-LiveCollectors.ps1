#Requires -Version 7.2
<#
.SYNOPSIS
    Runs the full live pipeline (separate collector processes, merge, import, analysis, dashboard) against a mock tenant
    (tests/Mock-Tenant.ps1) and asserts that every collector produces data. Exit code 0 on success.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$fail = 0
function Assert([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Host "  PASS  $Message" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Message" -ForegroundColor Red; $script:fail++; if ($env:GITHUB_ACTIONS) { Write-Host "::error title=Live collector test failed::$Message" } }
}
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('crt-live-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$env:CRT_TEST_MOCKS = Join-Path $PSScriptRoot 'Mock-Tenant.ps1'
try {
    & (Join-Path $root 'Invoke-CopilotReadinessAssessment.ps1') -TenantId '11111111-2222-3333-4444-555555555555' -CustomerName 'Mock Tenant' `
        -SharePointAdminUrl 'https://contoso-admin.sharepoint.com' -AdminUpn 'reader@contoso.com' -DagMode Export -OutputPath $tmp 3>$null 6>$null | Out-Null
}
finally { Remove-Item Env:\CRT_TEST_MOCKS -ErrorAction SilentlyContinue }

$run = Get-ChildItem $tmp -Directory | Select-Object -First 1
$status = Import-Csv (Join-Path $run.FullName 'csv/collection-status.csv')
$expectCollected = 'Graph_Organization', 'Graph_SubscribedSkus', 'Graph_Users', 'Graph_ReportSettings', 'Graph_CopilotUsage', 'Graph_CopilotUserCountTrend', 'Graph_CopilotUserCountSummary', 'Graph_ActiveUserDetail', 'Graph_ConditionalAccess', 'Graph_SecurityDefaults', 'Graph_RoleDefinitions', 'Graph_RoleAssignments', 'Graph_SharePointSettings', 'Graph_SecureScore', 'SPO_Tenant', 'SPO_Sites', 'SPO_OneDrive', 'PV_SensitivityLabels', 'PV_LabelPolicies', 'PV_AutoLabelPolicies', 'PV_DlpPolicies', 'PV_RetentionPolicies', 'EXO_AuditConfig', 'EXO_CopilotAuditSample', 'PP_Environments', 'PP_Inventory', 'FAB_TenantSettings'
foreach ($e in $expectCollected) { $r = $status | Where-Object Dataset -eq $e; Assert ($r -and $r.Status -eq 'Collected') "$e collected ($(if ($r) { "$($r.Status), $($r.Rows) rows" } else { 'missing' }))" }
Assert ((($status | Where-Object Dataset -eq 'Graph_Users').Rows) -eq '3') 'Graph paging followed @odata.nextLink (3 users)'
Assert ((($status | Where-Object Dataset -eq 'PP_Inventory').Rows) -eq '4') 'Inventory paging followed skipToken (4 resources)'
Assert ((($status | Where-Object Dataset -eq 'FAB_TenantSettings').Rows) -eq '3') 'Fabric paging followed continuationToken (3 settings)'
Assert ((($status | Where-Object Dataset -eq 'Graph_CopilotPackages').Status) -eq 'Failed') 'API error is recorded as Failed, not fatal'
Assert ((($status | Where-Object Dataset -eq 'IMP_DagEEEUItems').Status) -eq 'Imported') 'DAG report exported by the SharePoint collector is imported'

$m = Import-Csv (Join-Path $run.FullName 'csv/metrics.csv')
function Get-MetricValue($k) { ($m | Where-Object Key -eq $k).Value }
Assert ((Get-MetricValue 'lic.copilot.purchased') -eq '100') 'Copilot purchased = 100'
Assert ((Get-MetricValue 'lic.users.copilot') -eq '1') 'Copilot licensed users from Graph = 1'
Assert ((Get-MetricValue 'id.ca.mfaAll') -eq '1') 'MFA for all users policy detected'
Assert ((Get-MetricValue 'id.ca.legacyBlock') -eq '1') 'Legacy authentication block detected'
Assert ((Get-MetricValue 'id.roles.globalAdmins') -eq '2') 'Global Administrator assignments = 2'
Assert ((Get-MetricValue 'ccs.aiAdmins') -eq '1') 'AI Administrator assignments = 1'
Assert ((Get-MetricValue 'ip.labels') -eq '2') 'Sensitivity labels = 2'
Assert ((Get-MetricValue 'ip.dlp.enforced') -eq '1') 'DLP enforced = 1'
Assert ((Get-MetricValue 'am.ual') -eq 'True') 'Unified audit log on'
Assert ((Get-MetricValue 'am.copilotAudit') -eq '2') 'Copilot audit sample = 2'
Assert ((Get-MetricValue 'pp.agents') -eq '3') 'Inventory API agents = 3'
Assert ($null -ne (Get-MetricValue 'pp.agents.defaultPct')) 'Default environment share computed from inventory API'
Assert ((Get-MetricValue 'fb.copilotOn') -eq '2') 'Fabric Copilot and AI settings enabled = 2'
Assert ((Get-MetricValue 'use.users') -eq '2') 'Copilot usage from Graph JSON = 2 users'
Assert ($null -ne (Get-MetricValue 'use.active30Pct')) 'Usage activity computed from Graph JSON'
Assert ((Get-MetricValue 'da.tenant.SharingCapability') -eq 'ExternalUserSharingOnly') 'SharePoint tenant setting read'
$d = Import-Csv (Join-Path $run.FullName 'csv/diagnostics.csv')
Assert (@($d | Where-Object { $_.Operation -notmatch 'Graph_CopilotPackages' }).Count -eq 0) "No unexpected diagnostics ($(@($d).Count) total: $(($d | ForEach-Object { $_.Operation + ': ' + $_.Message }) -join ' | '))"
Assert (-not (Get-ChildItem (Join-Path $run.FullName 'raw') -Filter 'collector-*.clixml')) 'Collector hand-off files cleaned up'
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($fail) { Write-Host "$fail assertion(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All live collector tests passed' -ForegroundColor Green
