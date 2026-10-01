#Requires -Version 7.2
<#
.SYNOPSIS
    Microsoft 365 Copilot Readiness Assessment Toolkit. Read-only collection plus portal-export import,
    producing an HTML dashboard and CSV exports.

.DESCRIPTION
    Hybrid model:
      1. Collect what Microsoft exposes through read-only APIs and PowerShell (Microsoft Graph, SharePoint Online,
         Security & Compliance, Exchange Online audit, Power Platform, Fabric).
      2. Import the portal exports that have no API (Copilot readiness, Copilot Chat, Viva Insights, DSPM,
         SharePoint data access governance, Agents registry, Power Platform inventory). Files are recognized by
         their column headers, so the original portal file names do not need to be kept.
      3. Compute metrics with denominators, evaluate checks, and write the dashboard and CSVs.

    Nothing is changed in the tenant. Sign-in is interactive and delegated.

.EXAMPLE
    # Offline: analyze portal exports only (no sign-in)
    ./Invoke-CopilotReadinessAssessment.ps1 -CustomerName 'Contoso' -EvidencePath 'D:\Contoso\Discovery' -OfflineOnly

.EXAMPLE
    # Full run, Commercial cloud
    ./Invoke-CopilotReadinessAssessment.ps1 -TenantId 00000000-0000-0000-0000-000000000000 -CustomerName 'Contoso' `
        -EvidencePath 'D:\Contoso\Discovery' -SharePointAdminUrl https://contoso-admin.sharepoint.com -AdminUpn admin@contoso.com

.EXAMPLE
    # GCC High, Graph and Purview only
    ./Invoke-CopilotReadinessAssessment.ps1 -TenantId <guid> -Cloud GCCHigh -Collect Graph,Purview -EvidencePath .\evidence
#>
[CmdletBinding()]
param(
    [string]$TenantId,
    [string]$CustomerName = '',
    [ValidateSet('Commercial', 'GCC', 'GCCHigh')][string]$Cloud = 'Commercial',
    [string[]]$EvidencePath = @(),
    [string]$OutputPath = (Join-Path (Get-Location) 'output'),
    [ValidateSet('Graph', 'SharePoint', 'Purview', 'Exchange', 'PowerPlatform', 'Fabric', 'All')][string[]]$Collect = @('All'),
    [switch]$OfflineOnly,
    [string]$AdminUpn,
    [string]$SharePointAdminUrl,
    [ValidateSet('None', 'Start', 'Export')][string]$DagMode = 'None',
    [ValidateRange(1, 180)][int]$AuditDays = 7,
    [switch]$IncludeRowPreview
)

$ErrorActionPreference = 'Stop'
$ToolkitVersion = '1.0.0'
# pwsh -File passes "a,b" as one string; split lists that arrive that way (paths that exist are kept whole).
$EvidencePath = @($EvidencePath | ForEach-Object { if ($_ -and -not (Test-Path -LiteralPath $_) -and $_ -match ',') { $_ -split ',' | ForEach-Object { $_.Trim() } } else { $_ } } | Where-Object { $_ })
$Collect = @($Collect | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$root = $PSScriptRoot
foreach ($f in 'Common', 'Collect-Graph', 'Collect-SharePoint', 'Collect-Purview', 'Collect-PowerPlatform', 'Import-Evidence', 'Analyze', 'Checks', 'Report') {
    . (Join-Path $root "src/$f.ps1")
}

if (-not $OfflineOnly -and -not $TenantId) { throw 'Provide -TenantId for live collection, or use -OfflineOnly to analyze evidence files only.' }
if ($OfflineOnly -and -not $EvidencePath) { throw '-OfflineOnly needs at least one -EvidencePath folder.' }
if ($TenantId -and $TenantId -notmatch '^[0-9a-fA-F-]{36}$') { throw '-TenantId must be the tenant GUID.' }

$clouds = Get-Content -LiteralPath (Join-Path $root 'config/clouds.json') -Raw | ConvertFrom-Json
$cloudProfile = $clouds.$Cloud
$safeCustomer = if ($CustomerName) { ($CustomerName -replace '[^A-Za-z0-9\-_ ]', '').Trim() -replace '\s+', '-' } else { 'Assessment' }
$outDir = Join-Path $OutputPath ("{0}-{1:yyyyMMdd-HHmmss}" -f $safeCustomer, [datetime]::Now)
New-RunContext -OutDir $outDir -CustomerName $CustomerName -TenantId $TenantId -Cloud $Cloud | Out-Null
$ErrorActionPreference = 'Continue'

Write-Log "Copilot Readiness Assessment Toolkit v$ToolkitVersion"
Write-Log "Output folder: $outDir"
Write-Log ("Mode: {0}; cloud: {1}" -f $(if ($OfflineOnly) { 'Offline (import only)' } else { 'Collect and import' }), $Cloud)

$want = if ($Collect -contains 'All') { @('Graph', 'SharePoint', 'Purview', 'Exchange', 'PowerPlatform', 'Fabric') } else { $Collect }
if (-not $OfflineOnly) {
    if ('Graph' -in $want) { Invoke-GraphCollection -CloudProfile $cloudProfile -TenantId $TenantId -Cloud $Cloud }
    if ('SharePoint' -in $want) {
        if ($SharePointAdminUrl) { Invoke-SharePointCollection -AdminUrl $SharePointAdminUrl -CloudProfile $cloudProfile -DagMode $DagMode }
        else { foreach ($id in 'SPO_Tenant', 'SPO_Sites', 'SPO_OneDrive') { Add-Dataset -Id $id -Workstream 'SharePoint' -Status 'NotRequested' -Source 'Connect-SPOService' -Explanation 'Skipped: -SharePointAdminUrl was not supplied.' } }
    }
    if ('Purview' -in $want) { Invoke-PurviewCollection -CloudProfile $cloudProfile -AdminUpn $AdminUpn }
    if ('Exchange' -in $want) { Invoke-ExchangeCollection -CloudProfile $cloudProfile -AdminUpn $AdminUpn -AuditDays $AuditDays }
    if ('PowerPlatform' -in $want) { Invoke-PowerPlatformCollection -TenantId $TenantId -CloudProfile $cloudProfile -Cloud $Cloud }
    if ('Fabric' -in $want) { Invoke-FabricCollection -TenantId $TenantId -CloudProfile $cloudProfile -Cloud $Cloud }
}

if ($EvidencePath -or $script:Ctx.ExtraEvidenceFolders.Count) {
    Invoke-EvidenceImport -EvidencePath $EvidencePath -RulesPath (Join-Path $root 'config/import-rules.json')
}
else { Write-Log 'No -EvidencePath supplied; portal-only datasets will show as not assessed.' 'Warn' }

Invoke-Analysis
Invoke-Checks
$mode = if ($OfflineOnly) { 'Offline import' } else { 'Collect and import' }
$res = Export-Results -TemplatePath (Join-Path $root 'report/dashboard.template.html') -ToolkitVersion $ToolkitVersion -Mode $mode -IncludeRowPreview:$IncludeRowPreview -RunParameters @{
    collectors = ($(if ($OfflineOnly) { @() } else { $want }) -join ', ')
    evidenceFolders = (@($EvidencePath | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')
    dagMode = $DagMode
}
Write-Log ("Automated readiness indicator: {0}/100 ({1}); {2}% of checks scored" -f $res.Scores.Overall, $res.Scores.Rating, $res.Scores.CoveragePct) 'Ok'
Write-Log "Dashboard: $($res.Html)" 'Ok'
Write-Log "CSV exports: $(Join-Path $outDir 'csv')" 'Ok'
Write-Warning 'The output folder contains tenant data (user names, site URLs, agent names). Store it with client data controls and do not commit it to source control.'
