# Coverage: what is collected, imported, or manual

Status meanings in `collection-status.csv`: **Collected** (API or PowerShell), **Imported** (portal export recognized), **Empty** (call succeeded, no rows), **Failed** (error with guidance in `diagnostics.csv`), **Unsupported** (not available in the selected cloud), **NotRequested** (skipped by parameters).

## Collected (read-only API or PowerShell)

| Dataset | Source | Domain | Microsoft Learn |
|---|---|---|---|
| Graph_Organization, Graph_SubscribedSkus, Graph_Users | Graph v1.0 `/organization`, `/subscribedSkus`, `/users` | Licensing | [Licensing service plan reference](https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference) |
| Graph_ReportSettings | `/admin/reportSettings` | Licensing | |
| Graph_CopilotUsage, Graph_CopilotUserCountTrend, Graph_CopilotUserCountSummary | `/copilot/reports/getMicrosoft365Copilot*` (Commercial and GCC) | Usage | [getMicrosoft365CopilotUsageUserDetail](https://learn.microsoft.com/en-us/graph/api/reportroot-getmicrosoft365copilotusageuserdetail) |
| Graph_ActiveUserDetail | `/reports/getOffice365ActiveUserDetail(period='D30')` | Licensing | |
| Graph_ConditionalAccess, Graph_SecurityDefaults | `/identity/conditionalAccess/policies`, `/policies/identitySecurityDefaultsEnforcementPolicy` | Identity | [Require MFA for all users](https://learn.microsoft.com/en-us/entra/identity/conditional-access/policy-all-users-mfa-strength) |
| Graph_RoleDefinitions, Graph_RoleAssignments | `/roleManagement/directory/*` (active assignments) | Identity, Copilot Control System | [AI Administrator](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference#ai-administrator) |
| Graph_SharePointSettings | `/admin/sharepoint/settings` | Data access | |
| Graph_CopilotPackages | `/copilot/admin/catalog/packages` | Agent catalog | [List packages](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/admin-settings/package/copilotpackages-list) |
| Graph_SecureScore | `/security/secureScores?$top=1` | Identity | [Secure Score](https://learn.microsoft.com/en-us/defender-xdr/microsoft-secure-score) |
| SPO_Tenant, SPO_Sites, SPO_OneDrive | `Get-SPOTenant`, `Get-SPOSite -Limit All` | Data access, Lifecycle | |
| DAG reports (imported after `-DagMode Export`) | `Start-`, `Get-`, `Export-SPODataAccessGovernanceInsight` | Data access | [DAG reports](https://learn.microsoft.com/en-us/sharepoint/data-access-governance-reports), [Export cmdlet](https://learn.microsoft.com/en-us/powershell/module/sharepoint-online/export-spodataaccessgovernanceinsight) |
| PV_SensitivityLabels, PV_LabelPolicies, PV_AutoLabelPolicies, PV_DlpPolicies, PV_DlpRules, PV_RetentionPolicies, PV_RetentionLabels | Security & Compliance PowerShell `Get-*` | Information protection, Lifecycle | [DLP for Copilot](https://learn.microsoft.com/en-us/purview/dlp-microsoft365-copilot-location-learn-about) |
| EXO_AuditConfig | `Get-AdminAuditLogConfig` | Audit | [Turn auditing on or off](https://learn.microsoft.com/en-us/purview/audit-log-enable-disable) |
| EXO_CopilotAuditSample | `Search-UnifiedAuditLog -RecordType CopilotInteraction` (capped at 5,000, identities not exported) | Audit | [Audit Copilot](https://learn.microsoft.com/en-us/purview/audit-copilot) |
| PP_Environments | BAP admin environments API (Commercial) | Power Platform, Dataverse | [Capacity](https://learn.microsoft.com/en-us/power-platform/admin/capacity-storage) |
| PP_Inventory | Power Platform inventory API (Commercial, delegated) | Power Platform | [Inventory API](https://learn.microsoft.com/en-us/power-platform/admin/inventory-api) |
| FAB_TenantSettings | Fabric `GET /v1/admin/tenantsettings` (Commercial) | Fabric | [List tenant settings](https://learn.microsoft.com/en-us/rest/api/fabric/admin/tenants/list-tenant-settings) |

## Imported (no API exposes these; export from the portal)

| Dataset | Report | Why import |
|---|---|---|
| IMP_CopilotReadiness | Copilot readiness report | No Graph API for the readiness report. [Learn](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-readiness) |
| IMP_CopilotChat | Copilot Chat usage (includes unlicensed users) | No Graph API for Copilot Chat usage. [Learn](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-copilot-usage) |
| IMP_CopilotUsage | Copilot usage report (portal version includes prompt counts) | Also replaces the API in GCC High. [Learn](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-usage) |
| IMP_CopilotSearch | Copilot Search usage | No API. The export contains unquoted commas; the importer repairs it. [Learn](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-search-usage) |
| IMP_AgentUsage* | Agents usage report (Agents, Users, Users and agents tabs) | No API. [Learn](https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/microsoft-365-copilot-agents) |
| IMP_AgentRegistry | Microsoft 365 admin center > Agents > All agents export | Registry fields (owner, publisher type, platform) are not in the catalog API. [Learn](https://learn.microsoft.com/en-us/microsoft-365/admin/manage/manage-copilot-agents-integrated-apps) |
| IMP_ConnectorsUsage, IMP_ConnectorsUsers | Connectors usage | No API. |
| IMP_VivaCopilot | Viva Insights Copilot Dashboard person-week export | No public API. [Learn](https://learn.microsoft.com/en-us/viva/insights/org-team-insights/copilot-dashboard) |
| IMP_CopilotStudioInventory, IMP_AgentFlows | Power Platform admin center > Manage > Inventory | Used in every cloud; the API is Commercial-only in v1.0. |
| IMP_DagSharePoint, IMP_DagOneDrive, IMP_DagEEEUItems, IMP_DagEveryoneItems | SharePoint data access governance downloads | Same reports the cmdlets export; import when the cmdlets are not used. |
| IMP_ActiveSites | SharePoint admin center > Active sites export | Includes activity and storage per site. |
| IMP_DspmAiActivity, IMP_DspmAllActivity | Purview Activity explorer exports | No API for the export; capped at 10,000 rows by the portal and labeled as a sample. [DSPM for AI](https://learn.microsoft.com/en-us/purview/dspm-for-ai) |
| IMP_DspmApps, IMP_DspmAgents, IMP_DspmDataRisk | DSPM Apps and agents, data risk assessment | No API. |
| IMP_AIObservability, IMP_AIObservabilityApps | DSPM AI observability export | No API. |
| IMP_EntraUsers | Entra users download (alternative to Graph_Users) | For offline runs. |

When both a collected and an imported dataset exist for the same measure, the analysis uses the one listed first in the code (imported portal exports for usage, because they include prompt counts) and reports the other where it adds a reconciliation.

## Manual (no API and no export)

| Check | Where to verify |
|---|---|
| CCS-02, CCS-03, CCS-04 | Microsoft 365 admin center > Copilot > Settings and Optimize |
| DA-09 | SharePoint admin center > Policies (Restricted Access Control, site lifecycle, SAM policies) |
| AM-04 | Purview > Insider risk management > Policies |
| AG-04 | Microsoft 365 admin center > Agents > Settings |
| GOV-02 | Stakeholder interviews and the discovery questionnaire |

Capture screenshots for these in the evidence pack.
