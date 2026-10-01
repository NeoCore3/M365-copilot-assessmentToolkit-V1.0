# Checks: compare metrics with documented thresholds. Thresholds are SHI delivery conventions unless the
# recommendation cites a Microsoft Learn limit; they are listed in docs/CHECKS.md.
# Status values:
#   Pass, Warn, Fail   scored
#   Info               measured, not scored (context such as demand or usage counts)
#   Manual             no API or export exists; verify in the named portal
#   NotAssessed        the data needed was not collected or imported; never scored as a failure

$script:Learn = @{
    UsageReport      = 'https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-usage'
    ReadinessReport  = 'https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-readiness'
    ChatReport       = 'https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-copilot-usage'
    SearchReport     = 'https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-search-usage'
    AgentsReport     = 'https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-agents'
    VivaDashboard    = 'https://learn.microsoft.com/en-us/viva/insights/org-team-insights/copilot-dashboard'
    Licensing        = 'https://learn.microsoft.com/en-us/microsoft-365/copilot/microsoft-365-copilot-licensing'
    Adoption         = 'https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-enablement-resources'
    CopilotPage      = 'https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-page'
    Blueprint        = 'https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-blueprint-oversharing'
    Dag              = 'https://learn.microsoft.com/en-us/sharepoint/data-access-governance-reports'
    Rac              = 'https://learn.microsoft.com/en-us/sharepoint/restricted-access-control'
    Rss              = 'https://learn.microsoft.com/en-us/sharepoint/restricted-sharepoint-search'
    SiteReview       = 'https://learn.microsoft.com/en-us/sharepoint/site-access-review'
    Lifecycle        = 'https://learn.microsoft.com/en-us/sharepoint/site-lifecycle-management'
    Labels           = 'https://learn.microsoft.com/en-us/purview/sensitivity-labels'
    LibraryLabel     = 'https://learn.microsoft.com/en-us/purview/sensitivity-labels-sharepoint-default-label'
    CopilotDlp       = 'https://learn.microsoft.com/en-us/purview/dlp-microsoft365-copilot-location-learn-about'
    AutoLabel        = 'https://learn.microsoft.com/en-us/purview/apply-sensitivity-label-automatically'
    Retention        = 'https://learn.microsoft.com/en-us/purview/retention-policies-copilot'
    AuditCopilot     = 'https://learn.microsoft.com/en-us/purview/audit-copilot'
    AuditOn          = 'https://learn.microsoft.com/en-us/purview/audit-log-enable-disable'
    Dspm             = 'https://learn.microsoft.com/en-us/purview/dspm-for-ai'
    Irm              = 'https://learn.microsoft.com/en-us/purview/insider-risk-management-policy-templates'
    CaMfa            = 'https://learn.microsoft.com/en-us/entra/identity/conditional-access/policy-all-users-mfa-strength'
    CaLegacy         = 'https://learn.microsoft.com/en-us/entra/identity/conditional-access/policy-block-legacy-authentication'
    SecDefaults      = 'https://learn.microsoft.com/en-us/entra/fundamentals/security-defaults'
    RoleBest         = 'https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/best-practices'
    AiAdmin          = 'https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference#ai-administrator'
    SecureScore      = 'https://learn.microsoft.com/en-us/defender-xdr/microsoft-secure-score'
    Channels         = 'https://learn.microsoft.com/en-us/microsoft-365-apps/updates/overview-update-channels'
    ManagedEnv       = 'https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-overview'
    EnvStrategy      = 'https://learn.microsoft.com/en-us/power-platform/guidance/adoption/environment-strategy'
    StudioGov        = 'https://learn.microsoft.com/en-us/microsoft-copilot-studio/security-and-governance'
    StudioAuth       = 'https://learn.microsoft.com/en-us/microsoft-copilot-studio/configuration-end-user-authentication'
    ManageAgents     = 'https://learn.microsoft.com/en-us/microsoft-365/admin/manage/manage-copilot-agents-integrated-apps'
    FabricCopilot    = 'https://learn.microsoft.com/en-us/fabric/admin/service-admin-portal-copilot'
    Capacity         = 'https://learn.microsoft.com/en-us/power-platform/admin/capacity-storage'
}

# Threshold text for checks whose rule is not a simple numeric band (shown even when the check is not assessed).
$script:RuleText = @{
    'LIC-01' = 'Pass >= 90% of purchased licenses assigned; Warn >= 75%; otherwise Fail (Info when only report counts exist)'
    'CCS-01' = 'Pass >= 1 active AI Administrator assignment; otherwise Warn'
    'ID-01'  = 'Pass when an enforced all-users MFA or authentication strength policy exists, or security defaults are on'
    'ID-02'  = 'Pass when legacy authentication is blocked by an enforced policy or security defaults'
    'DA-07'  = 'Pass: Disabled or existing guests only; Warn: new and existing guests; Fail: Anyone'
    'DA-08'  = 'Pass: Direct (Specific people); Warn: Internal; Fail: AnonymousAccess'
    'IP-03'  = 'Pass: at least one enforced policy; Warn: policies exist but none enforced; Fail: none'
    'IP-04'  = 'Pass: enforced Copilot policy; Warn: simulation only; Fail: none'
    'IP-05'  = 'Pass: at least one enforced policy; Warn: simulation only; Fail: none'
    'LC-02'  = 'Pass: at least one retention policy; otherwise Warn'
    'AM-01'  = 'Pass: UnifiedAuditLogIngestionEnabled = True; otherwise Fail'
    'AM-02'  = 'Pass: more than 0 CopilotInteraction records; otherwise Warn'
    'AG-03'  = 'Pass: 0 agents with a risk level; otherwise Warn'
    'FB-01'  = 'Informational'
    'GOV-01' = 'Warn when no AI app has a data protection policy; otherwise Info'
}

$script:RiskWeight = @{ Critical = 4; High = 3; Medium = 2; Low = 1 }
$script:StatusPoints = @{ Pass = 1.0; Warn = 0.5; Fail = 0.0 }

function Add-Check {
    param(
        [string]$Id, [string]$Domain, [string]$Title, [ValidateSet('Critical', 'High', 'Medium', 'Low')][string]$Risk,
        [ValidateSet('Pass', 'Warn', 'Fail', 'Info', 'Manual', 'NotAssessed')][string]$Status,
        [string]$Finding, [string]$Recommendation, [string[]]$Links = @(), [string[]]$Metrics = @(), [string]$Threshold = '', [string]$DataNeeded = ''
    )
    if (-not $Threshold) {
        if ($Status -eq 'Info') { $Threshold = 'Informational' }
        elseif ($Status -eq 'Manual') { $Threshold = 'Manual verification' }
        elseif ($script:RuleText.ContainsKey($Id)) { $Threshold = $script:RuleText[$Id] }
    }
    $sources = @($Metrics | Where-Object { Test-Metric $_ } | ForEach-Object { $script:Ctx.Metrics[$_].Source } | ForEach-Object { $_ -split ' \| ' } | Select-Object -Unique)
    $script:Ctx.Checks.Add([pscustomobject][ordered]@{
            Id = $Id; Domain = $Domain; DomainName = $script:Domains[$Domain].Name; Title = $Title; Risk = $Risk; Status = $Status
            Finding = $Finding; Recommendation = $Recommendation; Threshold = $Threshold; DataNeeded = $DataNeeded
            Evidence = ($sources -join ' | '); Metrics = ($Metrics -join ', '); Learn = ($Links -join ' ')
        })
}

function Get-Band {
    <# Returns Pass/Warn/Fail. Direction 'Lower' means lower values are better. #>
    param([double]$Value, [double]$PassAt, [double]$WarnAt, [ValidateSet('Lower', 'Higher')][string]$Better = 'Higher')
    if ($Better -eq 'Higher') { if ($Value -ge $PassAt) { return 'Pass' } elseif ($Value -ge $WarnAt) { return 'Warn' } else { return 'Fail' } }
    if ($Value -le $PassAt) { return 'Pass' } elseif ($Value -le $WarnAt) { return 'Warn' } else { return 'Fail' }
}

function Add-ThresholdCheck {
    param([string]$Id, [string]$Domain, [string]$Title, [string]$Risk, [string]$Metric, [double]$PassAt, [double]$WarnAt, [string]$Better, [string]$Recommendation, [string[]]$Links, [string]$DataNeeded, [string[]]$Extra = @(), [string]$Unit = '')
    $op = if ($Better -eq 'Higher') { '>=' } else { '<=' }
    $rule = "Pass $op $PassAt$Unit; Warn $op $WarnAt$Unit; otherwise Fail"
    if (-not (Test-Metric $Metric)) {
        Add-Check -Id $Id -Domain $Domain -Title $Title -Risk $Risk -Status NotAssessed -Finding "NO DATA AVAILABLE. Not assessed because the required data was not collected or imported." -Recommendation $Recommendation -Links $Links -Metrics @($Metric) -DataNeeded $DataNeeded -Threshold $rule
        return
    }
    $m = $script:Ctx.Metrics[$Metric]
    $v = [double]$m.Value
    $status = Get-Band -Value $v -PassAt $PassAt -WarnAt $WarnAt -Better $Better
    $finding = "$($m.Label): $($m.Display)"
    if ($m.Denominator) { $finding += " ($($m.Denominator))" }
    if ($m.Note) { $finding += ". $($m.Note)" }
    foreach ($e in $Extra) { if (Test-Metric $e) { $x = $script:Ctx.Metrics[$e]; $finding += ". $($x.Label): $($x.Display)"; if ($x.Denominator) { $finding += " ($($x.Denominator))" } } }
    Add-Check -Id $Id -Domain $Domain -Title $Title -Risk $Risk -Status $status -Finding $finding -Recommendation $Recommendation -Links $Links -Metrics (@($Metric) + $Extra) -Threshold $rule -DataNeeded $DataNeeded
}

function Add-InfoCheck {
    param([string]$Id, [string]$Domain, [string]$Title, [string]$Risk, [string[]]$MetricKeys, [string]$Recommendation, [string[]]$Links, [string]$DataNeeded)
    $have = @($MetricKeys | Where-Object { Test-Metric $_ })
    if (-not $have.Count) { Add-Check -Id $Id -Domain $Domain -Title $Title -Risk $Risk -Status NotAssessed -Finding 'NO DATA AVAILABLE. Not assessed because the required data was not collected or imported.' -Recommendation $Recommendation -Links $Links -Metrics $MetricKeys -DataNeeded $DataNeeded; return }
    $parts = foreach ($k in $have) { $x = $script:Ctx.Metrics[$k]; $t = "$($x.Label): $($x.Display)"; if ($x.Denominator) { $t += " ($($x.Denominator))" }; $t }
    Add-Check -Id $Id -Domain $Domain -Title $Title -Risk $Risk -Status Info -Finding ($parts -join '. ') -Recommendation $Recommendation -Links $Links -Metrics $have -DataNeeded $DataNeeded
}

function Add-ManualCheck {
    param([string]$Id, [string]$Domain, [string]$Title, [string]$Risk, [string]$Where, [string]$Recommendation, [string[]]$Links)
    Add-Check -Id $Id -Domain $Domain -Title $Title -Risk $Risk -Status Manual -Finding "No API or export covers this setting. Verify in: $Where. Capture a screenshot for the evidence pack." -Recommendation $Recommendation -Links $Links -DataNeeded $Where
}

function Invoke-Checks {
    $L = $script:Learn
    # ---------------- Licensing and Deployment ----------------
    if (Test-Metric 'lic.copilot.assignedPct') {
        Add-ThresholdCheck 'LIC-01' 'LIC' 'Copilot license pool is in use' 'Medium' 'lic.copilot.assignedPct' 90 75 'Higher' 'Assign unused licenses to qualified candidates or reduce the order at renewal.' @($L.Licensing) '' @('lic.copilot.available') '%'
    }
    else { Add-InfoCheck 'LIC-01' 'LIC' 'Copilot license pool is in use' 'Medium' @('lic.ready.licensed', 'lic.users.copilot') 'Collect subscribedSkus (Graph) to compare purchased and assigned licenses.' @($L.Licensing) 'Graph_SubscribedSkus' }
    Add-ThresholdCheck 'LIC-02' 'LIC' 'Licensed users are not idle' 'Medium' 'lic.idlePct' 2 10 'Lower' 'Review idle licensed users monthly; reclaim or re-enable with targeted onboarding.' @($L.UsageReport, $L.ReadinessReport) 'Copilot usage (180 days) and readiness exports' @('lic.idle') '%'
    Add-InfoCheck 'LIC-03' 'LIC' 'Expansion demand is quantified' 'Low' @('lic.qualifiedPool', 'lic.ready.candidates', 'chat.activeUnlicensed') 'Size the next license wave from qualified candidates rather than headcount.' @($L.ReadinessReport, $L.ChatReport) 'Copilot Chat and readiness exports'
    Add-InfoCheck 'LIC-04' 'LIC' 'Directory and report license counts reconcile' 'Low' @('lic.reconcile.copilot', 'lic.users.copilot', 'lic.ready.licensed') 'Report both values with their capture dates; investigate deltas larger than recent assignment changes.' @($L.ReadinessReport) 'Entra users export and readiness export'

    # ---------------- Usage and Adoption ----------------
    Add-ThresholdCheck 'USE-01' 'USE' 'Licensed users are active within 30 days' 'High' 'use.active30Pct' 80 60 'Higher' 'Target onboarding and role-based scenarios at inactive licensed users.' @($L.UsageReport, $L.Adoption) 'Copilot usage export or Graph Reports.Read.All' @('use.noActivity') '%'
    Add-ThresholdCheck 'USE-02' 'USE' 'Weekly active rate of enabled users (Viva Insights)' 'Medium' 'viva.activeRate' 70 50 'Higher' 'Use the Copilot Dashboard to track weekly active and habitual use by organization.' @($L.VivaDashboard) 'Viva Insights Copilot Dashboard export' @('viva.habitual') '%'
    Add-ThresholdCheck 'USE-03' 'USE' 'Usage is broad, not concentrated in a few users' 'Low' 'use.prompts.top10Share' 50 70 'Lower' 'Use champions from high-usage groups to extend scenarios to low-usage groups.' @($L.Adoption) 'Copilot usage export' @('use.prompts', 'use.prompts.median') '%'
    if ((Test-Metric 'use.app.wordcopilot') -and (Test-Metric 'use.active30') -and (Get-Metric 'use.active30') -gt 0) {
        $w = Get-Metric 'use.app.wordcopilot'; $a = Get-Metric 'use.active30'; $p = Get-Pct $w $a
        Set-Metric 'use.wordDepthPct' 'USE' 'Active users who used Copilot in Word in 30 days' $p -Kind pct -Denominator ("{0:N0} of {1:N0} users active in 30 days" -f $w, $a) -Source $script:Ctx.Metrics['use.app.wordcopilot'].Source
        Add-ThresholdCheck 'USE-04' 'USE' 'Copilot is used for document authoring' 'Low' 'use.wordDepthPct' 40 20 'Higher' 'Run Word, PowerPoint, and Excel scenario training for roles that create documents.' @($L.UsageReport, $L.Adoption) 'Copilot usage export' @('use.app.powerpointcopilot', 'use.app.excelcopilot') '%'
    }
    else { Add-ThresholdCheck 'USE-04' 'USE' 'Copilot is used for document authoring' 'Low' 'use.wordDepthPct' 40 20 'Higher' 'Run Word, PowerPoint, and Excel scenario training for roles that create documents.' @($L.UsageReport) 'Copilot usage export' }
    Add-InfoCheck 'USE-05' 'USE' 'Unlicensed Copilot Chat and Copilot Search use' 'Low' @('chat.active', 'chat.prompts', 'chat.active10', 'viva.unlicensedChat', 'use.search.users') 'Use Copilot Chat activity to identify engaged users for the next wave and promote Copilot Search.' @($L.ChatReport, $L.SearchReport) 'Copilot Chat usage export'

    # ---------------- Copilot Control System ----------------
    if (Test-Metric 'ccs.aiAdmins') {
        $n = Get-Metric 'ccs.aiAdmins'
        Add-Check 'CCS-01' 'CCS' 'AI Administrator role is assigned' 'Medium' $(if ($n -ge 1) { 'Pass' } else { 'Warn' }) ("Active AI Administrator assignments: {0}. Eligible (PIM) assignments are not counted; confirm in Entra." -f $n) 'Assign the AI Administrator role (through PIM) to the people who own Copilot and agent settings, instead of Global Administrator.' @($L.AiAdmin, $L.CopilotPage) @('ccs.aiAdmins') 'Pass >= 1 active assignment'
    }
    else { Add-Check 'CCS-01' 'CCS' 'AI Administrator role is assigned' 'Medium' NotAssessed 'NO DATA AVAILABLE. Directory role assignments were not collected.' 'Assign the AI Administrator role through PIM.' @($L.AiAdmin) @('ccs.aiAdmins') '' 'Graph role assignments (RoleManagement.Read.Directory)' }
    Add-ManualCheck 'CCS-02' 'CCS' 'Copilot settings and Optimize recommendations reviewed' 'Medium' 'Microsoft 365 admin center > Copilot > Settings and Overview (Optimize)' 'Review each Copilot setting with an owner and a recorded decision.' @($L.CopilotPage)
    Add-ManualCheck 'CCS-03' 'CCS' 'Web search, AI providers, and Copilot app availability decided' 'Medium' 'Microsoft 365 admin center > Copilot > Settings (web search, AI providers operating as subprocessors, pinning)' 'Record a decision for web grounding and additional AI model providers before broad rollout.' @($L.CopilotPage)
    Add-ManualCheck 'CCS-04' 'CCS' 'Copilot release and update cadence managed' 'Low' 'Microsoft 365 admin center > Copilot > Settings and Microsoft 365 Apps admin center' 'Use a validation ring for Copilot feature releases.' @($L.CopilotPage, $L.Channels)

    # ---------------- Identity ----------------
    if ((Test-Metric 'id.ca.mfaAll') -or (Test-Metric 'id.securityDefaults')) {
        $mfa = Get-Metric 'id.ca.mfaAll'; $sd = "$(Get-Metric 'id.securityDefaults')"
        $st = if ($mfa -ge 1 -or $sd -eq 'True') { 'Pass' } else { 'Fail' }
        Add-Check 'ID-01' 'ID' 'Multifactor authentication is required for all users' 'Critical' $st ("Enforced Conditional Access policies requiring MFA or authentication strength for all users: {0}. Security defaults enabled: {1}." -f $(if ($null -ne $mfa) { $mfa } else { 'not collected' }), $(if ($sd) { $sd } else { 'not collected' })) 'Require MFA (authentication strength) for all users with Conditional Access, excluding only break-glass accounts.' @($L.CaMfa, $L.SecDefaults) @('id.ca.mfaAll', 'id.securityDefaults') 'Pass when at least one enforced all-users MFA policy exists or security defaults are on'
    }
    else { Add-Check 'ID-01' 'ID' 'Multifactor authentication is required for all users' 'Critical' NotAssessed 'NO DATA AVAILABLE. Conditional Access was not collected.' 'Require MFA for all users.' @($L.CaMfa) @() '' 'Graph Conditional Access policies (Policy.Read.All)' }
    if ((Test-Metric 'id.ca.legacyBlock') -or (Test-Metric 'id.securityDefaults')) {
        $lb = Get-Metric 'id.ca.legacyBlock'; $sd = "$(Get-Metric 'id.securityDefaults')"
        $st = if ($lb -ge 1 -or $sd -eq 'True') { 'Pass' } else { 'Fail' }
        Add-Check 'ID-02' 'ID' 'Legacy authentication is blocked' 'High' $st ("Enforced policies blocking legacy authentication: {0}. Security defaults enabled: {1}." -f $(if ($null -ne $lb) { $lb } else { 'not collected' }), $(if ($sd) { $sd } else { 'not collected' })) 'Block legacy authentication with Conditional Access.' @($L.CaLegacy) @('id.ca.legacyBlock', 'id.securityDefaults') 'Pass when blocked by policy or security defaults'
    }
    else { Add-Check 'ID-02' 'ID' 'Legacy authentication is blocked' 'High' NotAssessed 'NO DATA AVAILABLE. Conditional Access was not collected.' 'Block legacy authentication.' @($L.CaLegacy) @() '' 'Graph Conditional Access policies' }
    Add-ThresholdCheck 'ID-03' 'ID' 'Global Administrator assignments are limited' 'High' 'id.roles.globalAdmins' 4 8 'Lower' 'Keep fewer than five Global Administrators (Microsoft Learn) and use least-privileged roles such as AI Administrator for Copilot.' @($L.RoleBest) 'Graph role assignments'
    Add-InfoCheck 'ID-04' 'ID' 'Guest accounts in scope of Copilot data access' 'Low' @('lic.users.guests') 'Review guest access and guest expiration; guests can reach shared content that Copilot grounds on for them.' @($L.Blueprint) 'Entra users export or Graph users'
    Add-ThresholdCheck 'ID-05' 'ID' 'Microsoft Secure Score' 'Medium' 'id.secureScore' 70 50 'Higher' 'Work the Secure Score identity and data recommendations before broad Copilot expansion.' @($L.SecureScore) 'Graph secureScores (SecurityEvents.Read.All)' @() '%'

    # ---------------- Endpoint ----------------
    Add-ThresholdCheck 'EP-01' 'EP' 'Licensed users run an eligible Microsoft 365 Apps channel' 'Medium' 'ep.channel.licensedPct' 95 80 'Higher' 'Move licensed users to Current Channel or Monthly Enterprise Channel.' @($L.Channels, $L.ReadinessReport) 'Copilot readiness export' @() '%'
    Add-ThresholdCheck 'EP-02' 'EP' 'Expansion population runs an eligible channel' 'Low' 'ep.channel.unlicensedPct' 80 50 'Higher' 'Move the next license wave to an eligible channel before licenses are assigned.' @($L.Channels, $L.ReadinessReport) 'Copilot readiness export' @() '%'

    # ---------------- Data access and oversharing ----------------
    Add-ThresholdCheck 'DA-01' 'DA' 'Sites with uniquely permissioned items' 'High' 'da.sp.brokenInheritancePct' 10 30 'Lower' 'Run site access reviews on the highest-count sites and reset inheritance where unique permissions are not needed.' @($L.Dag, $L.SiteReview, $L.Blueprint) 'SharePoint DAG site permissions report (SharePoint Advanced Management)' @('da.sp.brokenInheritance') '%'
    Add-ThresholdCheck 'DA-02' 'DA' 'Private sites reachable by 1,000 or more users' 'High' 'da.sp.wide1000Private' 0 10 'Lower' 'Review membership of broad private sites; apply Restricted Access Control or Restricted Content Discovery to sites that must stay broad.' @($L.Dag, $L.Rac, $L.Blueprint) 'SharePoint DAG site permissions report' @('da.sp.wide1000')
    Add-ThresholdCheck 'DA-03' 'DA' 'Everyone except external users grants with Edit or higher' 'High' 'da.eeeu.editPlus' 0 50 'Lower' 'Remove or downgrade EEEU grants; replace with named groups.' @($L.Dag, $L.Blueprint) 'DAG content shared with Everyone except external users report' @('da.eeeu.grants')
    Add-ThresholdCheck 'DA-04' 'DA' 'Anyone links on SharePoint sites' 'Medium' 'da.sp.anyoneLinks' 0 1000 'Lower' 'Expire or remove Anyone links and set link expiration.' @($L.Dag) 'SharePoint DAG site permissions report'
    Add-ThresholdCheck 'DA-05' 'DA' 'OneDrive accounts reachable by 100 or more users' 'Medium' 'da.od.wide100Pct' 1 5 'Lower' 'Review OneDrive sharing for accounts with wide reach; run the DAG OneDrive report regularly.' @($L.Dag) 'DAG OneDrive permissions report' @('da.od.wide100', 'da.od.brokenInheritance') '%'
    Add-ThresholdCheck 'DA-06' 'DA' 'Item-level Everyone grants' 'Medium' 'da.everyone.grants' 0 10 'Lower' 'Remove Everyone grants from items.' @($L.Dag) 'DAG content shared with Everyone report'
    if (Test-Metric 'da.tenant.SharingCapability') {
        $v = "$(Get-Metric 'da.tenant.SharingCapability')"
        $st = switch -Regex ($v) { '^(Disabled|ExistingExternalUserSharingOnly)$' { 'Pass' } '^(ExternalUserSharingOnly)$' { 'Warn' } '^(ExternalUserAndGuestSharing)$' { 'Fail' } default { 'Info' } }
        Add-Check 'DA-07' 'DA' 'Tenant external sharing level' 'Medium' $st "SharingCapability: $v." 'Limit tenant-level sharing to the least permissive level the business needs; use site-level exceptions.' @($L.Blueprint) @('da.tenant.SharingCapability') 'Pass: Disabled or existing guests only; Warn: new and existing guests; Fail: Anyone'
    }
    else { Add-Check 'DA-07' 'DA' 'Tenant external sharing level' 'Medium' NotAssessed 'NO DATA AVAILABLE. SharePoint tenant settings were not collected.' 'Limit tenant-level sharing.' @($L.Blueprint) @() '' 'Get-SPOTenant or Graph admin/sharepoint/settings' }
    if (Test-Metric 'da.tenant.DefaultSharingLinkType') {
        $v = "$(Get-Metric 'da.tenant.DefaultSharingLinkType')"
        $st = switch -Regex ($v) { '^(Direct)$' { 'Pass' } '^(Internal)$' { 'Warn' } '^(AnonymousAccess)$' { 'Fail' } default { 'Info' } }
        Add-Check 'DA-08' 'DA' 'Default sharing link is Specific people' 'Medium' $st "DefaultSharingLinkType: $v." 'Set the default link type to Specific people to reduce accidental broad sharing.' @($L.Blueprint) @('da.tenant.DefaultSharingLinkType') 'Pass: Direct; Warn: Internal; Fail: AnonymousAccess'
    }
    else { Add-Check 'DA-08' 'DA' 'Default sharing link is Specific people' 'Medium' NotAssessed 'NO DATA AVAILABLE. SharePoint tenant settings were not collected.' 'Set the default link type to Specific people.' @($L.Blueprint) @() '' 'Get-SPOTenant' }
    Add-ManualCheck 'DA-09' 'DA' 'Restricted Access Control, Restricted Content Discovery, and SAM policies in use' 'Medium' 'SharePoint admin center > Policies > Access control and Site lifecycle; Reports > Data access governance' 'Apply Restricted Access Control or Restricted Content Discovery to sensitive sites during remediation; use Restricted SharePoint Search only as a temporary measure.' @($L.Rac, $L.Rss)
    Add-ThresholdCheck 'DA-10' 'DA' 'Anyone links in OneDrive' 'Low' 'da.od.anyoneLinks' 0 500 'Lower' 'Remove legacy Anyone links in OneDrive.' @($L.Dag) 'DAG OneDrive permissions report'

    # ---------------- Information protection ----------------
    Add-ThresholdCheck 'IP-01' 'IP' 'Sensitivity labels are defined' 'High' 'ip.labels' 1 1 'Higher' 'Publish a sensitivity label taxonomy; Copilot honors label encryption and usage rights.' @($L.Labels) 'Security & Compliance PowerShell (Get-Label)' @('ip.labelPolicies')
    Add-ThresholdCheck 'IP-02' 'IP' 'Sites carry a sensitivity label' 'Medium' 'ip.sitesLabeled' 90 50 'Higher' 'Label sites and set default library labels so new files inherit protection.' @($L.LibraryLabel) 'SharePoint DAG site permissions report' @() '%'
    if ((Test-Metric 'ip.dlp.total')) {
        $t = Get-Metric 'ip.dlp.total'; $e = Get-Metric 'ip.dlp.enforced'
        $st = if ($e -ge 1) { 'Pass' } elseif ($t -ge 1) { 'Warn' } else { 'Fail' }
        Add-Check 'IP-03' 'IP' 'DLP policies are enforced' 'High' $st ("DLP policies: {0}; in enforcement mode: {1}." -f $t, $e) 'Move tested DLP policies from simulation to enforcement in stages.' @($L.CopilotDlp) @('ip.dlp.total', 'ip.dlp.enforced') 'Pass: at least one enforced; Warn: policies exist but none enforced; Fail: none'
        $c = Get-Metric 'ip.dlp.copilot'; $ce = Get-Metric 'ip.dlp.copilotEnforced'
        $st = if ($ce -ge 1) { 'Pass' } elseif ($c -ge 1) { 'Warn' } else { 'Fail' }
        Add-Check 'IP-04' 'IP' 'DLP protects the Microsoft 365 Copilot location' 'High' $st ("Policies referencing Copilot: {0}; enforced: {1}. Detected by text match; confirm the Microsoft 365 Copilot and Copilot Chat location in Purview." -f $c, $ce) 'Create a DLP policy for the Microsoft 365 Copilot location that blocks processing of labeled content and sensitive prompts.' @($L.CopilotDlp) @('ip.dlp.copilot', 'ip.dlp.copilotEnforced') 'Pass: enforced Copilot policy; Warn: simulation only; Fail: none'
    }
    else {
        Add-Check 'IP-03' 'IP' 'DLP policies are enforced' 'High' NotAssessed 'NO DATA AVAILABLE. DLP policies were not collected.' 'Enforce DLP.' @($L.CopilotDlp) @() '' 'Get-DlpCompliancePolicy'
        Add-Check 'IP-04' 'IP' 'DLP protects the Microsoft 365 Copilot location' 'High' NotAssessed 'NO DATA AVAILABLE. DLP policies were not collected.' 'Create a Copilot DLP policy.' @($L.CopilotDlp) @() '' 'Get-DlpCompliancePolicy'
    }
    if (Test-Metric 'ip.autolabel.total') {
        $t = Get-Metric 'ip.autolabel.total'; $e = Get-Metric 'ip.autolabel.enforced'
        Add-Check 'IP-05' 'IP' 'Auto-labeling is enforced' 'Medium' $(if ($e -ge 1) { 'Pass' } elseif ($t -ge 1) { 'Warn' } else { 'Fail' }) ("Auto-labeling policies: {0}; enforced: {1}." -f $t, $e) 'Turn on service-side auto-labeling for high-risk sensitive information types after simulation review.' @($L.AutoLabel) @('ip.autolabel.total', 'ip.autolabel.enforced') 'Pass: at least one enforced; Warn: simulation only; Fail: none'
    }
    else { Add-Check 'IP-05' 'IP' 'Auto-labeling is enforced' 'Medium' NotAssessed 'NO DATA AVAILABLE. Auto-labeling policies were not collected.' 'Turn on auto-labeling.' @($L.AutoLabel) @() '' 'Get-AutoSensitivityLabelPolicy' }
    Add-InfoCheck 'IP-06' 'IP' 'Sensitive content exposure (DSPM data risk assessment)' 'Medium' @('ip.dra.sensitiveItems', 'ip.dra.sources') 'Prioritize labeling and access review on data sources with the most sensitive items.' @($L.Dspm) 'DSPM data risk assessment export'

    # ---------------- Lifecycle ----------------
    Add-ThresholdCheck 'LC-01' 'LC' 'Inactive sites that still hold content' 'Medium' 'lc.inactive180Pct' 10 25 'Lower' 'Apply an inactive site policy and archive or delete stale sites so Copilot does not ground on outdated content.' @($L.Lifecycle) 'Active sites export or Get-SPOSite' @('lc.inactive180') '%'
    if (Test-Metric 'lc.retentionPolicies') {
        $n = Get-Metric 'lc.retentionPolicies'
        Add-Check 'LC-02' 'LC' 'Retention covers Copilot interactions and content' 'Medium' $(if ($n -ge 1) { 'Pass' } else { 'Warn' }) "Retention policies: $n. Confirm a policy includes Microsoft Copilot experiences." 'Create a retention policy for Copilot interactions aligned to records requirements.' @($L.Retention) @('lc.retentionPolicies', 'lc.retentionLabels') 'Pass: at least one policy'
    }
    else { Add-Check 'LC-02' 'LC' 'Retention covers Copilot interactions and content' 'Medium' NotAssessed 'NO DATA AVAILABLE. Retention policies were not collected.' 'Create a Copilot retention policy.' @($L.Retention) @() '' 'Get-RetentionCompliancePolicy' }
    Add-ThresholdCheck 'LC-03' 'LC' 'Storage on unlabeled sites' 'Low' 'lc.unlabeledStoragePct' 20 50 'Lower' 'Label large unlabeled sites first; they hold the most content Copilot can reach.' @($L.LibraryLabel) 'Active sites export' @() '%'

    # ---------------- Audit and monitoring ----------------
    if (Test-Metric 'am.ual') {
        $v = "$(Get-Metric 'am.ual')"
        Add-Check 'AM-01' 'AM' 'Unified audit log is on' 'Critical' $(if ($v -eq 'True') { 'Pass' } else { 'Fail' }) "UnifiedAuditLogIngestionEnabled: $v." 'Turn on auditing; Copilot interaction records depend on it.' @($L.AuditOn, $L.AuditCopilot) @('am.ual') 'Pass: True'
    }
    else { Add-Check 'AM-01' 'AM' 'Unified audit log is on' 'Critical' NotAssessed 'NO DATA AVAILABLE. Audit configuration was not collected.' 'Turn on auditing.' @($L.AuditOn) @() '' 'Get-AdminAuditLogConfig (Exchange Online PowerShell)' }
    if (Test-Metric 'am.copilotAudit') {
        $n = Get-Metric 'am.copilotAudit'
        Add-Check 'AM-02' 'AM' 'Copilot interactions are recorded in the audit log' 'Medium' $(if ($n -gt 0) { 'Pass' } else { 'Warn' }) ("CopilotInteraction records in sample window: {0:N0}." -f $n) 'Confirm Copilot interactions appear in audit search and are retained for the required period.' @($L.AuditCopilot) @('am.copilotAudit') 'Pass: more than 0'
    }
    elseif (Test-Metric 'am.dspm.aiActivity') { Add-InfoCheck 'AM-02' 'AM' 'Copilot interactions are recorded in the audit log' 'Medium' @('am.dspm.aiActivity') 'Confirm audit retention for Copilot interactions.' @($L.AuditCopilot) 'Search-UnifiedAuditLog' }
    else { Add-Check 'AM-02' 'AM' 'Copilot interactions are recorded in the audit log' 'Medium' NotAssessed 'NO DATA AVAILABLE. Neither an audit sample nor a DSPM activity export was supplied.' 'Confirm Copilot audit records.' @($L.AuditCopilot) @() '' 'Search-UnifiedAuditLog or DSPM Activity explorer export' }
    Add-InfoCheck 'AM-03' 'AM' 'DSPM captures AI activity and sensitive interactions' 'Medium' @('am.dspm.aiActivity', 'am.dspm.sensitive') 'Turn on DSPM collection policies and review sensitive AI interactions weekly. Portal exports are capped; use scheduled exports for totals.' @($L.Dspm) 'DSPM Activity explorer export'
    Add-ManualCheck 'AM-04' 'AM' 'Insider Risk Management covers risky AI usage' 'Medium' 'Microsoft Purview > Insider risk management > Policies (Risky AI usage template)' 'Create a Risky AI usage policy once audit and DSPM are confirmed.' @($L.Irm)

    # ---------------- Agents ----------------
    Add-ThresholdCheck 'AG-01' 'AG' 'Organization-built agents have an owner' 'High' 'ag.registry.noOwnerPct' 5 20 'Lower' 'Assign an owner to every organization-built agent; block or retire agents without owners.' @($L.ManageAgents) 'Agents registry export (Microsoft 365 admin center > Agents)' @('ag.registry.noOwner', 'ag.registry') '%'
    Add-InfoCheck 'AG-02' 'AG' 'Agent adoption' 'Low' @('ag.registry', 'ag.usage.agents', 'ag.usage.users', 'ag.connectors', 'ag.registry.byPublisher') 'Track agent usage against the registry to retire unused agents.' @($L.AgentsReport, $L.ManageAgents) 'Agents usage and registry exports'
    if (Test-Metric 'am.obs.risky') {
        $r = Get-Metric 'am.obs.risky'
        Add-Check 'AG-03' 'AG' 'Agents flagged with risk in AI observability' 'Medium' $(if ($r -eq 0) { 'Pass' } else { 'Warn' }) ("{0}: {1} ({2})." -f $script:Ctx.Metrics['am.obs.risky'].Label, $script:Ctx.Metrics['am.obs.risky'].Display, $script:Ctx.Metrics['am.obs.risky'].Denominator) 'Review agents with a risk level and confirm their data sources and sharing.' @($L.Dspm) @('am.obs.risky', 'am.obs.agents') 'Pass: 0 agents with risk'
    }
    else { Add-Check 'AG-03' 'AG' 'Agents flagged with risk in AI observability' 'Medium' NotAssessed 'NO DATA AVAILABLE. AI observability export not supplied.' 'Review risky agents.' @($L.Dspm) @() '' 'Purview DSPM AI observability export' }
    Add-ManualCheck 'AG-04' 'AG' 'Agent sharing and approval policy is set' 'Medium' 'Microsoft 365 admin center > Agents > Settings (who can create, share, and use agents)' 'Restrict agent sharing to approved groups and route org-wide publishing through an approval process.' @($L.ManageAgents)

    # ---------------- Power Platform ----------------
    Add-ThresholdCheck 'PP-01' 'PP' 'Agents built outside the default environment' 'High' 'pp.agents.defaultPct' 20 50 'Lower' 'Route makers to governed environments with an environment strategy; use default environment routing.' @($L.EnvStrategy, $L.StudioGov) 'Power Platform admin center Inventory export or inventory API' @('pp.agents.default', 'pp.agents') '%'
    Add-ThresholdCheck 'PP-02' 'PP' 'Agents run in Managed Environments' 'Medium' 'pp.agents.unmanagedPct' 20 60 'Lower' 'Enable Managed Environments for environments that host agents, including the default environment.' @($L.ManagedEnv) 'Power Platform admin center Inventory export' @() '%'
    Add-ThresholdCheck 'PP-03' 'PP' 'Agents require authentication' 'High' 'pp.agents.noAuth' 0 5 'Lower' 'Require Microsoft Entra authentication for agents unless anonymous access is approved.' @($L.StudioAuth) 'Power Platform admin center Inventory export' @('pp.agents.creators')

    # ---------------- Dataverse ----------------
    Add-InfoCheck 'DV-01' 'DV' 'Dataverse use and capacity' 'Low' @('dv.agentsUsingDataverse', 'dv.environments', 'dv.databaseGB') 'Plan Dataverse capacity for agents, and review Dataverse search and data policies for knowledge sources.' @($L.Capacity) 'Inventory export or BAP environments API'

    # ---------------- Fabric ----------------
    if (Test-Metric 'fb.copilotOn') {
        $on = Get-Metric 'fb.copilotOn'
        $m = $script:Ctx.Metrics['fb.copilotOn']
        Add-Check 'FB-01' 'FB' 'Fabric Copilot and AI settings are deliberate and scoped' 'Medium' 'Info' ("{0}: {1} ({2})." -f $m.Label, $m.Display, $m.Denominator) 'Enable Copilot in Fabric for a defined security group first; record the cross-geo processing decision.' @($L.FabricCopilot) @('fb.copilotOn', 'fb.copilotSettings') 'Informational'
    }
    else { Add-Check 'FB-01' 'FB' 'Fabric Copilot and AI settings are deliberate and scoped' 'Medium' NotAssessed 'NO DATA AVAILABLE. Fabric tenant settings were not collected.' 'Review Copilot and agent tenant settings in the Fabric admin portal.' @($L.FabricCopilot) @() '' 'Fabric admin API (Fabric administrator) or admin portal screenshots' }

    # ---------------- Catalog ----------------
    Add-ThresholdCheck 'DC-01' 'DC' 'Agent and app requests are processed' 'Low' 'dc.pending' 0 10 'Lower' 'Assign an approver and a service level for agent and app requests.' @($L.ManageAgents) 'Graph Copilot admin catalog (CopilotPackages.Read.All)' @('dc.packages')

    # ---------------- AI governance ----------------
    if (Test-Metric 'gov.ai.appsProtected') {
        $p = Get-Metric 'gov.ai.appsProtected'
        Add-Check 'GOV-01' 'GOV' 'AI apps are covered by data protection policies' 'Medium' $(if ($p -ge 1) { 'Info' } else { 'Warn' }) ("{0}: {1} ({2})." -f $script:Ctx.Metrics['gov.ai.appsProtected'].Label, $script:Ctx.Metrics['gov.ai.appsProtected'].Display, $script:Ctx.Metrics['gov.ai.appsProtected'].Denominator) 'Extend DSPM data protection policies to the AI apps in use, starting with the highest prompt volume.' @($L.Dspm) @('gov.ai.appsProtected') 'Warn: no AI app has a policy'
    }
    else { Add-Check 'GOV-01' 'GOV' 'AI apps are covered by data protection policies' 'Medium' NotAssessed 'NO DATA AVAILABLE. DSPM Apps report not supplied.' 'Extend DSPM policies to AI apps.' @($L.Dspm) @() '' 'DSPM Apps and agents export' }
    Add-ManualCheck 'GOV-02' 'GOV' 'AI governance operating model is defined' 'Medium' 'Stakeholder interviews and discovery questionnaire (owners, AI council or CoE, acceptable use policy)' 'Name an executive sponsor, an AI governance group, and owners for Copilot, agents, and data.' @($L.Adoption)

    Write-Log "Checks evaluated: $($script:Ctx.Checks.Count)" 'Ok'
}

function Get-Scores {
    $domainRows = foreach ($k in $script:Domains.Keys) {
        $cs = @($script:Ctx.Checks | Where-Object { $_.Domain -eq $k })
        $scored = @($cs | Where-Object { $_.Status -in @('Pass', 'Warn', 'Fail') })
        $num = 0.0; $den = 0.0
        foreach ($c in $scored) { $w = $script:RiskWeight[$c.Risk]; $num += $w * $script:StatusPoints[$c.Status]; $den += $w }
        $score = if ($den -gt 0) { [math]::Round(100 * $num / $den) } else { $null }
        [pscustomobject][ordered]@{
            Domain = $k; Name = $script:Domains[$k].Name; Weight = $script:Domains[$k].Weight; Score = $score; Rating = (Get-Rating $score)
            Confidence = $(if (-not $scored.Count) { 'None' } elseif ($scored.Count / [math]::Max(1, $cs.Count) -ge 0.75) { 'High' } elseif ($scored.Count / [math]::Max(1, $cs.Count) -ge 0.4) { 'Medium' } else { 'Low' })
            Checks = $cs.Count; Scored = $scored.Count
            Pass = @($cs | Where-Object Status -eq 'Pass').Count; Warn = @($cs | Where-Object Status -eq 'Warn').Count; Fail = @($cs | Where-Object Status -eq 'Fail').Count
            Info = @($cs | Where-Object Status -eq 'Info').Count; Manual = @($cs | Where-Object Status -eq 'Manual').Count; NotAssessed = @($cs | Where-Object Status -eq 'NotAssessed').Count
        }
    }
    $num = 0.0; $den = 0.0
    foreach ($d in $domainRows) { if ($null -ne $d.Score) { $num += $d.Weight * $d.Score; $den += $d.Weight } }
    $overall = if ($den -gt 0) { [math]::Round($num / $den) } else { $null }
    $all = @($script:Ctx.Checks); $scoredAll = @($all | Where-Object { $_.Status -in @('Pass', 'Warn', 'Fail') })
    return [pscustomobject]@{
        Overall = $overall; Rating = (Get-Rating $overall); Domains = @($domainRows)
        WeightCovered = $den; WeightTotal = (($script:Domains.Values | ForEach-Object { $_.Weight }) | Measure-Object -Sum).Sum
        CoveragePct = (Get-Pct $scoredAll.Count $all.Count 0)
    }
}

function Get-Rating {
    param($Score)
    if ($null -eq $Score) { return 'Not assessed' }
    if ($Score -ge 85) { return 'Ready' }
    if ($Score -ge 70) { return 'Mostly Ready' }
    if ($Score -ge 40) { return 'Partially Ready' }
    return 'Not Ready'
}
