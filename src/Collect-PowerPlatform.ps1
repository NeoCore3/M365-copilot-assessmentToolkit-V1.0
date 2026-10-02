# Power Platform and Microsoft Fabric collectors (read-only). Requires Az.Accounts for delegated tokens.
# Endpoints (Microsoft Learn):
#   Environments (admin):  GET {BapRoot}/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2020-10-01&$expand=properties.capacity
#   Inventory (agents, apps, flows): POST {PowerPlatformApiRoot}/resourcequery/resources/query?api-version=2024-10-01 (delegated user only)
#   Fabric tenant settings: GET {FabricRoot}/v1/admin/tenantsettings (Fabric administrator)
# All response fields are read with Get-Prop: a property the API omits becomes an empty value, never an error.

function Get-DelegatedToken {
    param([string]$Resource)
    $t = $null
    try { $t = Get-AzAccessToken -ResourceUrl $Resource -AsSecureString -ErrorAction Stop -WarningAction SilentlyContinue }
    catch { $t = Get-AzAccessToken -ResourceUrl $Resource -ErrorAction Stop -WarningAction SilentlyContinue }
    $tok = $t.Token
    if ($tok -is [System.Security.SecureString]) { $tok = [System.Net.NetworkCredential]::new('', $tok).Password }
    return $tok
}

function Connect-AzForTokens {
    param([string]$TenantId, $CloudProfile)
    $v = Import-ModuleSafe -Name 'Az.Accounts'
    Write-Log "Az.Accounts $v loaded"
    # Process-scoped settings only; nothing is written to the user's Az configuration.
    try { Update-AzConfig -LoginExperienceV2 Off -DisplayBreakingChangeWarning $false -Scope Process -ErrorAction Stop | Out-Null } catch { }
    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $ctx -or (Get-Prop $ctx 'Tenant.Id') -ne $TenantId) {
        Write-Log 'Signing in with Az.Accounts for Power Platform and Fabric tokens...'
        Connect-AzAccount -Tenant $TenantId -Environment $CloudProfile.AzEnvironment -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
    }
}

function Invoke-PowerPlatformRequest {
    param([string]$Method, [string]$Uri, [string]$Token, $Body)
    $p = @{ Method = $Method; Uri = $Uri; Headers = @{ Authorization = "Bearer $Token" }; ErrorAction = 'Stop' }
    if ($null -ne $Body) { $p.ContentType = 'application/json'; $p.Body = ($Body | ConvertTo-Json -Depth 12 -Compress) }
    try { return Invoke-RestMethod @p }
    catch {
        $detail = ''
        try { $detail = $_.ErrorDetails.Message } catch { }
        if ($detail) { throw "$($_.Exception.Message) $detail" }
        throw
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
        $m = Add-Diagnostic 'PowerPlatform' 'Connect-AzAccount' $_ 'Install Az.Accounts. Environments need Power Platform Administrator; inventory works with Global Reader.'
        foreach ($id in 'PP_Environments', 'PP_Inventory') { Add-Dataset -Id $id -Workstream 'PowerPlatform' -Status 'Failed' -Source 'Az.Accounts' -Explanation $m }
        return
    }
    # Environments
    try {
        $tok = Get-DelegatedToken -Resource $CloudProfile.BapResource
        $url = "$($CloudProfile.BapRoot)/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2020-10-01&`$expand=properties.capacity"
        $rows = [System.Collections.Generic.List[object]]::new()
        $guard = 0
        while ($url -and $guard -lt 200) {
            $guard++
            $r = Invoke-PowerPlatformRequest -Method GET -Uri $url -Token $tok
            foreach ($e in @(Get-Prop $r 'value')) {
                if ($null -eq $e) { continue }
                $cap = @{}
                foreach ($c in @(Get-Prop $e 'properties.capacity')) { $ct = Get-Prop $c 'capacityType'; if ($ct) { $cap[$ct] = Get-Prop $c 'actualConsumption' } }
                $rows.Add([pscustomobject][ordered]@{
                        EnvironmentId   = Get-Prop $e 'name'
                        DisplayName     = Get-Prop $e 'properties.displayName'
                        Sku             = Get-Prop $e 'properties.environmentSku'
                        Location        = Get-Prop $e 'location'
                        IsDefault       = Get-Prop $e 'properties.isDefault'
                        CreatedTime     = Get-Prop $e 'properties.createdTime'
                        HasDataverse    = [bool](Get-Prop $e 'properties.linkedEnvironmentMetadata')
                        ProtectionLevel = Get-Prop $e 'properties.governanceConfiguration.protectionLevel'
                        DatabaseMB      = $cap['Database']; FileMB = $cap['File']; LogMB = $cap['Log']
                    })
            }
            $url = Get-Prop $r 'nextLink'
        }
        Add-Dataset -Id 'PP_Environments' -Workstream 'PowerPlatform' -Status ($(if ($rows.Count) { 'Collected' } else { 'Empty' })) -Source 'BAP admin environments API' -Explanation 'Environments with type, Dataverse, governance protection level as returned by the API (verify Managed Environments in the admin center), and capacity consumption in MB.' -Rows $rows.ToArray()
        Write-Log "PP_Environments: $($rows.Count) rows" 'Ok'
    }
    catch { Add-Dataset -Id 'PP_Environments' -Workstream 'PowerPlatform' -Status 'Failed' -Source 'BAP admin environments API' -Explanation (Add-Diagnostic 'PowerPlatform' 'Environments' $_ 'Requires Power Platform Administrator or Dynamics 365 Administrator. Otherwise export environments from the Power Platform admin center.') }

    # Inventory (Copilot Studio agents, agent flows, apps, cloud flows). Body follows the Microsoft Learn example;
    # "$type" must be the first property of each clause, so every clause is an ordered dictionary.
    try {
        $tok = Get-DelegatedToken -Resource $CloudProfile.PowerPlatformApiResource
        $url = "$($CloudProfile.PowerPlatformApiRoot)/resourcequery/resources/query?api-version=2024-10-01"
        $all = [System.Collections.Generic.List[object]]::new(); $skip = ''; $guard = 0
        do {
            $guard++
            $body = New-InventoryQuery -SkipToken $skip
            $r = Invoke-PowerPlatformRequest -Method POST -Uri $url -Token $tok -Body $body
            foreach ($i in @(Get-Prop $r 'data')) {
                if ($null -eq $i) { continue }
                $conn = @(Get-Prop $i 'properties.powerPlatformConnectors') | Where-Object { $_ } | ForEach-Object { if ($_ -is [string]) { $_ } else { Get-Prop $_ 'name' } }
                $all.Add([pscustomobject][ordered]@{
                        Type                 = Get-Prop $i 'type'
                        Id                   = Get-Prop $i 'name'
                        DisplayName          = Get-Prop $i 'properties.displayName'
                        EnvironmentId        = Get-Prop $i 'properties.environmentId'
                        EnvironmentName      = Get-Prop $i 'environmentName'
                        EnvironmentType      = Get-Prop $i 'environmentType'
                        IsManagedEnvironment = Get-Prop $i 'isManagedEnvironment'
                        CreatedIn            = Get-Prop $i 'properties.createdIn'
                        CreatedAt            = Get-Prop $i 'properties.createdAt'
                        CreatedBy            = Get-Prop $i 'properties.createdBy'
                        OwnerId              = Get-Prop $i 'properties.ownerId'
                        Connectors           = (@($conn) -join ', ')
                    })
            }
            $skip = [string](Get-Prop $r 'skipToken')
        } while ($skip -and $guard -lt 500)
        Add-Dataset -Id 'PP_Inventory' -Workstream 'PowerPlatform' -Status ($(if ($all.Count) { 'Collected' } else { 'Empty' })) -Source 'Power Platform inventory API' -Explanation 'Copilot Studio agents, agent flows, canvas apps, and cloud flows, with environment type and Managed Environment state.' -Rows $all.ToArray()
        Write-Log "PP_Inventory: $($all.Count) rows" 'Ok'
    }
    catch { Add-Dataset -Id 'PP_Inventory' -Workstream 'PowerPlatform' -Status 'Failed' -Source 'Power Platform inventory API' -Explanation (Add-Diagnostic 'PowerPlatform' 'Inventory' $_ 'Delegated sign-in only; Global Reader or Power Platform Administrator. If refused, export Manage > Inventory from the Power Platform admin center and import it.') }
}

function New-InventoryQuery {
    param([string]$SkipToken = '')
    $types = @("'microsoft.copilotstudio/agents'", "'microsoft.powerautomate/agentflows'", "'microsoft.powerapps/canvasapps'", "'microsoft.powerautomate/cloudflows'")
    return [ordered]@{
        Options   = [ordered]@{ Top = 1000; Skip = 0; SkipToken = $SkipToken }
        TableName = 'PowerPlatformResources'
        Clauses   = @(
            [ordered]@{ '$type' = 'extend'; FieldName = 'joinKey'; Expression = 'tolower(tostring(properties.environmentId))' }
            [ordered]@{
                '$type'         = 'join'
                JoinKind        = 'leftouter'
                RightTable      = [ordered]@{
                    TableName = 'PowerPlatformResources'
                    Clauses   = @(
                        [ordered]@{ '$type' = 'where'; FieldName = 'type'; Operator = '=='; Values = @("'microsoft.powerplatform/environments'") }
                        [ordered]@{ '$type' = 'project'; FieldList = @('joinKey = tolower(name)', 'environmentName = properties.displayName', 'environmentType = properties.environmentType', 'isManagedEnvironment = properties.isManaged') }
                    )
                }
                LeftColumnName  = 'joinKey'
                RightColumnName = 'joinKey'
            }
            [ordered]@{ '$type' = 'where'; FieldName = 'type'; Operator = 'in~'; Values = $types }
        )
    }
}

function Invoke-FabricCollection {
    param([string]$TenantId, $CloudProfile, [string]$Cloud)
    if (-not $CloudProfile.FabricSupported) { Add-Dataset -Id 'FAB_TenantSettings' -Workstream 'Fabric' -Status 'Unsupported' -Source 'Fabric REST API' -Explanation "API collection not enabled for $Cloud in v1.0."; return }
    try {
        Connect-AzForTokens -TenantId $TenantId -CloudProfile $CloudProfile
        $tok = Get-DelegatedToken -Resource $CloudProfile.FabricResource
        $base = "$($CloudProfile.FabricRoot)/v1/admin/tenantsettings"
        $url = $base
        $rows = [System.Collections.Generic.List[object]]::new(); $guard = 0
        while ($url -and $guard -lt 100) {
            $guard++
            $r = Invoke-PowerPlatformRequest -Method GET -Uri $url -Token $tok
            $items = @(Get-Prop $r 'tenantSettings') + @(Get-Prop $r 'value')
            foreach ($s in $items) {
                if ($null -eq $s) { continue }
                $rows.Add([pscustomobject][ordered]@{
                        SettingName            = Get-Prop $s 'settingName'
                        Title                  = Get-Prop $s 'title'
                        Enabled                = Get-Prop $s 'enabled'
                        Group                  = Get-Prop $s 'tenantSettingGroup'
                        EnabledSecurityGroups  = (@(Get-Prop $s 'enabledSecurityGroups') | Where-Object { $_ } | ForEach-Object { Get-Prop $_ 'name' }) -join '; '
                        ExcludedSecurityGroups = (@(Get-Prop $s 'excludedSecurityGroups') | Where-Object { $_ } | ForEach-Object { Get-Prop $_ 'name' }) -join '; '
                        DelegateToCapacity     = Get-Prop $s 'delegateToCapacity'
                        DelegateToDomain       = Get-Prop $s 'delegateToDomain'
                        DelegateToWorkspace    = Get-Prop $s 'delegateToWorkspace'
                    })
            }
            $ct = Get-Prop $r 'continuationToken'
            $url = if ($ct) { "$base`?continuationToken=$([uri]::EscapeDataString($ct))" } else { $null }
        }
        Add-Dataset -Id 'FAB_TenantSettings' -Workstream 'Fabric' -Status ($(if ($rows.Count) { 'Collected' } else { 'Empty' })) -Source 'GET /v1/admin/tenantsettings' -Explanation 'Fabric tenant settings, including Copilot and Azure OpenAI settings.' -Rows $rows.ToArray()
        Write-Log "FAB_TenantSettings: $($rows.Count) rows" 'Ok'
    }
    catch { Add-Dataset -Id 'FAB_TenantSettings' -Workstream 'Fabric' -Status 'Failed' -Source 'Fabric REST API' -Explanation (Add-Diagnostic 'Fabric' 'TenantSettings' $_ 'Requires Fabric Administrator. If refused, capture the Fabric admin portal tenant settings as screenshots.') }
}
