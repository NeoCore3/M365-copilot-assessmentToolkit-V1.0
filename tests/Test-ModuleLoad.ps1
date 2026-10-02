#Requires -Version 7.2
<#
.SYNOPSIS
    Module compatibility check (run on a Windows machine or the GitHub Actions Windows runner).
    For each collector group, starts a clean PowerShell process, imports the module the way the toolkit does
    (Import-ModuleSafe, skipping known-bad versions), and makes a dummy, non-interactive connection attempt with a fake
    token. An authentication error is expected and counts as a pass; an assembly or type-load error is a failure,
    because that is what stops a real run before any sign-in prompt appears.
    Also reports, for information, what happens when the modules share one process (the cause of the original failures).
#>
param([switch]$SkipSharedProcess)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$pwsh = (Get-Process -Id $PID).Path
$loadError = 'Could not load file or assembly|type initializer|manifest definition|FileLoadException|FileNotFoundException|TypeLoadException|MissingMethodException'
$fail = 0

$probes = [ordered]@{
    Graph      = @'
$v = Import-ModuleSafe -Name 'Microsoft.Graph.Authentication'
"version=$v"
try { Connect-MgGraph -AccessToken (ConvertTo-SecureString 'eyJ0eXAiOiJKV1QifQ.e30.x' -AsPlainText -Force) -NoWelcome -ErrorAction Stop; Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization' -ErrorAction Stop } catch { "error=$($_.Exception.GetType().FullName): $($_.Exception.Message)" }
'@
    Compliance = @'
$v = Import-ModuleSafe -Name 'ExchangeOnlineManagement'
"version=$v"
try { Connect-ExchangeOnline -AccessToken 'eyJ0eXAiOiJKV1QifQ.e30.x' -Organization 'contoso.onmicrosoft.com' -ShowBanner:$false -ErrorAction Stop } catch { "error=$($_.Exception.GetType().FullName): $($_.Exception.Message)" }
'@
    Azure      = @'
$v = Import-ModuleSafe -Name 'Az.Accounts'
"version=$v"
try { Connect-AzAccount -AccessToken 'eyJ0eXAiOiJKV1QifQ.e30.x' -AccountId 'probe@contoso.com' -Tenant '11111111-2222-3333-4444-555555555555' -ErrorAction Stop | Out-Null; Get-AzAccessToken -ResourceUrl 'https://api.fabric.microsoft.com' -ErrorAction Stop | Out-Null } catch { "error=$($_.Exception.GetType().FullName): $($_.Exception.Message)" }
'@
    SharePoint = @'
if (-not $IsWindows) { 'skipped=Windows only'; return }
$v = Import-ModuleSafe -Name 'Microsoft.Online.SharePoint.PowerShell' -Extra @{ DisableNameChecking = $true }
"version=$v"
"commands=$(@(Get-Command Connect-SPOService, Get-SPOTenant, Get-SPOSite, Start-SPODataAccessGovernanceInsight, Export-SPODataAccessGovernanceInsight -ErrorAction SilentlyContinue).Count) of 5"
'@
}

foreach ($k in $probes.Keys) {
    $script = Join-Path ([System.IO.Path]::GetTempPath()) "crt-probe-$k.ps1"
    ". '$root/src/Common.ps1'`n" + $probes[$k] | Set-Content -LiteralPath $script -Encoding utf8
    $out = & $pwsh -NoProfile -NonInteractive -File $script 2>&1 | Out-String
    $bad = $out -match $loadError
    if ($k -eq 'SharePoint' -and $out -match 'commands=(\d) of 5' -and [int]$Matches[1] -lt 5) { $bad = $true }
    Write-Host ("[{0}] {1}: {2}" -f $(if ($bad) { 'FAIL' } else { 'PASS' }), $k, ($out.Trim() -replace '\s+', ' ')) -ForegroundColor $(if ($bad) { 'Red' } else { 'Green' })
    if ($bad) { $fail++; if ($env:GITHUB_ACTIONS) { Write-Host "::error title=Module load ($k)::$(($out.Trim() -replace '\s+', ' ').Substring(0, [math]::Min(900, $out.Trim().Length)))" } }
    Remove-Item $script -ErrorAction SilentlyContinue
}

if (-not $SkipSharedProcess) {
    Write-Host "`nFor information: all modules in ONE process (how v1.0.0 ran)" -ForegroundColor Cyan
    $shared = Join-Path ([System.IO.Path]::GetTempPath()) 'crt-probe-shared.ps1'
    (". '$root/src/Common.ps1'`n" + $probes.Graph + "`n" + $probes.Compliance + "`n" + $probes.Azure) | Set-Content -LiteralPath $shared -Encoding utf8
    $out = & $pwsh -NoProfile -NonInteractive -File $shared 2>&1 | Out-String
    Write-Host ($out.Trim()) -ForegroundColor Gray
    if ($env:GITHUB_ACTIONS) { Write-Host "::notice title=Shared-process result::$((($out.Trim() -replace '\s+', ' ')).Substring(0, [math]::Min(900, $out.Trim().Length)))" }
    Remove-Item $shared -ErrorAction SilentlyContinue
}
if ($fail) { Write-Host "$fail module group(s) failed to load" -ForegroundColor Red; exit 1 }
Write-Host 'All module groups load cleanly in isolated processes' -ForegroundColor Green
