# Microsoft Purview (Security & Compliance PowerShell) and Exchange Online collectors (read-only).
# Requires ExchangeOnlineManagement 3.x.

$script:PurviewCommands = @(
    @{ Id = 'PV_SensitivityLabels'; Cmd = 'Get-Label'; Note = 'Sensitivity labels.' }
    @{ Id = 'PV_LabelPolicies'; Cmd = 'Get-LabelPolicy'; Note = 'Sensitivity label publishing policies.' }
    @{ Id = 'PV_AutoLabelPolicies'; Cmd = 'Get-AutoSensitivityLabelPolicy'; Note = 'Service-side auto-labeling policies (Mode shows simulation or enforcement).' }
    @{ Id = 'PV_DlpPolicies'; Cmd = 'Get-DlpCompliancePolicy'; Note = 'DLP policies (Mode: Enable, TestWithNotifications, TestWithoutNotifications, Disable).' }
    @{ Id = 'PV_DlpRules'; Cmd = 'Get-DlpComplianceRule'; Note = 'DLP rules.' }
    @{ Id = 'PV_RetentionPolicies'; Cmd = 'Get-RetentionCompliancePolicy'; Note = 'Retention policies.' }
    @{ Id = 'PV_RetentionLabels'; Cmd = 'Get-ComplianceTag'; Note = 'Retention labels.' }
)

function Invoke-PurviewCollection {
    param($CloudProfile, [string]$AdminUpn)
    try {
        $v = Import-ModuleSafe -Name 'ExchangeOnlineManagement'; Write-Log "ExchangeOnlineManagement $v loaded"
        $p = @{ ErrorAction = 'Stop'; ShowBanner = $false }
        if ($CloudProfile.ComplianceConnectionUri) { $p.ConnectionUri = $CloudProfile.ComplianceConnectionUri; $p.AzureADAuthorizationEndpointUri = $CloudProfile.ComplianceAuthority }
        if ($AdminUpn) { $p.UserPrincipalName = $AdminUpn }
        Write-Log 'Connecting to Security & Compliance PowerShell...'
        Connect-IPPSSession @p | Out-Null
        Write-Log 'Security & Compliance connected' 'Ok'
    }
    catch {
        $m = Add-Diagnostic 'Purview' 'Connect-IPPSSession' $_ 'Install ExchangeOnlineManagement 3.x. Requires Compliance Administrator, Compliance Data Administrator, or Global Reader.'
        foreach ($c in $script:PurviewCommands) { Add-Dataset -Id $c.Id -Workstream 'Purview' -Status 'Failed' -Source $c.Cmd -Explanation "Connection failed: $m" }
        return
    }
    try {
        foreach ($c in $script:PurviewCommands) {
            try {
                if (-not (Get-Command $c.Cmd -ErrorAction SilentlyContinue)) { Add-Dataset -Id $c.Id -Workstream 'Purview' -Status 'Unsupported' -Source $c.Cmd -Explanation 'Cmdlet not available to this account or tenant.'; continue }
                $rows = @(& $c.Cmd -ErrorAction Stop | Select-Object *)
                $status = if ($rows.Count) { 'Collected' } else { 'Empty' }
                Add-Dataset -Id $c.Id -Workstream 'Purview' -Status $status -Source $c.Cmd -Explanation $c.Note -Rows $rows
                Write-Log ("{0}: {1} rows" -f $c.Id, $rows.Count) 'Ok'
            }
            catch { Add-Dataset -Id $c.Id -Workstream 'Purview' -Status 'Failed' -Source $c.Cmd -Explanation (Add-Diagnostic 'Purview' $c.Cmd $_) }
        }
    }
    finally { try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } catch { } }
}

function Invoke-ExchangeCollection {
    param($CloudProfile, [string]$AdminUpn, [int]$AuditDays = 7)
    try {
        $v = Import-ModuleSafe -Name 'ExchangeOnlineManagement'; Write-Log "ExchangeOnlineManagement $v loaded"
        $p = @{ ErrorAction = 'Stop'; ShowBanner = $false; ExchangeEnvironmentName = $CloudProfile.ExchangeEnvironmentName }
        if ($AdminUpn) { $p.UserPrincipalName = $AdminUpn }
        Write-Log 'Connecting to Exchange Online (audit configuration and Copilot audit sample)...'
        Connect-ExchangeOnline @p | Out-Null
    }
    catch {
        $m = Add-Diagnostic 'Exchange' 'Connect-ExchangeOnline' $_ 'Requires View-Only Audit Logs or Audit Logs role (or Global Reader for configuration).'
        foreach ($id in 'EXO_AuditConfig', 'EXO_CopilotAuditSample') { Add-Dataset -Id $id -Workstream 'Audit' -Status 'Failed' -Source 'Connect-ExchangeOnline' -Explanation $m }
        return
    }
    try {
        try {
            $a = Get-AdminAuditLogConfig -ErrorAction Stop | Select-Object UnifiedAuditLogIngestionEnabled, AdminAuditLogEnabled
            Add-Dataset -Id 'EXO_AuditConfig' -Workstream 'Audit' -Status 'Collected' -Source 'Get-AdminAuditLogConfig' -Explanation 'Unified audit log ingestion state.' -Rows @($a)
        }
        catch { Add-Dataset -Id 'EXO_AuditConfig' -Workstream 'Audit' -Status 'Failed' -Source 'Get-AdminAuditLogConfig' -Explanation (Add-Diagnostic 'Exchange' 'Get-AdminAuditLogConfig' $_) }
        try {
            $end = [datetime]::UtcNow; $start = $end.AddDays(-1 * $AuditDays)
            $res = @(Search-UnifiedAuditLog -StartDate $start -EndDate $end -RecordType CopilotInteraction -ResultSize 5000 -ErrorAction Stop)
            $rows = foreach ($r in $res) {
                $d = $null; try { $d = $r.AuditData | ConvertFrom-Json } catch { }
                [pscustomobject]@{
                    CreationDate = $r.CreationDate; Operation = $r.Operations; RecordType = $r.RecordType
                    AppHost = $d.CopilotEventData.AppHost; Workload = $d.Workload
                    ResourceCount = @($d.CopilotEventData.AccessedResources).Count
                    SensitivityLabelsAccessed = (@($d.CopilotEventData.AccessedResources | ForEach-Object { $_.SensitivityLabelId } | Where-Object { $_ }) | Select-Object -Unique) -join ';'
                }
            }
            $status = if (@($rows).Count) { 'Collected' } else { 'Empty' }
            Add-Dataset -Id 'EXO_CopilotAuditSample' -Workstream 'Audit' -Status $status -Source "Search-UnifiedAuditLog -RecordType CopilotInteraction ($AuditDays days, max 5,000)" -Explanation 'Sample of Copilot interaction audit records. Capped; treat as a sample, not a total. User identities are not exported.' -Rows @($rows)
        }
        catch { Add-Dataset -Id 'EXO_CopilotAuditSample' -Workstream 'Audit' -Status 'Failed' -Source 'Search-UnifiedAuditLog' -Explanation (Add-Diagnostic 'Exchange' 'Search-UnifiedAuditLog' $_ 'Requires an audit role. If CopilotInteraction is not accepted as a RecordType in this module version, search in the Purview portal and import the export.') }
    }
    finally { try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } catch { } }
}
