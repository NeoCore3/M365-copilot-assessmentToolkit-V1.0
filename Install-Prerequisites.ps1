#Requires -Version 7.2
<#
.SYNOPSIS
    Installs or updates the PowerShell modules used by the live collectors (current user scope).
    Not needed for -OfflineOnly runs.
#>
param([switch]$SkipAz)
$modules = @(
    @{ Name = 'Microsoft.Graph.Authentication'; Why = 'Microsoft Graph (licenses, users, Copilot reports, Conditional Access, roles)' }
    @{ Name = 'ExchangeOnlineManagement'; Why = 'Security & Compliance (labels, DLP, retention) and audit' }
    @{ Name = 'Microsoft.Online.SharePoint.PowerShell'; Why = 'SharePoint tenant, sites, data access governance reports' }
)
if (-not $SkipAz) { $modules += @{ Name = 'Az.Accounts'; Why = 'Tokens for Power Platform and Fabric APIs' } }
foreach ($m in $modules) {
    $have = Get-Module -ListAvailable -Name $m.Name | Sort-Object Version -Descending | Select-Object -First 1
    try {
        if ($have) { Write-Host "Updating $($m.Name) (installed $($have.Version)) - $($m.Why)"; Update-Module -Name $m.Name -Scope CurrentUser -ErrorAction Stop }
        else { Write-Host "Installing $($m.Name) - $($m.Why)"; Install-Module -Name $m.Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop }
    }
    catch { Write-Warning "$($m.Name): $($_.Exception.Message)" }
}
# Make sure a known-good version is present when the newest release is known to fail (config/modules.json).
$cfg = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config/modules.json') -Raw | ConvertFrom-Json
foreach ($b in $cfg.KnownBad) {
    $installed = @(Get-Module -ListAvailable -Name $b.Name)
    if (-not $installed.Count) { continue }
    $good = @($installed | Where-Object { "$($_.Version)" -notin @($b.Versions) })
    if (-not $good.Count) {
        Write-Host "Installing $($b.Name) $($b.Recommended) alongside $($installed[0].Version): $($b.Reason)"
        try { Install-Module -Name $b.Name -RequiredVersion $b.Recommended -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop } catch { Write-Warning "$($b.Name) $($b.Recommended): $($_.Exception.Message)" }
    }
}
Write-Host 'Done. Keep Microsoft.Online.SharePoint.PowerShell current: the data access governance cmdlets are only in recent versions. Run ./Test-Prerequisites.ps1 to check access requirements.'
