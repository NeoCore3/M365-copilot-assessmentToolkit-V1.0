# Checks

55 checks across 15 domains. Thresholds produce Pass, Warn, or Fail. Info checks report measured context and are not scored. Manual checks have no API or export. Not assessed means the data was not supplied; it is never scored as a failure.

Thresholds are SHI delivery conventions unless the recommendation cites a Microsoft Learn limit (for example, fewer than five Global Administrators). Change them in `src/Checks.ps1` and record any change in the engagement notes.

Risk weights: Critical 4, High 3, Medium 2, Low 1. Status points: Pass 1, Warn 0.5, Fail 0.

## Licensing and Deployment

| ID | Check | Risk | Rule | Data source | Microsoft Learn |
|---|---|---|---|---|---|
| LIC-01 | Copilot license pool is in use | Medium | Informational | Graph_SubscribedSkus | [1](https://learn.microsoft.com/en-us/microsoft-365/copilot/microsoft-365-copilot-licensing) |
| LIC-02 | Licensed users are not idle | Medium | Pass <= 2%; Warn <= 10%; otherwise Fail | Copilot usage (180 days) and readiness exports | [1](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-usage) [2](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-readiness) |
| LIC-03 | Expansion demand is quantified | Low | Informational | Copilot Chat and readiness exports | [1](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-readiness) [2](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-copilot-usage) |
| LIC-04 | Directory and report license counts reconcile | Low | Informational | Entra users export and readiness export | [1](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-readiness) |

## Usage and Adoption

| ID | Check | Risk | Rule | Data source | Microsoft Learn |
|---|---|---|---|---|---|
| USE-01 | Licensed users are active within 30 days | High | Pass >= 80%; Warn >= 60%; otherwise Fail | Copilot usage export or Graph Reports.Read.All | [1](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-usage) [2](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-enablement-resources) |
| USE-02 | Weekly active rate of enabled users (Viva Insights) | Medium | Pass >= 70%; Warn >= 50%; otherwise Fail | Viva Insights Copilot Dashboard export | [1](https://learn.microsoft.com/en-us/viva/insights/org-team-insights/copilot-dashboard) |
| USE-03 | Usage is broad, not concentrated in a few users | Low | Pass <= 50%; Warn <= 70%; otherwise Fail | Copilot usage export | [1](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-enablement-resources) |
| USE-04 | Copilot is used for document authoring | Low | Pass >= 40%; Warn >= 20%; otherwise Fail | Copilot usage export | [1](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-usage) [2](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-enablement-resources) |
| USE-05 | Unlicensed Copilot Chat and Copilot Search use | Low | Informational | Copilot Chat usage export | [1](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-copilot-usage) [2](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-search-usage) |

## Copilot Control System Configuration

| ID | Check | Risk | Rule | Data source | Microsoft Learn |
|---|---|---|---|---|---|
| CCS-01 | AI Administrator role is assigned | Medium | Pass >= 1 active AI Administrator assignment; otherwise Warn | Graph role assignments (RoleManagement.Read.Directory) | [1](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference#ai-administrator) |
| CCS-02 | Copilot settings and Optimize recommendations reviewed | Medium | Manual verification | Microsoft 365 admin center > Copilot > Settings and Overview (Optimize) | [1](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-page) |
| CCS-03 | Web search, AI providers, and Copilot app availability decided | Medium | Manual verification | Microsoft 365 admin center > Copilot > Settings (web search, AI providers operating as subprocessors, pinning) | [1](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-page) |
| CCS-04 | Copilot release and update cadence managed | Low | Manual verification | Microsoft 365 admin center > Copilot > Settings and Microsoft 365 Apps admin center | [1](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-page) [2](https://learn.microsoft.com/en-us/microsoft-365-apps/updates/overview-update-channels) |

## Identity and Access

| ID | Check | Risk | Rule | Data source | Microsoft Learn |
|---|---|---|---|---|---|
| ID-01 | Multifactor authentication is required for all users | Critical | Pass when an enforced all-users MFA or authentication strength policy exists, or security defaults are on | Graph Conditional Access policies (Policy.Read.All) | [1](https://learn.microsoft.com/en-us/entra/identity/conditional-access/policy-all-users-mfa-strength) |
| ID-02 | Legacy authentication is blocked | High | Pass when legacy authentication is blocked by an enforced policy or security defaults | Graph Conditional Access policies | [1](https://learn.microsoft.com/en-us/entra/identity/conditional-access/policy-block-legacy-authentication) |
| ID-03 | Global Administrator assignments are limited | High | Pass <= 4; Warn <= 8; otherwise Fail | Graph role assignments | [1](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/best-practices) |
| ID-04 | Guest accounts in scope of Copilot data access | Low | Informational | Entra users export or Graph users | [1](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-blueprint-oversharing) |
| ID-05 | Microsoft Secure Score | Medium | Pass >= 70%; Warn >= 50%; otherwise Fail | Graph secureScores (SecurityEvents.Read.All) | [1](https://learn.microsoft.com/en-us/defender-xdr/microsoft-secure-score) |

## Endpoint and App Readiness

| ID | Check | Risk | Rule | Data source | Microsoft Learn |
|---|---|---|---|---|---|
| EP-01 | Licensed users run an eligible Microsoft 365 Apps channel | Medium | Pass >= 95%; Warn >= 80%; otherwise Fail | Copilot readiness export | [1](https://learn.microsoft.com/en-us/microsoft-365-apps/updates/overview-update-channels) [2](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-readiness) |
| EP-02 | Expansion population runs an eligible channel | Low | Pass >= 80%; Warn >= 50%; otherwise Fail | Copilot readiness export | [1](https://learn.microsoft.com/en-us/microsoft-365-apps/updates/overview-update-channels) [2](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-readiness) |

## Data Access and Oversharing

| ID | Check | Risk | Rule | Data source | Microsoft Learn |
|---|---|---|---|---|---|
| DA-01 | Sites with uniquely permissioned items | High | Pass <= 10%; Warn <= 30%; otherwise Fail | SharePoint DAG site permissions report (SharePoint Advanced Management) | [1](https://learn.microsoft.com/en-us/sharepoint/data-access-governance-reports) [2](https://learn.microsoft.com/en-us/sharepoint/site-access-review) [3](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-blueprint-oversharing) |
| DA-02 | Private sites reachable by 1,000 or more users | High | Pass <= 0; Warn <= 10; otherwise Fail | SharePoint DAG site permissions report | [1](https://learn.microsoft.com/en-us/sharepoint/data-access-governance-reports) [2](https://learn.microsoft.com/en-us/sharepoint/restricted-access-control) [3](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-blueprint-oversharing) |
| DA-03 | Everyone except external users grants with Edit or higher | High | Pass <= 0; Warn <= 50; otherwise Fail | DAG content shared with Everyone except external users report | [1](https://learn.microsoft.com/en-us/sharepoint/data-access-governance-reports) [2](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-blueprint-oversharing) |
| DA-04 | Anyone links on SharePoint sites | Medium | Pass <= 0; Warn <= 1000; otherwise Fail | SharePoint DAG site permissions report | [1](https://learn.microsoft.com/en-us/sharepoint/data-access-governance-reports) |
| DA-05 | OneDrive accounts reachable by 100 or more users | Medium | Pass <= 1%; Warn <= 5%; otherwise Fail | DAG OneDrive permissions report | [1](https://learn.microsoft.com/en-us/sharepoint/data-access-governance-reports) |
| DA-06 | Item-level Everyone grants | Medium | Pass <= 0; Warn <= 10; otherwise Fail | DAG content shared with Everyone report | [1](https://learn.microsoft.com/en-us/sharepoint/data-access-governance-reports) |
| DA-07 | Tenant external sharing level | Medium | Pass: Disabled or existing guests only; Warn: new and existing guests; Fail: Anyone | Get-SPOTenant or Graph admin/sharepoint/settings | [1](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-blueprint-oversharing) |
| DA-08 | Default sharing link is Specific people | Medium | Pass: Direct (Specific people); Warn: Internal; Fail: AnonymousAccess | Get-SPOTenant | [1](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-blueprint-oversharing) |
| DA-09 | Restricted Access Control, Restricted Content Discovery, and SAM policies in use | Medium | Manual verification | SharePoint admin center > Policies > Access control and Site lifecycle; Reports > Data access governance | [1](https://learn.microsoft.com/en-us/sharepoint/restricted-access-control) [2](https://learn.microsoft.com/en-us/sharepoint/restricted-sharepoint-search) |
| DA-10 | Anyone links in OneDrive | Low | Pass <= 0; Warn <= 500; otherwise Fail | DAG OneDrive permissions report | [1](https://learn.microsoft.com/en-us/sharepoint/data-access-governance-reports) |

## Information Protection

| ID | Check | Risk | Rule | Data source | Microsoft Learn |
|---|---|---|---|---|---|
| IP-01 | Sensitivity labels are defined | High | Pass >= 1; Warn >= 1; otherwise Fail | Security & Compliance PowerShell (Get-Label) | [1](https://learn.microsoft.com/en-us/purview/sensitivity-labels) |
| IP-02 | Sites carry a sensitivity label | Medium | Pass >= 90%; Warn >= 50%; otherwise Fail | SharePoint DAG site permissions report | [1](https://learn.microsoft.com/en-us/purview/sensitivity-labels-sharepoint-default-label) |
| IP-03 | DLP policies are enforced | High | Pass: at least one enforced policy; Warn: policies exist but none enforced; Fail: none | Get-DlpCompliancePolicy | [1](https://learn.microsoft.com/en-us/purview/dlp-microsoft365-copilot-location-learn-about) |
| IP-04 | DLP protects the Microsoft 365 Copilot location | High | Pass: enforced Copilot policy; Warn: simulation only; Fail: none | Get-DlpCompliancePolicy | [1](https://learn.microsoft.com/en-us/purview/dlp-microsoft365-copilot-location-learn-about) |
| IP-05 | Auto-labeling is enforced | Medium | Pass: at least one enforced policy; Warn: simulation only; Fail: none | Get-AutoSensitivityLabelPolicy | [1](https://learn.microsoft.com/en-us/purview/apply-sensitivity-label-automatically) |
| IP-06 | Sensitive content exposure (DSPM data risk assessment) | Medium | Informational | DSPM data risk assessment export | [1](https://learn.microsoft.com/en-us/purview/dspm-for-ai) |

## Data Lifecycle and Content Quality

| ID | Check | Risk | Rule | Data source | Microsoft Learn |
|---|---|---|---|---|---|
| LC-01 | Inactive sites that still hold content | Medium | Pass <= 10%; Warn <= 25%; otherwise Fail | Active sites export or Get-SPOSite | [1](https://learn.microsoft.com/en-us/sharepoint/site-lifecycle-management) |
| LC-02 | Retention covers Copilot interactions and content | Medium | Pass: at least one retention policy; otherwise Warn | Get-RetentionCompliancePolicy | [1](https://learn.microsoft.com/en-us/purview/retention-policies-copilot) |
| LC-03 | Storage on unlabeled sites | Low | Pass <= 20%; Warn <= 50%; otherwise Fail | Active sites export | [1](https://learn.microsoft.com/en-us/purview/sensitivity-labels-sharepoint-default-label) |

## Audit, Monitoring, and AI Risk Detection

| ID | Check | Risk | Rule | Data source | Microsoft Learn |
|---|---|---|---|---|---|
| AM-01 | Unified audit log is on | Critical | Pass: UnifiedAuditLogIngestionEnabled = True; otherwise Fail | Get-AdminAuditLogConfig (Exchange Online PowerShell) | [1](https://learn.microsoft.com/en-us/purview/audit-log-enable-disable) |
| AM-02 | Copilot interactions are recorded in the audit log | Medium | Informational | Search-UnifiedAuditLog | [1](https://learn.microsoft.com/en-us/purview/audit-copilot) |
| AM-03 | DSPM captures AI activity and sensitive interactions | Medium | Informational | DSPM Activity explorer export | [1](https://learn.microsoft.com/en-us/purview/dspm-for-ai) |
| AM-04 | Insider Risk Management covers risky AI usage | Medium | Manual verification | Microsoft Purview > Insider risk management > Policies (Risky AI usage template) | [1](https://learn.microsoft.com/en-us/purview/insider-risk-management-policy-templates) |

## Agent and Extensibility Governance

| ID | Check | Risk | Rule | Data source | Microsoft Learn |
|---|---|---|---|---|---|
| AG-01 | Organization-built agents have an owner | High | Pass <= 5%; Warn <= 20%; otherwise Fail | Agents registry export (Microsoft 365 admin center > Agents) | [1](https://learn.microsoft.com/en-us/microsoft-365/admin/manage/manage-copilot-agents-integrated-apps) |
| AG-02 | Agent adoption | Low | Informational | Agents usage and registry exports | [1](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-agents) [2](https://learn.microsoft.com/en-us/microsoft-365/admin/manage/manage-copilot-agents-integrated-apps) |
| AG-03 | Agents flagged with risk in AI observability | Medium | Pass: 0 agents with risk |  | [1](https://learn.microsoft.com/en-us/purview/dspm-for-ai) |
| AG-04 | Agent sharing and approval policy is set | Medium | Manual verification | Microsoft 365 admin center > Agents > Settings (who can create, share, and use agents) | [1](https://learn.microsoft.com/en-us/microsoft-365/admin/manage/manage-copilot-agents-integrated-apps) |

## Power Platform and Copilot Studio Governance

| ID | Check | Risk | Rule | Data source | Microsoft Learn |
|---|---|---|---|---|---|
| PP-01 | Agents built outside the default environment | High | Pass <= 20%; Warn <= 50%; otherwise Fail | Power Platform admin center Inventory export or inventory API | [1](https://learn.microsoft.com/en-us/power-platform/guidance/adoption/environment-strategy) [2](https://learn.microsoft.com/en-us/microsoft-copilot-studio/security-and-governance) |
| PP-02 | Agents run in Managed Environments | Medium | Pass <= 20%; Warn <= 60%; otherwise Fail | Power Platform admin center Inventory export | [1](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-overview) |
| PP-03 | Agents require authentication | High | Pass <= 0; Warn <= 5; otherwise Fail | Power Platform admin center Inventory export | [1](https://learn.microsoft.com/en-us/microsoft-copilot-studio/configuration-end-user-authentication) |

## Dataverse Readiness

| ID | Check | Risk | Rule | Data source | Microsoft Learn |
|---|---|---|---|---|---|
| DV-01 | Dataverse use and capacity | Low | Informational | Inventory export or BAP environments API | [1](https://learn.microsoft.com/en-us/power-platform/admin/capacity-storage) |

## Microsoft Fabric and Copilot in Power BI

| ID | Check | Risk | Rule | Data source | Microsoft Learn |
|---|---|---|---|---|---|
| FB-01 | Fabric Copilot and AI settings are deliberate and scoped | Medium | Informational | Fabric admin API (Fabric administrator) or admin portal screenshots | [1](https://learn.microsoft.com/en-us/fabric/admin/service-admin-portal-copilot) |

## Agent Catalog and Store Management

| ID | Check | Risk | Rule | Data source | Microsoft Learn |
|---|---|---|---|---|---|
| DC-01 | Agent and app requests are processed | Low | Pass <= 0; Warn <= 10; otherwise Fail | Graph Copilot admin catalog (CopilotPackages.Read.All) | [1](https://learn.microsoft.com/en-us/microsoft-365/admin/manage/manage-copilot-agents-integrated-apps) |

## AI Governance and Operating Model

| ID | Check | Risk | Rule | Data source | Microsoft Learn |
|---|---|---|---|---|---|
| GOV-01 | AI apps are covered by data protection policies | Medium | Warn: no AI app has a policy |  | [1](https://learn.microsoft.com/en-us/purview/dspm-for-ai) |
| GOV-02 | AI governance operating model is defined | Medium | Manual verification | Stakeholder interviews and discovery questionnaire (owners, AI council or CoE, acceptable use policy) | [1](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-enablement-resources) |
