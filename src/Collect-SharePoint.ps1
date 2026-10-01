# SharePoint Online collectors (read-only) and SharePoint Advanced Management data access governance (DAG) reports.
# Requires Microsoft.Online.SharePoint.PowerShell. DAG cmdlets need SharePoint Advanced Management and module 16.0.25409 or later
# (EEEU and Everyone item reports need 16.0.27215.12000 or later), per Microsoft Learn.

function Connect-SpoAdmin {
    param([string]$AdminUrl, $CloudProfile)
    $imported = $false
    try { Import-Module Microsoft.Online.SharePoint.PowerShell -ErrorAction Stop -WarningAction SilentlyContinue; $imported = $true }
    catch {
        if ($IsWindows) { Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell -ErrorAction Stop -WarningAction SilentlyContinue; $imported = $true }
        else { throw }
    }
    $p = @{ Url = $AdminUrl; ErrorAction = 'Stop' }
    if ($CloudProfile.SharePointRegion -and $CloudProfile.SharePointRegion -ne 'Default') { $p.Region = $CloudProfile.SharePointRegion }
    Connect-SPOService @p | Out-Null
    return $imported
}

function Invoke-SharePointCollection {
    param([string]$AdminUrl, $CloudProfile, [ValidateSet('None', 'Start', 'Export')][string]$DagMode = 'None')
    try {
        Write-Log "Connecting to SharePoint admin $AdminUrl ..."
        Connect-SpoAdmin -AdminUrl $AdminUrl -CloudProfile $CloudProfile | Out-Null
        Write-Log 'SharePoint connected' 'Ok'
    }
    catch {
        $m = Add-Diagnostic 'SharePoint' 'Connect-SPOService' $_ 'Install the latest Microsoft.Online.SharePoint.PowerShell module and use the tenant admin URL (https://<tenant>-admin.sharepoint.com). Requires SharePoint Administrator or Global Reader where supported.'
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
    $latest = $all | Where-Object { "$($_.Status)" -match 'complet|succe|ready' } | Group-Object { "$($_.ReportEntity)|$($_.Workload)" } | ForEach-Object { $_.Group | Sort-Object { [datetime]$_.CreatedDateTime } -Descending | Select-Object -First 1 }
    foreach ($r in $latest) {
        try {
            Export-SPODataAccessGovernanceInsight -ReportID $r.ReportId -DownloadPath $dir -ErrorAction Stop | Out-Null
            Write-Log "DAG report exported: $($r.ReportEntity) $($r.Workload)" 'Ok'
        }
        catch { [void](Add-Diagnostic 'SharePoint DAG' "Export $($r.ReportEntity)" $_) }
    }
    $script:Ctx.ExtraEvidenceFolders += , $dir
}
