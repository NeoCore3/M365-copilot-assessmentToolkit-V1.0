# SharePoint Online collectors (read-only) and SharePoint Advanced Management data access governance (DAG) reports.
# Requires Microsoft.Online.SharePoint.PowerShell (keep it current; the DAG cmdlets exist only in recent versions)
# and the SharePoint Administrator role. DAG snapshot reports need SharePoint Advanced Management.

function Connect-SpoAdmin {
    <#
      Microsoft Learn: in PowerShell 7 import the SharePoint module with -UseWindowsPowerShell. The toolkit tries a native
      load first (works with recent module versions), and if the module or the sign-in fails, retries once through
      Windows PowerShell compatibility. Runs in its own process, so no other module's authentication library interferes.
    #>
    param([string]$AdminUrl, $CloudProfile)
    $p = @{ Url = $AdminUrl; ErrorAction = 'Stop' }
    if ($CloudProfile.SharePointRegion -and $CloudProfile.SharePointRegion -ne 'Default') { $p.Region = $CloudProfile.SharePointRegion }
    $firstError = $null
    try {
        $v = Import-ModuleSafe -Name 'Microsoft.Online.SharePoint.PowerShell' -Extra @{ DisableNameChecking = $true }
        Write-Log "Microsoft.Online.SharePoint.PowerShell $v loaded (native)"
        Connect-SPOService @p | Out-Null
        return 'Native'
    }
    catch { $firstError = $_.Exception.Message }
    if (-not $IsWindows) { throw "SharePoint module failed: $firstError (the module is supported on Windows only)" }
    Write-Log "Native SharePoint sign-in failed ($firstError). Retrying through Windows PowerShell compatibility..." 'Warn'
    Remove-Module Microsoft.Online.SharePoint.PowerShell -Force -ErrorAction SilentlyContinue
    Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell -DisableNameChecking -ErrorAction Stop -WarningAction SilentlyContinue
    Connect-SPOService @p | Out-Null
    return 'WindowsPowerShell'
}

function Invoke-SharePointCollection {
    param([string]$AdminUrl, $CloudProfile, [ValidateSet('None', 'Start', 'Export')][string]$DagMode = 'None')
    try {
        Write-Log "Connecting to SharePoint admin $AdminUrl ..."
        $how = Connect-SpoAdmin -AdminUrl $AdminUrl -CloudProfile $CloudProfile
        Write-Log "SharePoint connected ($how)" 'Ok'
    }
    catch {
        $m = Add-Diagnostic 'SharePoint' 'Connect-SPOService' $_ 'Install the latest Microsoft.Online.SharePoint.PowerShell module and use the tenant admin URL (https://<tenant>-admin.sharepoint.com). Requires the SharePoint Administrator role (Learn lists no read-only role for this module). On Windows, Windows PowerShell 5.1 must be present for the compatibility fallback.'
        foreach ($id in 'SPO_Tenant', 'SPO_Sites', 'SPO_OneDrive') { Add-Dataset -Id $id -Workstream 'SharePoint' -Status 'Failed' -Source 'Connect-SPOService' -Explanation $m }
        return
    }
    try {
        try {
            $t = Get-SPOTenant -ErrorAction Stop
            Add-Dataset -Id 'SPO_Tenant' -Workstream 'SharePoint' -Status 'Collected' -Source 'Get-SPOTenant' -Explanation 'SharePoint and OneDrive tenant settings.' -Rows @($t | Select-Object *)
        }
        catch { Add-Dataset -Id 'SPO_Tenant' -Workstream 'SharePoint' -Status 'Failed' -Source 'Get-SPOTenant' -Explanation (Add-Diagnostic 'SharePoint' 'Get-SPOTenant' $_) }

        $props = 'Url', 'Title', 'Template', 'Owner', 'StorageUsageCurrent', 'LastContentModifiedDate', 'SharingCapability', 'SensitivityLabel', 'LockState', 'IsTeamsConnected', 'GroupId'
        try {
            $sites = Get-SPOSite -Limit All -ErrorAction Stop | Select-Object $props
            Add-Dataset -Id 'SPO_Sites' -Workstream 'SharePoint' -Status 'Collected' -Source 'Get-SPOSite -Limit All' -Explanation 'Site inventory (configuration, not item-level permissions).' -Rows $sites
        }
        catch { Add-Dataset -Id 'SPO_Sites' -Workstream 'SharePoint' -Status 'Failed' -Source 'Get-SPOSite' -Explanation (Add-Diagnostic 'SharePoint' 'Get-SPOSite' $_) }
        try {
            $od = Get-SPOSite -IncludePersonalSite $true -Limit All -Filter "Url -like '-my.sharepoint'" -ErrorAction Stop | Select-Object $props
            Add-Dataset -Id 'SPO_OneDrive' -Workstream 'OneDrive' -Status 'Collected' -Source 'Get-SPOSite -IncludePersonalSite' -Explanation 'OneDrive inventory.' -Rows $od
        }
        catch { Add-Dataset -Id 'SPO_OneDrive' -Workstream 'OneDrive' -Status 'Failed' -Source 'Get-SPOSite -IncludePersonalSite' -Explanation (Add-Diagnostic 'SharePoint' 'Get-SPOSite OneDrive' $_) }

        if ($DagMode -eq 'Start') { Start-DagReports }
        elseif ($DagMode -eq 'Export') { Export-DagReports }
    }
    finally { try { Disconnect-SPOService -ErrorAction SilentlyContinue } catch { } }
}

$script:DagDefinitions = @(
    @{ Entity = 'PermissionedUsers'; Type = 'Snapshot'; Workload = 'SharePoint'; Name = 'CRT-PermissionedUsers-SharePoint'; Extra = @{ CountOfUsersMoreThan = 0 } }
    @{ Entity = 'PermissionedUsers'; Type = 'Snapshot'; Workload = 'OneDriveForBusiness'; Name = 'CRT-PermissionedUsers-OneDrive'; Extra = @{ CountOfUsersMoreThan = 0 } }
    @{ Entity = 'EveryoneExceptExternalUsers'; Type = 'Snapshot'; Workload = $null; Name = 'CRT-EEEU-Items' ; Extra = @{} }
    @{ Entity = 'Everyone'; Type = 'Snapshot'; Workload = $null; Name = 'CRT-Everyone-Items'; Extra = @{} }
    @{ Entity = 'SharingLinks_Anyone'; Type = 'RecentActivity'; Workload = 'SharePoint'; Name = 'CRT-Links-Anyone'; Extra = @{} }
    @{ Entity = 'SharingLinks_PeopleInYourOrg'; Type = 'RecentActivity'; Workload = 'SharePoint'; Name = 'CRT-Links-Org'; Extra = @{} }
    @{ Entity = 'EveryoneExceptExternalUsersAtSite'; Type = 'RecentActivity'; Workload = 'SharePoint'; Name = 'CRT-EEEU-Sites'; Extra = @{} }
)

function Start-DagReports {
    foreach ($d in $script:DagDefinitions) {
        try {
            $p = @{ ReportEntity = $d.Entity; ReportType = $d.Type; Name = $d.Name; ErrorAction = 'Stop' }
            if ($d.Workload) { $p.Workload = $d.Workload }
            foreach ($k in $d.Extra.Keys) { $p[$k] = $d.Extra[$k] }
            Start-SPODataAccessGovernanceInsight @p | Out-Null
            Write-Log "DAG report requested: $($d.Name)" 'Ok'
        }
        catch { [void](Add-Diagnostic 'SharePoint DAG' "Start $($d.Entity)" $_ 'Requires SharePoint Advanced Management and a current SharePoint module. Reports can take hours; re-run later with -DagMode Export.') }
    }
    Write-Log 'DAG reports take time to generate. Re-run with -DagMode Export later to download and analyze them.' 'Warn'
}

function Export-DagReports {
    $dir = Join-Path $script:Ctx.OutDir 'raw/dag'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try { $all = @(Get-SPODataAccessGovernanceInsight -ErrorAction Stop) }
    catch { [void](Add-Diagnostic 'SharePoint DAG' 'Get-SPODataAccessGovernanceInsight' $_); return }
    $latest = $all | Where-Object { "$(Get-Prop $_ 'Status')" -match 'complet|succe|ready' } | Group-Object { "$(Get-Prop $_ 'ReportEntity')|$(Get-Prop $_ 'Workload')" } | ForEach-Object { $_.Group | Sort-Object { ConvertTo-Date (Get-Prop $_ 'CreatedDateTime') } -Descending | Select-Object -First 1 }
    if (-not $latest) { Write-Log 'No completed data access governance reports found yet. Re-run later with -DagMode Export.' 'Warn' }
    foreach ($r in $latest) {
        try {
            $rid = Get-Prop $r 'ReportId'; if (-not $rid) { $rid = Get-Prop $r 'Id' }
            Export-SPODataAccessGovernanceInsight -ReportID $rid -DownloadPath $dir -ErrorAction Stop | Out-Null
            Write-Log "DAG report exported: $(Get-Prop $r 'ReportEntity') $(Get-Prop $r 'Workload')" 'Ok'
        }
        catch { [void](Add-Diagnostic 'SharePoint DAG' "Export $(Get-Prop $r 'ReportEntity')" $_) }
    }
    $script:Ctx.ExtraEvidenceFolders += , $dir
}
