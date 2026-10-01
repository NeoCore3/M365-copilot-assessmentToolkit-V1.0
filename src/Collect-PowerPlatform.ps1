# Power Platform and Microsoft Fabric collectors (read-only, best effort). Requires Az.Accounts for delegated tokens.
# Endpoints (Microsoft Learn):
#   Environments (admin):  GET {BapRoot}/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2020-10-01&$expand=properties.capacity
#   Inventory (agents/apps/flows): POST {PowerPlatformApiRoot}/resourcequery/resources/query?api-version=2024-10-01 (delegated user only)
#   Fabric tenant settings: GET {FabricRoot}/v1/admin/tenantsettings (Fabric administrator)
# If token acquisition is refused for a resource, the dataset is marked Failed and the portal export import path applies.

function Get-DelegatedToken {
    param([string]$Resource)
    $t = Get-AzAccessToken -ResourceUrl $Resource -ErrorAction Stop
    $tok = $t.Token
    if ($tok -is [System.Security.SecureString]) { $tok = [System.Net.NetworkCredential]::new('', $tok).Password }
    return $tok
}

function Connect-AzForTokens {
    param([string]$TenantId, $CloudProfile)
    Import-Module Az.Accounts -ErrorAction Stop
    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $ctx -or $ctx.Tenant.Id -ne $TenantId) {
        Write-Log 'Signing in with Az.Accounts for Power Platform and Fabric tokens...'
        Connect-AzAccount -Tenant $TenantId -Environment $CloudProfile.AzEnvironment -ErrorAction Stop | Out-Null
    }
}

function Invoke-PowerPlatformCollection {
    param([string]$TenantId, $CloudProfile, [string]$Cloud)
    if (-not $CloudProfile.PowerPlatformSupported) {
        foreach ($id in 'PP_Environments', 'PP_Inventory') { Add-Dataset -Id $id -Workstream 'PowerPlatform' -Status 'Unsupported' -Source 'Power Platform API' -Explanation "API collection not enabled for $Cloud in v1.0. Import the Power Platform admin center exports." }
        return
    }
    try { Connect-AzForTokens -TenantId $TenantId -CloudProfile $CloudProfile }
    catch {
        $m = Add-Diagnostic 'PowerPlatform' 'Connect-AzAccount' $_ 'Install Az.Accounts. Requires Power Platform Administrator or Dynamics 365 Administrator.'
        foreach ($id in 'PP_Environments', 'PP_Inventory') { Add-Dataset -Id $id -Workstream 'PowerPlatform' -Status 'Failed' -Source 'Az.Accounts' -Explanation $m }
        return
    }
    # Environments
    try {
        $tok = Get-DelegatedToken -Resource $CloudProfile.BapResource
        $url = "$($CloudProfile.BapRoot)/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2020-10-01&`$expand=properties.capacity"
        $rows = [System.Collections.Generic.List[object]]::new()
        while ($url) {
            $r = Invoke-RestMethod -Method GET -Uri $url -Headers @{ Authorization = "Bearer $tok" } -ErrorAction Stop
            foreach ($e in @($r.value)) {
                $cap = @{}; foreach ($c in @($e.properties.capacity)) { if ($c.capacityType) { $cap[$c.capacityType] = $c.actualConsumption } }
                $rows.Add([pscustomobject]@{
                        EnvironmentId = $e.name; DisplayName = $e.properties.displayName; Sku = $e.properties.environmentSku
                        Location = $e.location; IsDefault = $e.properties.isDefault; CreatedTime = $e.properties.createdTime
                        HasDataverse = [bool]$e.properties.linkedEnvironmentMetadata
                        ProtectionLevel = $e.properties.governanceConfiguration.protectionLevel
                        DatabaseMB = $cap['Database']; FileMB = $cap['File']; LogMB = $cap['Log']
                    })
            }
            $url = $r.nextLink
        }
        Add-Dataset -Id 'PP_Environments' -Workstream 'PowerPlatform' -Status ($(if ($rows.Count) { 'Collected' } else { 'Empty' })) -Source 'BAP admin environments API' -Explanation 'Environments with type, Dataverse, governance protection level as returned by the API (verify Managed Environments in the admin center), and capacity consumption in MB.' -Rows $rows.ToArray()
        Write-Log "PP_Environments: $($rows.Count) rows" 'Ok'
    }
    catch { Add-Dataset -Id 'PP_Environments' -Workstream 'PowerPlatform' -Status 'Failed' -Source 'BAP admin environments API' -Explanation (Add-Diagnostic 'PowerPlatform' 'Environments' $_ 'If the token is refused, export environments from the Power Platform admin center and import them.') }
    # Inventory (Copilot Studio agents, apps, flows)
    try {
        $tok = Get-DelegatedToken -Resource $CloudProfile.PowerPlatformApiResource
        $url = "$($CloudProfile.PowerPlatformApiRoot)/resourcequery/resources/query?api-version=2024-10-01"
        $all = [System.Collections.Generic.List[object]]::new(); $skip = $null
        do {
            $body = @{ TableName = 'PowerPlatformResources'; Clauses = @(@{ '$type' = 'where'; FieldName = 'type'; Operator = 'in~'; Values = @("'microsoft.copilotstudio/agents'", "'microsoft.powerautomate/agentflows'", "'microsoft.powerapps/canvasapps'", "'microsoft.powerautomate/cloudflows'") }); Options = @{ Top = 1000 } }
            if ($skip) { $body.Options.SkipToken = $skip }
            $r = Invoke-RestMethod -Method POST -Uri $url -Headers @{ Authorization = "Bearer $tok"; 'Content-Type' = 'application/json' } -Body ($body | ConvertTo-Json -Depth 8) -ErrorAction Stop
            foreach ($i in @($r.data)) {
                $p = $i.properties
                $all.Add([pscustomobject]@{
                        Type = $i.type; Id = $i.name; DisplayName = $p.displayName; EnvironmentId = $p.environmentId
                        CreatedIn = $p.createdIn; Model = $p.model; IsCLIAgent = $p.isCLIAgent; OwnerId = $p.ownerId; CreatedAt = $p.createdAt
                        Connectors = (@($p.powerPlatformConnectors) | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } }) -join ', '
                    })
            }
            $skip = $r.skipToken
        } while ($skip)
        Add-Dataset -Id 'PP_Inventory' -Workstream 'PowerPlatform' -Status ($(if ($all.Count) { 'Collected' } else { 'Empty' })) -Source 'Power Platform inventory API' -Explanation 'Copilot Studio agents, agent flows, canvas apps, and cloud flows.' -Rows $all.ToArray()
        Write-Log "PP_Inventory: $($all.Count) rows" 'Ok'
    }
    catch { Add-Dataset -Id 'PP_Inventory' -Workstream 'PowerPlatform' -Status 'Failed' -Source 'Power Platform inventory API' -Explanation (Add-Diagnostic 'PowerPlatform' 'Inventory' $_ 'The inventory API supports delegated users only. If refused, export Manage > Inventory from the Power Platform admin center and import it.') }
}

function Invoke-FabricCollection {
    param([string]$TenantId, $CloudProfile, [string]$Cloud)
    if (-not $CloudProfile.FabricSupported) { Add-Dataset -Id 'FAB_TenantSettings' -Workstream 'Fabric' -Status 'Unsupported' -Source 'Fabric REST API' -Explanation "API collection not enabled for $Cloud in v1.0."; return }
    try {
        Connect-AzForTokens -TenantId $TenantId -CloudProfile $CloudProfile
        $tok = Get-DelegatedToken -Resource $CloudProfile.FabricResource
        $url = "$($CloudProfile.FabricRoot)/v1/admin/tenantsettings"
        $rows = [System.Collections.Generic.List[object]]::new()
        while ($url) {
            $r = Invoke-RestMethod -Method GET -Uri $url -Headers @{ Authorization = "Bearer $tok" } -ErrorAction Stop
            foreach ($s in @($r.value)) {
                $rows.Add([pscustomobject]@{
                        SettingName = $s.settingName; Title = $s.title; Enabled = $s.enabled; Group = $s.tenantSettingGroup
                        EnabledSecurityGroups = (@($s.enabledSecurityGroups) | ForEach-Object { $_.name }) -join '; '
                        ExcludedSecurityGroups = (@($s.excludedSecurityGroups) | ForEach-Object { $_.name }) -join '; '
                        DelegateToCapacity = $s.delegateToCapacity; DelegateToDomain = $s.delegateToDomain; DelegateToWorkspace = $s.delegateToWorkspace
                    })
            }
            $url = if ($r.continuationToken) { "$($CloudProfile.FabricRoot)/v1/admin/tenantsettings?continuationToken=$([uri]::EscapeDataString($r.continuationToken))" } else { $null }
        }
        Add-Dataset -Id 'FAB_TenantSettings' -Workstream 'Fabric' -Status ($(if ($rows.Count) { 'Collected' } else { 'Empty' })) -Source 'GET /v1/admin/tenantsettings' -Explanation 'Fabric tenant settings, including Copilot and Azure OpenAI settings.' -Rows $rows.ToArray()
        Write-Log "FAB_TenantSettings: $($rows.Count) rows" 'Ok'
    }
    catch { Add-Dataset -Id 'FAB_TenantSettings' -Workstream 'Fabric' -Status 'Failed' -Source 'Fabric REST API' -Explanation (Add-Diagnostic 'Fabric' 'TenantSettings' $_ 'Requires Fabric administrator. If refused, capture the Fabric admin portal tenant settings as screenshots.') }
}
