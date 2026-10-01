#Requires -Version 7.2
<#
.SYNOPSIS
    Checks the local machine before a live run: PowerShell version, required modules, and output folder access.
    Prints the access the assessment account needs (see docs/PERMISSIONS.md). Makes no connection to the tenant.
.EXAMPLE
    ./Test-Prerequisites.ps1
.EXAMPLE
    ./Test-Prerequisites.ps1 -Collect Graph, Purview
#>
param([ValidateSet('Graph', 'SharePoint', 'Purview', 'Exchange', 'PowerPlatform', 'Fabric', 'All')][string[]]$Collect = @('All'))

$want = if ($Collect -contains 'All') { @('Graph', 'SharePoint', 'Purview', 'Exchange', 'PowerPlatform', 'Fabric') } else { $Collect }
$ok = $true
function Line([string]$State, [string]$Text) {
    $c = @{ OK = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; INFO = 'Gray' }[$State]
    Write-Host ('[{0,-4}] {1}' -f $State, $Text) -ForegroundColor $c
}

Write-Host "`nLocal requirements" -ForegroundColor Cyan
if ($PSVersionTable.PSVersion -ge [version]'7.2') { Line OK "PowerShell $($PSVersionTable.PSVersion)" } else { Line FAIL "PowerShell $($PSVersionTable.PSVersion); 7.2 or later is required"; $ok = $false }
Line INFO ("OS: {0}" -f [System.Runtime.InteropServices.RuntimeInformation]::OSDescription)

$mods = [ordered]@{
    'Microsoft.Graph.Authentication'         = @('Graph')
    'Microsoft.Online.SharePoint.PowerShell' = @('SharePoint')
    'ExchangeOnlineManagement'               = @('Purview', 'Exchange')
    'Az.Accounts'                            = @('PowerPlatform', 'Fabric')
}
foreach ($m in $mods.Keys) {
    $needed = @($mods[$m] | Where-Object { $_ -in $want })
    if (-not $needed) { continue }
    $have = Get-Module -ListAvailable -Name $m | Sort-Object Version -Descending | Select-Object -First 1
    if ($have) { Line OK "$m $($have.Version) (used by $($needed -join ', '))" }
    else { Line FAIL "$m not installed (needed by $($needed -join ', ')). Run ./Install-Prerequisites.ps1"; $ok = $false }
}
if ('SharePoint' -in $want -and -not $IsWindows) { Line WARN 'Microsoft.Online.SharePoint.PowerShell is supported on Windows. On macOS or Linux, skip -Collect SharePoint and import the SharePoint admin center exports instead.' }
if ('Exchange' -in $want) {
    $exo = Get-Module -ListAvailable -Name ExchangeOnlineManagement | Sort-Object Version -Descending | Select-Object -First 1
    if ($exo -and $exo.Version -lt [version]'3.0.0') { Line WARN 'ExchangeOnlineManagement 3.x or later is recommended.' }
}
try { $t = Join-Path ([System.IO.Path]::GetTempPath()) ('crt-' + [guid]::NewGuid()); Set-Content $t 'x'; Remove-Item $t; Line OK 'Temporary folder is writable' } catch { Line FAIL 'Cannot write to the temporary folder'; $ok = $false }

Write-Host "`nAccess the assessment account needs (details: docs/PERMISSIONS.md)" -ForegroundColor Cyan
$access = [ordered]@{
    Graph         = 'Global Reader + Reports Reader + Security Reader. Admin consent for the Graph scopes (once).'
    SharePoint    = 'SharePoint Administrator (activate through PIM for the run). SharePoint Advanced Management for DAG snapshot reports.'
    Purview       = 'Global Reader (Purview Global Reader role group), or Compliance Administrator.'
    Exchange      = 'View-Only Audit Logs (Exchange Online) for Search-UnifiedAuditLog and the audit configuration check.'
    PowerPlatform = 'Power Platform Administrator (environments); Global Reader is enough for the inventory API.'
    Fabric        = 'Fabric Administrator.'
}
foreach ($k in $access.Keys) { if ($k -in $want) { Line INFO ("{0,-13} {1}" -f $k, $access[$k]) } }

Write-Host ''
if ($ok) { Line OK 'Local prerequisites met. Confirm the account roles above with the client before the run.' } else { Line FAIL 'Fix the items above, or run with -OfflineOnly to analyze portal exports without sign-in.' }
