#Requires -Version 7.2
<#
.SYNOPSIS
    Offline self-test: parses every script, generates synthetic evidence, runs the toolkit in -OfflineOnly mode,
    and asserts on recognized datasets, metrics, checks, and outputs. Exit code 0 on success.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$fail = 0
function Assert([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Host "  PASS  $Message" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Message" -ForegroundColor Red; $script:fail++; if ($env:GITHUB_ACTIONS) { Write-Host "::error title=Test failed::$Message" } }
}
trap { if ($env:GITHUB_ACTIONS) { Write-Host ("::error title=Unhandled error::{0} at {1}" -f $_.Exception.Message, $_.InvocationInfo.PositionMessage -replace "`r?`n", ' ') }; throw }

Write-Host 'Parsing scripts'
foreach ($f in Get-ChildItem $root -Recurse -Filter *.ps1) {
    $tokens = $null; $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errs) | Out-Null
    Assert ($errs.Count -eq 0) "parse $($f.Name)$(if ($errs.Count) { ': ' + ($errs | Select-Object -First 1).Message })"
}
foreach ($j in Get-ChildItem (Join-Path $root 'config') -Filter *.json) { try { Get-Content $j.FullName -Raw | ConvertFrom-Json | Out-Null; Assert $true "json $($j.Name)" } catch { Assert $false "json $($j.Name): $_" } }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('crt-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$ev = Join-Path $tmp 'evidence'; $out = Join-Path $tmp 'output'
& (Join-Path $PSScriptRoot 'New-SampleEvidence.ps1') -Path $ev | Out-Null
& (Join-Path $root 'Invoke-CopilotReadinessAssessment.ps1') -CustomerName 'Contoso Test' -EvidencePath $ev -OfflineOnly -OutputPath $out -IncludeRowPreview 3>$null 6>$null | Out-Null

$run = Get-ChildItem $out -Directory | Select-Object -First 1
Write-Host "Checking outputs in $($run.FullName)"
$status = Import-Csv (Join-Path $run.FullName 'csv/collection-status.csv')
$expected = 'IMP_EntraUsers', 'IMP_CopilotReadiness', 'IMP_CopilotUsage', 'IMP_CopilotChat', 'IMP_CopilotSearch', 'IMP_AgentUsageAgents', 'IMP_AgentUsageUsers', 'IMP_AgentUsageUsersAgents', 'IMP_AgentRegistry', 'IMP_CopilotStudioInventory', 'IMP_AgentFlows', 'IMP_ConnectorsUsage', 'IMP_VivaCopilot', 'IMP_DagSharePoint', 'IMP_DagOneDrive', 'IMP_DagEEEUItems', 'IMP_DagEveryoneItems', 'IMP_ActiveSites', 'IMP_AIObservability', 'IMP_DspmAiActivity', 'IMP_DspmApps', 'IMP_DspmDataRisk'
foreach ($e in $expected) { $r = $status | Where-Object Dataset -eq $e; Assert ($r -and $r.Status -eq 'Imported' -and [int]$r.Rows -gt 0) "dataset $e imported ($(if ($r) { $r.Rows } else { 0 }) rows)" }
Assert ((($status | Where-Object Dataset -eq 'IMP_CopilotSearch').Rows) -eq '25') 'Copilot Search repair parsed all 25 rows'
Assert ((($status | Where-Object Dataset -eq 'IMP_DspmAiActivity').Rows) -eq '400') 'XLSX reader skipped title block and portal note row'
Assert ((($status | Where-Object Dataset -eq 'IMP_DspmAiActivity').Explanation) -match 'limited to 10,000') 'portal row cap is recorded'

$m = Import-Csv (Join-Path $run.FullName 'csv/metrics.csv')
function Get-MetricValue($k) { ($m | Where-Object Key -eq $k).Value }
Assert ((Get-MetricValue 'lic.users.copilot') -eq '80') 'directory Copilot licenses = 80 (SKU ID match)'
Assert ((Get-MetricValue 'lic.ready.licensed') -eq '80') 'readiness licensed = 80'
Assert ([int](Get-MetricValue 'lic.users.guests') -eq 15) 'guests = 15'
Assert ([int](Get-MetricValue 'da.sp.wide1000') -eq 3) 'SharePoint sites reachable by 1,000+ users = 3'
Assert ([int](Get-MetricValue 'da.od.accounts') -eq 200) 'OneDrive split by URL = 200 accounts'
Assert ([int](Get-MetricValue 'da.eeeu.grants') -eq 30) 'EEEU grants = 30'
Assert ([int](Get-MetricValue 'pp.agents') -eq 90) 'Copilot Studio inventory = 90'
foreach ($k in 'use.prompts', 'use.active30Pct', 'chat.active', 'lic.qualifiedPool', 'viva.activeRate', 'lc.inactive180', 'am.dspm.aiActivity', 'ip.dra.sensitiveItems', 'gov.ai.appsProtected') { Assert ($null -ne (Get-MetricValue $k)) "metric $k present" }

$c = Import-Csv (Join-Path $run.FullName 'csv/checks.csv')
Assert ($c.Count -eq 55) "55 checks evaluated ($($c.Count))"
Assert (@($c | Where-Object { $_.Status -eq 'NotAssessed' -and $_.Finding -notmatch 'NO DATA AVAILABLE' }).Count -eq 0) 'every not-assessed check says NO DATA AVAILABLE'
Assert (@($c | Where-Object { $_.Learn -and ($_.Learn -split ' ' | Where-Object { $_ -notmatch '^https://learn\.microsoft\.com/' }) }).Count -eq 0) 'all reference links are Microsoft Learn'

$html = Get-Content (Join-Path $run.FullName 'CopilotReadinessDashboard.html') -Raw
Assert ($html -notmatch '__REPORT_DATA__') 'dashboard data injected'
Assert ($html -notmatch '<script[^>]+src=') 'dashboard has no external scripts'
$json = [regex]::Match($html, '<script id="report-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value
try { $d = $json | ConvertFrom-Json; Assert ($d.checks.Count -eq 55) 'embedded JSON parses' } catch { Assert $false "embedded JSON parses: $_" }
foreach ($f in 'manifest.json', 'run.log', 'csv/domain-scores.csv', 'csv/evidence-inventory.csv', 'csv/diagnostics.csv') { Assert (Test-Path (Join-Path $run.FullName $f)) "output $f" }

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($fail) { Write-Host "$fail assertion(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All tests passed' -ForegroundColor Green
