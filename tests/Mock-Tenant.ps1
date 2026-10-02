# Mock tenant for tests. Dot-sourced into the collector child process (via $env:CRT_TEST_MOCKS) to replace every
# Microsoft cmdlet and REST call with realistic responses, including omitted properties, paging, CSV report output,
# and error paths, so the live collectors can be exercised end to end without a tenant.

function Import-ModuleSafe { [CmdletBinding()] param([string]$Name, [hashtable]$Extra) return '0.0.0-mock' }
function Remove-Module { }

# ---------- Microsoft Graph ----------
$script:MockTenant = '11111111-2222-3333-4444-555555555555'
function Connect-MgGraph { [CmdletBinding()] param($TenantId, $Environment, $Scopes, $ContextScope, [switch]$NoWelcome, $ClientId) }
function Disconnect-MgGraph { }
function Get-MgContext { [pscustomobject]@{ TenantId = $script:MockTenant; Account = 'reader@contoso.com' } }

function Invoke-MgGraphRequest {
    [CmdletBinding()] param($Method, $Uri, $OutputType, $OutputFilePath)
    $path = ([uri]$Uri).AbsolutePath + ([uri]$Uri).Query
    $json = $null; $csv = $null
    switch -Regex ($path) {
        '/organization' { $json = '{"value":[{"id":"t1","displayName":"Contoso"}]}'; break }
        '/subscribedSkus' { $json = '{"value":[{"skuId":"639dec6b-bb19-468b-871c-c5c441c4b0cb","skuPartNumber":"Microsoft_365_Copilot","consumedUnits":90,"prepaidUnits":{"enabled":100}},{"skuId":"05e9a617-0261-4cee-bb44-138d3ef5d965","skuPartNumber":"SPE_E3","consumedUnits":300}]}'; break }
        '/users\?.*skiptoken=page2' { $json = '{"value":[{"id":"u3","userPrincipalName":"guest_x@contoso.com","userType":"Guest","assignedLicenses":[]}]}'; break }
        '/users' { $json = '{"value":[{"id":"u1","userPrincipalName":"a@contoso.com","userType":"Member","assignedLicenses":[{"skuId":"639dec6b-bb19-468b-871c-c5c441c4b0cb"}]},{"id":"u2","userPrincipalName":"b@contoso.com","userType":"Member","assignedLicenses":[{"skuId":"05e9a617-0261-4cee-bb44-138d3ef5d965"}]}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/users?$skiptoken=page2"}'; break }
        '/admin/reportSettings' { $json = '{"displayConcealedNames":false}'; break }
        'getMicrosoft365CopilotUsageUserDetail' { $json = '{"value":[{"reportRefreshDate":"2026-09-28","userPrincipalName":"a@contoso.com","lastActivityDate":"2026-09-27","microsoftTeamsCopilotLastActivityDate":"2026-09-27","wordCopilotLastActivityDate":""},{"reportRefreshDate":"2026-09-28","userPrincipalName":"c@contoso.com","lastActivityDate":""}]}'; break }
        'getMicrosoft365CopilotUserCount' { $json = '{"value":[{"reportRefreshDate":"2026-09-28","enabledUsers":100,"activeUsers":80}]}'; break }
        'getOffice365ActiveUserDetail' { $csv = "Report Refresh Date,User Principal Name,Has Exchange License`n2026-09-28,a@contoso.com,True`n"; break }
        '/conditionalAccess/policies' { $json = '{"value":[{"displayName":"MFA all","state":"enabled","conditions":{"users":{"includeUsers":["All"]},"clientAppTypes":["all"]},"grantControls":{"builtInControls":["mfa"]}},{"displayName":"Block legacy","state":"enabled","conditions":{"users":{"includeUsers":["All"]},"clientAppTypes":["exchangeActiveSync","other"]},"grantControls":{"builtInControls":["block"]}},{"displayName":"Report only","state":"enabledForReportingButNotEnforced"}]}'; break }
        'identitySecurityDefaultsEnforcementPolicy' { $json = '{"isEnabled":false}'; break }
        'roleDefinitions' { $json = '{"value":[{"id":"62e90394-69f5-4237-9190-012177145e10","templateId":"62e90394-69f5-4237-9190-012177145e10","displayName":"Global Administrator"},{"id":"ai1","templateId":"ai1","displayName":"AI Administrator"}]}'; break }
        'roleAssignments' { $json = '{"value":[{"roleDefinitionId":"62e90394-69f5-4237-9190-012177145e10","principal":{"id":"p1"}},{"roleDefinitionId":"62e90394-69f5-4237-9190-012177145e10"},{"roleDefinitionId":"ai1"}]}'; break }
        '/admin/sharepoint/settings' { $json = '{"sharingCapability":"externalUserSharingOnly"}'; break }
        'copilot/admin/catalog/packages' { throw 'Response status code does not indicate success: Forbidden (Forbidden). Agent 365 license required.' }
        'secureScores' { $json = '{"value":[{"currentScore":55.5,"maxScore":100}]}'; break }
        default { throw "Mock Graph: unhandled $path" }
    }
    if ($OutputFilePath) { Set-Content -LiteralPath $OutputFilePath -Value $(if ($csv) { $csv } else { $json }) -Encoding utf8; return }
    if ($csv) { return $csv }
    return ($json | ConvertFrom-Json)
}

# ---------- SharePoint ----------
function Connect-SPOService { [CmdletBinding()] param($Url, $Region) }
function Disconnect-SPOService { }
function Get-SPOTenant { [pscustomobject]@{ SharingCapability = 'ExternalUserSharingOnly'; OneDriveSharingCapability = 'Disabled'; DefaultSharingLinkType = 'Internal' } }
function Get-SPOSite {
    [CmdletBinding()] param($Limit, $IncludePersonalSite, $Filter)
    if ($IncludePersonalSite) { return @([pscustomobject]@{ Url = 'https://contoso-my.sharepoint.com/personal/a'; LastContentModifiedDate = (Get-Date).AddDays(-3) }) }
    return @([pscustomobject]@{ Url = 'https://contoso.sharepoint.com/sites/a'; Title = 'A'; LastContentModifiedDate = (Get-Date).AddDays(-400) }, [pscustomobject]@{ Url = 'https://contoso.sharepoint.com/sites/b'; Title = 'B'; LastContentModifiedDate = (Get-Date).AddDays(-2) })
}
function Get-SPODataAccessGovernanceInsight { @([pscustomobject]@{ ReportId = 'r1'; ReportEntity = 'EveryoneExceptExternalUsers'; Workload = $null; Status = 'Completed'; CreatedDateTime = '2026-09-28T00:00:00Z' }) }
function Export-SPODataAccessGovernanceInsight {
    [CmdletBinding()] param($ReportID, $DownloadPath)
    "Tenant ID,Site ID,Item type,Item url,Role definition,Recipient,Parent group type,Total user count`nt,s1,File,sites/a/doc.docx,Edit,Everyone except external users,SharePointGroup,500`n" | Set-Content -LiteralPath (Join-Path $DownloadPath 'EEEU-report.csv') -Encoding utf8
}
function Start-SPODataAccessGovernanceInsight { }

# ---------- Purview and Exchange ----------
function Connect-IPPSSession { }
function Connect-ExchangeOnline { }
function Disconnect-ExchangeOnline { }
function Get-Label { @([pscustomobject]@{ Name = 'General' }, [pscustomobject]@{ Name = 'Confidential' }) }
function Get-LabelPolicy { @([pscustomobject]@{ Name = 'Default policy' }) }
function Get-AutoSensitivityLabelPolicy { @([pscustomobject]@{ Name = 'Auto PII'; Mode = 'TestWithoutNotifications' }) }
function Get-DlpCompliancePolicy { @([pscustomobject]@{ Name = 'Copilot prompts'; Mode = 'TestWithNotifications'; Workload = 'Applications'; Locations = 'Microsoft365Copilot' }, [pscustomobject]@{ Name = 'Exchange PII'; Mode = 'Enable' }) }
function Get-DlpComplianceRule { @() }
function Get-RetentionCompliancePolicy { @([pscustomobject]@{ Name = 'Keep 7 years' }) }
function Get-ComplianceTag { @() }
function Get-AdminAuditLogConfig { [pscustomobject]@{ UnifiedAuditLogIngestionEnabled = $true; AdminAuditLogEnabled = $true } }
function Search-UnifiedAuditLog {
    [CmdletBinding()] param($StartDate, $EndDate, $RecordType, $ResultSize)
    @([pscustomobject]@{ CreationDate = (Get-Date); Operations = 'CopilotInteraction'; RecordType = 'CopilotInteraction'; AuditData = '{"Workload":"Copilot","CopilotEventData":{"AppHost":"Word","AccessedResources":[{"SensitivityLabelId":"l1"},{}]}}' },
      [pscustomobject]@{ CreationDate = (Get-Date); Operations = 'CopilotInteraction'; RecordType = 'CopilotInteraction'; AuditData = '{"Workload":"Copilot"}' })
}

# ---------- Az, Power Platform, Fabric ----------
function Get-AzContext { $null }
function Connect-AzAccount { }
function Update-AzConfig { }
function Get-AzAccessToken { [CmdletBinding()] param($ResourceUrl, [switch]$AsSecureString) [pscustomobject]@{ Token = (ConvertTo-SecureString 'mock-token' -AsPlainText -Force) } }
function Invoke-RestMethod {
    [CmdletBinding()] param($Method, $Uri, $Headers, $ContentType, $Body)
    if ($Uri -match 'scopes/admin/environments') {
        return ('{"value":[{"name":"Default-1","location":"unitedstates","properties":{"displayName":"Contoso (default)","isDefault":true,"environmentSku":"Default","capacity":[{"capacityType":"Database","actualConsumption":1024}]}},{"name":"prod","properties":{"displayName":"Prod","environmentSku":"Production","linkedEnvironmentMetadata":{"instanceUrl":"x"}}}]}' | ConvertFrom-Json)
    }
    if ($Uri -match 'resourcequery') {
        $b = $Body | ConvertFrom-Json
        foreach ($c in $b.Clauses) { if (($Body -split '"Clauses":\[')[1] -notmatch '^\{"\$type"') { throw 'Response status code does not indicate success: 400 (Bad Request). $type must be first.' } }
        if ($b.Options.SkipToken -eq 'p2') { return ('{"data":[{"type":"microsoft.copilotstudio/agents","name":"a3","properties":{"displayName":"Agent 3","createdBy":"u2"},"environmentType":"Production","isManagedEnvironment":true}],"count":1}' | ConvertFrom-Json) }
        return ('{"skipToken":"p2","data":[{"type":"microsoft.copilotstudio/agents","name":"a1","properties":{"displayName":"Agent 1","environmentId":"Default-1","createdBy":"u1"},"environmentType":"Default","isManagedEnvironment":false},{"type":"microsoft.copilotstudio/agents","name":"a2","properties":{"displayName":"Agent 2"},"environmentType":"Default"},{"type":"microsoft.powerapps/canvasapps","name":"app1","properties":{}}]}' | ConvertFrom-Json)
    }
    if ($Uri -match 'tenantsettings') {
        if ($Uri -match 'continuationToken') { return ('{"tenantSettings":[{"settingName":"AISkillArtifactTenantSwitch","title":"Data agent","enabled":false}]}' | ConvertFrom-Json) }
        return ('{"tenantSettings":[{"settingName":"CopilotTenantSwitch","title":"Users can use Copilot","enabled":true,"enabledSecurityGroups":[{"name":"Pilot"}]},{"settingName":"OpenAITenantSwitch","title":"Azure OpenAI","enabled":true}],"continuationToken":"c2"}' | ConvertFrom-Json)
    }
    throw "Mock REST: unhandled $Uri"
}
