# Microsoft Graph collectors (read-only). Requires Microsoft.Graph.Authentication.

$script:GraphCollectors = @(
    @{ Id = 'Graph_Organization'; Ws = 'Licensing'; Path = '/v1.0/organization'; Scope = 'Organization.Read.All'; Note = 'Tenant identity.' }
    @{ Id = 'Graph_SubscribedSkus'; Ws = 'Licensing'; Path = '/v1.0/subscribedSkus'; Scope = 'Organization.Read.All'; Note = 'Purchased and consumed units per SKU.' }
    @{ Id = 'Graph_Users'; Ws = 'Licensing'; Path = '/v1.0/users?$select=id,displayName,userPrincipalName,userType,accountEnabled,department,jobTitle,companyName,onPremisesSyncEnabled,assignedLicenses,createdDateTime&$top=999'; Scope = 'User.Read.All'; Note = 'Directory users with license assignments.' }
    @{ Id = 'Graph_ReportSettings'; Ws = 'Licensing'; Path = '/v1.0/admin/reportSettings'; Scope = 'ReportSettings.Read.All'; GlobalOnly = $true; Note = 'Whether usage reports conceal user names (affects joins).' }
    @{ Id = 'Graph_CopilotUsage'; Ws = 'Copilot'; Path = "/v1.0/copilot/reports/getMicrosoft365CopilotUsageUserDetail(period='D180')"; Scope = 'Reports.Read.All'; Csv = $true; Copilot = $true; Note = 'Licensed Microsoft 365 Copilot usage per user, 180 days. Does not include unlicensed Copilot Chat.' }
    @{ Id = 'Graph_CopilotUserCountTrend'; Ws = 'Copilot'; Path = "/v1.0/copilot/reports/getMicrosoft365CopilotUserCountTrend(period='D180')"; Scope = 'Reports.Read.All'; Csv = $true; Copilot = $true; Note = 'Daily enabled and active Copilot users.' }
    @{ Id = 'Graph_CopilotUserCountSummary'; Ws = 'Copilot'; Path = "/v1.0/copilot/reports/getMicrosoft365CopilotUserCountSummary(period='D30')"; Scope = 'Reports.Read.All'; Csv = $true; Copilot = $true; Note = 'Enabled and active Copilot users by app, 30 days.' }
    @{ Id = 'Graph_ActiveUserDetail'; Ws = 'Licensing'; Path = "/v1.0/reports/getOffice365ActiveUserDetail(period='D30')"; Scope = 'Reports.Read.All'; Csv = $true; Note = 'Microsoft 365 app activity per user, 30 days.' }
    @{ Id = 'Graph_ConditionalAccess'; Ws = 'Identity'; Path = '/v1.0/identity/conditionalAccess/policies'; Scope = 'Policy.Read.All'; Note = 'Conditional Access policies.' }
    @{ Id = 'Graph_SecurityDefaults'; Ws = 'Identity'; Path = '/v1.0/policies/identitySecurityDefaultsEnforcementPolicy'; Scope = 'Policy.Read.All'; Note = 'Security defaults state.' }
    @{ Id = 'Graph_RoleDefinitions'; Ws = 'Identity'; Path = '/v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName,templateId'; Scope = 'RoleManagement.Read.Directory'; Note = 'Directory role definitions.' }
    @{ Id = 'Graph_RoleAssignments'; Ws = 'Identity'; Path = '/v1.0/roleManagement/directory/roleAssignments?$expand=principal'; Scope = 'RoleManagement.Read.Directory'; Note = 'Active directory role assignments (eligible PIM assignments are not included).' }
    @{ Id = 'Graph_SharePointSettings'; Ws = 'SharePoint'; Path = '/v1.0/admin/sharepoint/settings'; Scope = 'SharePointTenantSettings.Read.All'; Note = 'SharePoint tenant sharing settings.' }
    @{ Id = 'Graph_CopilotPackages'; Ws = 'Agents'; Path = '/v1.0/copilot/admin/catalog/packages'; Scope = 'CopilotPackages.Read.All'; GlobalOnly = $true; Note = 'Agents and apps in the Microsoft 365 admin center catalog, including pending requests. Microsoft Learn states the package API requires a Microsoft Agent 365 license.' }
    @{ Id = 'Graph_SecureScore'; Ws = 'Security'; Path = '/v1.0/security/secureScores?$top=1'; Scope = 'SecurityEvents.Read.All'; Single = $true; Note = 'Latest Microsoft Secure Score. Requires Security Reader or Security Administrator.' }
)

function Get-GraphScopes { return @($script:GraphCollectors | ForEach-Object { $_.Scope } | Select-Object -Unique) }

function Invoke-GraphPaged {
    param([string]$Url, [switch]$Csv, [switch]$Single, [string]$GraphRoot)
    $rows = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $next = $Url
    while ($next) {
        if (-not $seen.Add($next)) { throw "Repeated nextLink: $next" }
        if (([uri]$next).Host -ne ([uri]$GraphRoot).Host) { throw 'Refusing nextLink outside the selected Graph cloud.' }
        if ($Csv) {
            $tmp = Join-Path $script:Ctx.OutDir ('raw/tmp_' + [guid]::NewGuid().ToString('N') + '.csv')
            try {
                Invoke-MgGraphRequest -Method GET -Uri $next -OutputFilePath $tmp | Out-Null
                $body = Get-Content -LiteralPath $tmp -Raw -Encoding utf8
                if ([string]::IsNullOrWhiteSpace($body)) { break }
                $body = $body.TrimStart([char]0xFEFF)
                if ($body.TrimStart().StartsWith('{')) {
                    $j = $body | ConvertFrom-Json
                    foreach ($r in @($j.value)) { $rows.Add($r) }
                    $next = $j.'@odata.nextLink'
                }
                else { foreach ($r in @($body | ConvertFrom-Csv)) { $rows.Add($r) }; $next = $null }
            }
            finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
        else {
            $page = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject
            if ($Single -and $page.PSObject.Properties['value']) { foreach ($r in @($page.value | Select-Object -First 1)) { $rows.Add($r) }; break }
            if ($page.PSObject.Properties['value']) { foreach ($r in @($page.value)) { $rows.Add($r) } } else { $rows.Add($page) }
            $next = $page.'@odata.nextLink'
        }
    }
    return , $rows.ToArray()
}

function Invoke-GraphCollection {
    param($CloudProfile, [string]$TenantId, [string]$Cloud, [string]$ClientId)
    try {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        $p = @{ TenantId = $TenantId; Environment = $CloudProfile.MgEnvironment; Scopes = (Get-GraphScopes); ContextScope = 'Process'; NoWelcome = $true; ErrorAction = 'Stop' }
        if ($ClientId) { $p.ClientId = $ClientId }
        Write-Log 'Connecting to Microsoft Graph (sign in with a read-only admin account)...'
        Connect-MgGraph @p | Out-Null
        $ctx = Get-MgContext
        if ($ctx.TenantId -ne $TenantId) { throw "Signed-in tenant $($ctx.TenantId) does not match -TenantId $TenantId." }
        Write-Log "Graph connected as $($ctx.Account)" 'Ok'
    }
    catch {
        $m = Add-Diagnostic 'Graph' 'Connect-MgGraph' $_ 'Install Microsoft.Graph.Authentication, confirm the tenant ID, and consent to the read-only scopes listed in docs/SETUP.md.'
        foreach ($c in $script:GraphCollectors) { Add-Dataset -Id $c.Id -Workstream $c.Ws -Status 'Failed' -Source $c.Path -Explanation "Graph connection failed: $m" }
        return
    }
    try {
        foreach ($c in $script:GraphCollectors) {
            if (($c.Copilot -or $c.GlobalOnly) -and -not $CloudProfile.CopilotReportsSupported) {
                Add-Dataset -Id $c.Id -Workstream $c.Ws -Status 'Unsupported' -Source $c.Path -Explanation "Microsoft Learn lists this API for the global service only (not US Government L4/L5). Import the portal export instead where one exists."
                continue
            }
            $url = $CloudProfile.GraphRoot + $c.Path
            try {
                $rows = Invoke-GraphPaged -Url $url -Csv:([bool]$c.Csv) -Single:([bool]$c.Single) -GraphRoot $CloudProfile.GraphRoot
                $status = if (@($rows).Count -gt 0) { 'Collected' } else { 'Empty' }
                Add-Dataset -Id $c.Id -Workstream $c.Ws -Status $status -Origin 'Collected' -Source $c.Path -Explanation $c.Note -Rows $rows
                Write-Log ("{0}: {1} rows" -f $c.Id, @($rows).Count) 'Ok'
            }
            catch {
                $m = Add-Diagnostic 'Graph' $c.Id $_ "Requires $($c.Scope) and a role that can read this data."
                Add-Dataset -Id $c.Id -Workstream $c.Ws -Status 'Failed' -Source $c.Path -Explanation $m
                Write-Log ("{0}: failed ({1})" -f $c.Id, $m) 'Warn'
            }
        }
    }
    finally { try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch { } }
}
