# Permissions, roles, and Microsoft Graph access

The toolkit only reads. It signs in as a person (delegated access), sends `GET` requests and report calls, and runs `Get-*` cmdlets. It creates no app registration, secret, or certificate, and stores no tokens. The only non-read action is `-DagMode Start`, which asks SharePoint Advanced Management to generate data access governance reports. That action changes no permissions or content, and it is off by default.

Everything below was checked against Microsoft Learn (links in each table). Where Learn does not state a requirement, this page says so.

## 1. Recommended assessment account

Ask the client to create (or nominate) a named account for the assessment. Give it these roles for the duration of the engagement, ideally as PIM-eligible assignments that are activated only for the run.

| Role | Type | Why it is needed | Privilege |
|---|---|---|---|
| Global Reader | Microsoft Entra | Directory, licenses, Conditional Access, roles, SharePoint settings through Graph, and Purview read access (through the Purview Global Reader role group) | Read-only |
| Reports Reader | Microsoft Entra | **Required for the per-user Copilot usage report.** Global Reader is not on the role list for that API. | Read-only |
| Security Reader | Microsoft Entra | Microsoft Secure Score through Graph. The Graph security API asks for Security Reader or Security Administrator. | Read-only |
| SharePoint Administrator | Microsoft Entra | SharePoint Online PowerShell (`Connect-SPOService`, `Get-SPOTenant`, `Get-SPOSite`, data access governance cmdlets). Learn does not list a read-only role for this module. | **Can change settings.** Use PIM and activate only for the run. |
| View-Only Audit Logs | Exchange Online role (assign in the Exchange admin center, or through a role group) | `Search-UnifiedAuditLog` for the Copilot interaction sample | Read-only |
| Power Platform Administrator | Microsoft Entra | Power Platform environments API | **Can change settings.** Use PIM. Optional; the inventory API alone works with Global Reader. |
| Fabric Administrator | Microsoft Entra | Fabric tenant settings API | **Can change settings.** Use PIM. Optional. |

A minimum read-only run uses Global Reader, Reports Reader, Security Reader, and View-Only Audit Logs. Skip the collectors that need administrator roles with `-Collect Graph, Purview, Exchange`, and import the SharePoint, Power Platform, and Fabric data from portal exports instead (see [EVIDENCE.md](EVIDENCE.md)).

Do not use a Global Administrator account for the assessment.

## 2. Microsoft Graph

### Delegated scopes requested by `Connect-MgGraph`

| Scope | Used for | Admin consent |
|---|---|---|
| Organization.Read.All | `/organization`, `/subscribedSkus` | Yes |
| User.Read.All | `/users` with `assignedLicenses` | Yes |
| ReportSettings.Read.All | `/admin/reportSettings` (whether report names are concealed) | Yes |
| Reports.Read.All | Copilot usage reports, `getOffice365ActiveUserDetail` | Yes |
| Policy.Read.All | Conditional Access policies, security defaults | Yes |
| RoleManagement.Read.Directory | Directory role definitions and assignments | Yes |
| SharePointTenantSettings.Read.All | `/admin/sharepoint/settings` | Yes |
| CopilotPackages.Read.All | `/copilot/admin/catalog/packages` | Yes |
| SecurityEvents.Read.All | `/security/secureScores` | Yes |

### Calls, roles, and cloud availability

| Dataset | Endpoint | Least scope (Learn) | Role the signed-in user needs (Learn) | Clouds |
|---|---|---|---|---|
| Graph_Organization | `GET /v1.0/organization` | Organization.Read.All for all properties | A supported Entra role (Global Reader works) | All |
| Graph_SubscribedSkus | `GET /v1.0/subscribedSkus` | LicenseAssignment.Read.All (the toolkit uses Organization.Read.All, which is also listed) | Global Reader or Directory Readers | All |
| Graph_Users | `GET /v1.0/users?$select=...assignedLicenses` | User.Read.All | Global Reader | All |
| Graph_ReportSettings | `GET /v1.0/admin/reportSettings` | ReportSettings.Read.All | Reports limited administrator role | Global service only |
| Graph_CopilotUsage | `GET /v1.0/copilot/reports/getMicrosoft365CopilotUsageUserDetail(period='D180')` | Reports.Read.All | Reports Reader, AI Administrator, Exchange, SharePoint or Teams administrator. **Not Global Reader.** | Global service only (not GCC High or DoD) |
| Graph_CopilotUserCountTrend, Graph_CopilotUserCountSummary | `getMicrosoft365CopilotUserCountTrend`, `getMicrosoft365CopilotUserCountSummary` | Reports.Read.All | Same list plus Global Reader and Usage Summary Reports Reader | Global service only |
| Graph_ActiveUserDetail | `GET /v1.0/reports/getOffice365ActiveUserDetail(period='D30')` | Reports.Read.All | Reports Reader (Global Reader gets tenant-level data only) | All |
| Graph_ConditionalAccess | `GET /v1.0/identity/conditionalAccess/policies` | Policy.Read.All | Global Reader (Security Reader reads standard properties only) | All |
| Graph_SecurityDefaults | `GET /v1.0/policies/identitySecurityDefaultsEnforcementPolicy` | Policy.Read.All | Global Reader | All |
| Graph_RoleDefinitions, Graph_RoleAssignments | `GET /v1.0/roleManagement/directory/roleDefinitions`, `/roleAssignments?$expand=principal` | RoleManagement.Read.Directory | Global Reader or Directory Readers | All |
| Graph_SharePointSettings | `GET /v1.0/admin/sharepoint/settings` | SharePointTenantSettings.Read.All | Global Reader or SharePoint Administrator | All |
| Graph_CopilotPackages | `GET /v1.0/copilot/admin/catalog/packages` | CopilotPackages.Read.All | Learn lists no role. Learn states the API "requires a Microsoft Agent 365 license". | Global service only |
| Graph_SecureScore | `GET /v1.0/security/secureScores?$top=1` | SecurityEvents.Read.All | Security Reader or Security Administrator | Commercial, GCC, GCC High |

When the selected cloud is GCC High, the toolkit marks the global-only datasets as Unsupported and does not call them. Import the Copilot usage report from the admin center instead.

Learn references: [Copilot usage user detail](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/admin-settings/reports/copilotreportroot-getmicrosoft365copilotusageuserdetail), [Reports authorization](https://learn.microsoft.com/en-us/graph/reportroot-authorization), [List Copilot packages](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/admin-settings/package/copilotpackages-list), [List Conditional Access policies](https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-list-policies?view=graph-rest-1.0), [List role assignments](https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignments?view=graph-rest-1.0), [SharePoint settings](https://learn.microsoft.com/en-us/graph/api/sharepointsettings-get?view=graph-rest-1.0), [Secure scores](https://learn.microsoft.com/en-us/graph/api/security-list-securescores?view=graph-rest-1.0), [Security API authorization](https://learn.microsoft.com/en-us/graph/security-authorization).

### Granting consent

By default `Connect-MgGraph` uses the Microsoft Graph Command Line Tools enterprise app. The scopes above need admin consent. Pick one approach with the client:

**Option A: consent to Microsoft Graph Command Line Tools (quickest).** A Privileged Role Administrator, Cloud Application Administrator, or Application Administrator signs in once and grants tenant-wide consent:

```powershell
Connect-MgGraph -TenantId <tenant-guid> -Scopes 'Organization.Read.All','User.Read.All','ReportSettings.Read.All','Reports.Read.All','Policy.Read.All','RoleManagement.Read.Directory','SharePointTenantSettings.Read.All','CopilotPackages.Read.All','SecurityEvents.Read.All'
# Tick "Consent on behalf of your organization" in the prompt
```

**Option B: a dedicated app registration (recommended where the client restricts the shared app).** It isolates the consent to this assessment and can be deleted afterwards.

1. Entra admin center > App registrations > New registration. Name it, for example, `Copilot Readiness Assessment (read-only)`. Supported account types: this organization only.
2. Authentication > Add a platform > Mobile and desktop applications > redirect URI `http://localhost`. Allow public client flows: Yes.
3. API permissions > Add > Microsoft Graph > Delegated: add the nine scopes above. Grant admin consent.
4. Enterprise applications > the new app > Properties > Assignment required: Yes. Add the assessment account under Users and groups.
5. Run the toolkit with `-GraphClientId <application-id>`.

Reference: [Use your own application with Microsoft Graph PowerShell](https://learn.microsoft.com/en-us/powershell/microsoftgraph/authentication-commands?view=graph-powershell-1.0), [Grant tenant-wide admin consent](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/grant-admin-consent).

### Report name concealment

Microsoft 365 usage reports conceal user names by default. Only a Global Administrator can change this (Microsoft 365 admin center > Settings > Org settings > Reports). If names stay concealed, the toolkit cannot join the usage, Chat, and readiness reports by user. It then skips idle-user and qualified-candidate metrics instead of reporting wrong numbers. Agree with the client whether to show names for the assessment window and turn concealment back on afterwards.

## 3. SharePoint Online

| Operation | Requirement (Learn) |
|---|---|
| `Connect-SPOService`, `Get-SPOTenant`, `Get-SPOSite` | "You must be a SharePoint Administrator" (or SharePoint Embedded Administrator). Learn does not list Global Reader for this module. |
| `Start-`, `Get-`, `Export-SPODataAccessGovernanceInsight` | SharePoint Administrator and a SharePoint Advanced Management license. Microsoft 365 E5 without SharePoint Advanced Management gets activity reports only (no snapshot reports). |
| Module | Microsoft.Online.SharePoint.PowerShell, Windows only. Keep it current; the data access governance cmdlets exist only in recent versions. In PowerShell 7 the toolkit imports it with `-UseWindowsPowerShell` when needed. |
| Admin URL | `https://<tenant>-admin.sharepoint.com` (Commercial and GCC), `https://<tenant>-admin.sharepoint.us` (GCC High, region ITAR). |

If the client will not grant SharePoint Administrator, skip `-Collect SharePoint` and import the data access governance downloads and the Active sites export from the SharePoint admin center. A SharePoint Administrator can produce those.

References: [Connect-SPOService](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/connect-sposervice?view=sharepoint-ps), [Data access governance reports](https://learn.microsoft.com/en-us/sharepoint/data-access-governance-reports), [Start-SPODataAccessGovernanceInsight](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/start-spodataaccessgovernanceinsight?view=sharepoint-ps).

## 4. Microsoft Purview (Security & Compliance PowerShell)

| Cmdlets | Requirement |
|---|---|
| `Get-Label`, `Get-LabelPolicy`, `Get-AutoSensitivityLabelPolicy`, `Get-DlpCompliancePolicy`, `Get-DlpComplianceRule`, `Get-RetentionCompliancePolicy`, `Get-ComplianceTag` | The Purview **Global Reader** role group (granted with the Entra Global Reader role) includes Sensitivity Label Reader, View-Only DLP Compliance Management, View-Only Retention Management, and View-Only Record Management. Compliance Administrator or Compliance Data Administrator also work but add write roles. |
| Connection | `Connect-IPPSSession` from ExchangeOnlineManagement 3.x. GCC High uses `https://ps.compliance.protection.office365.us/powershell-liveid/` (set in `config/clouds.json`). |

References: [Permissions in the Microsoft Purview portal](https://learn.microsoft.com/en-us/purview/purview-permissions), [Security & Compliance permissions](https://learn.microsoft.com/en-us/defender-office-365/scc-permissions).

## 5. Exchange Online (audit)

| Cmdlet | Requirement (Learn) |
|---|---|
| `Search-UnifiedAuditLog -RecordType CopilotInteraction` | "Audit Logs or View-Only Audit Logs" role in Exchange Online. Results are capped at 5,000 per call; the toolkit records the sample as a sample. |
| `Get-AdminAuditLogConfig` | Must run in Exchange Online PowerShell (in Security & Compliance PowerShell `UnifiedAuditLogIngestionEnabled` always reads False). The cmdlet page does not name a specific role; confirm with the assessment account before the run. |

The toolkit keeps only aggregate fields from audit records (app, workload, resource counts, label IDs) and does not export user identities from the audit sample.

Reference: [Search the audit log](https://learn.microsoft.com/en-us/purview/audit-search), [Search-UnifiedAuditLog](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/search-unifiedauditlog?view=exchange-ps).

## 6. Power Platform and Microsoft Fabric

| API | Requirement (Learn) | Notes |
|---|---|---|
| Power Platform inventory (`POST https://api.powerplatform.com/resourcequery/resources/query`) | Global Reader, Power Platform Administrator, Dynamics 365 Administrator, or Global Administrator for all resources; AI Administrator and AI Reader see agents only. Delegated only (app-only returns 403). | Learn lists inventory in GCC and GCC High, but the toolkit enables API collection for Commercial only in v1.0. Use the inventory export elsewhere. |
| Power Platform environments (BAP admin API) | Power Platform Administrator or Dynamics 365 Administrator | Commercial only in v1.0. |
| Fabric tenant settings (`GET https://api.fabric.microsoft.com/v1/admin/tenantsettings`) | Fabric Administrator; delegated scope Tenant.Read.All. Limit 25 requests per minute. | Commercial only in v1.0. |

Tokens for these APIs come from `Connect-AzAccount` (Az.Accounts) with the same account.

References: [Power Platform inventory](https://learn.microsoft.com/en-us/power-platform/admin/power-platform-inventory), [Inventory API](https://learn.microsoft.com/en-us/power-platform/admin/inventory-api), [List tenant settings](https://learn.microsoft.com/en-us/rest/api/fabric/admin/tenants/list-tenant-settings).

## 7. Portal exports (import path)

People who export the reports in [EVIDENCE.md](EVIDENCE.md) need the role the portal requires for each report, for example Reports Reader or AI Administrator for Copilot reports in the Microsoft 365 admin center, access to the Copilot Dashboard in Viva Insights for its export, Purview access for DSPM exports, and SharePoint Administrator for data access governance downloads. The toolkit itself needs no access to read the exported files.

## 8. Network

The machine running the toolkit needs outbound HTTPS to Microsoft 365 endpoints: Microsoft Graph, login endpoints, SharePoint, Exchange Online and Security & Compliance PowerShell, and (if used) Power Platform and Fabric APIs and the PowerShell Gallery for module installs. See [Microsoft 365 URLs and IP address ranges](https://learn.microsoft.com/en-us/microsoft-365/enterprise/urls-and-ip-address-ranges?view=o365-worldwide) and, for GCC High, [GCC High endpoints](https://learn.microsoft.com/en-us/microsoft-365/enterprise/microsoft-365-u-s-government-gcc-high-endpoints?view=o365-worldwide).

## 9. Access request template

Copy this into the client request:

> For the Microsoft 365 Copilot readiness assessment, please provide a named account `<name>@<tenant>` with these roles from `<start date>` to `<end date>`: Global Reader, Reports Reader, Security Reader, and the Exchange Online View-Only Audit Logs role. Please make SharePoint Administrator, and optionally Power Platform Administrator and Fabric Administrator, PIM-eligible for the same period; they will be activated only during data collection. Please grant admin consent for the read-only Microsoft Graph delegated permissions listed in PERMISSIONS.md section 2 (or register the assessment app described in Option B). All collection is read-only; no settings or content are changed.
