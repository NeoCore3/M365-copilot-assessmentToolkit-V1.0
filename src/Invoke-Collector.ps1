#Requires -Version 7.2
<#
  Child-process entry point for one collector group. Started by Invoke-CopilotReadinessAssessment.ps1 so that each
  group loads its Microsoft modules into a clean process (the Graph, SharePoint, Exchange Online, and Az modules ship
  conflicting versions of MSAL and System.Text.Json; loading them together makes later sign-ins fail).
  Writes <OutDir>/raw/collector-<Group>.clixml for the parent to merge. Not intended to be run directly.
#>
param(
    [Parameter(Mandatory)][ValidateSet('Graph', 'SharePoint', 'Compliance', 'Azure')][string]$Group,
    [Parameter(Mandatory)][string]$OutDir,
    [string]$TenantId, [string]$Cloud = 'Commercial', [string]$CustomerName = '',
    [string]$Parts = '', [string]$AdminUpn = '', [string]$SharePointAdminUrl = '', [string]$DagMode = 'None',
    [int]$AuditDays = 7, [string]$GraphClientId = '', [string]$TestMocks = ''
)
$ErrorActionPreference = 'Continue'
$src = $PSScriptRoot
foreach ($f in 'Common', 'Collect-Graph', 'Collect-SharePoint', 'Collect-Purview', 'Collect-PowerPlatform') { . (Join-Path $src "$f.ps1") }
if ($TestMocks) { . $TestMocks }   # test harness only

$clouds = Get-Content -LiteralPath (Join-Path (Split-Path $src -Parent) 'config/clouds.json') -Raw | ConvertFrom-Json
$cloudProfile = $clouds.$Cloud
New-RunContext -OutDir $OutDir -CustomerName $CustomerName -TenantId $TenantId -Cloud $Cloud | Out-Null
$want = @($Parts -split ',' | Where-Object { $_ })
$resultPath = Join-Path $OutDir "raw/collector-$Group.clixml"
try {
    switch ($Group) {
        'Graph' { Invoke-GraphCollection -CloudProfile $cloudProfile -TenantId $TenantId -Cloud $Cloud -ClientId $GraphClientId }
        'SharePoint' { Invoke-SharePointCollection -AdminUrl $SharePointAdminUrl -CloudProfile $cloudProfile -DagMode $DagMode }
        'Compliance' {
            if ('Purview' -in $want) { Invoke-PurviewCollection -CloudProfile $cloudProfile -AdminUpn $AdminUpn }
            if ('Exchange' -in $want) { Invoke-ExchangeCollection -CloudProfile $cloudProfile -AdminUpn $AdminUpn -AuditDays $AuditDays }
        }
        'Azure' {
            if ('PowerPlatform' -in $want) { Invoke-PowerPlatformCollection -TenantId $TenantId -CloudProfile $cloudProfile -Cloud $Cloud }
            if ('Fabric' -in $want) { Invoke-FabricCollection -TenantId $TenantId -CloudProfile $cloudProfile -Cloud $Cloud }
        }
    }
}
catch { [void](Add-Diagnostic $Group 'Collector' $_ 'Unexpected collector error; see run.log.') }
finally { Save-CollectorResult -Path $resultPath }
