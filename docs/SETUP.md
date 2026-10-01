# Setup

## Requirements

- PowerShell 7.2 or later (Windows, macOS, or Linux). On Windows, the SharePoint module may load through Windows PowerShell compatibility; the toolkit handles this.
- Modules for live collection (`./Install-Prerequisites.ps1` installs them for the current user):

| Module | Used for |
|---|---|
| Microsoft.Graph.Authentication | Microsoft Graph requests |
| ExchangeOnlineManagement 3.x | Security & Compliance PowerShell and Exchange Online audit |
| Microsoft.Online.SharePoint.PowerShell | SharePoint tenant, sites, data access governance (16.0.25409 or later; 16.0.27215.12000 or later for Everyone and EEEU item reports) |
| Az.Accounts | Delegated tokens for Power Platform and Fabric APIs |

No module is needed for `-OfflineOnly`.

## Sign-in model

All collection is delegated and interactive. The toolkit only issues `GET` requests, report functions, and `Get-*` cmdlets. The one exception is `-DagMode Start`, which asks SharePoint Advanced Management to generate data access governance reports; it does not change permissions or content. It is off by default.

Use a dedicated read-only assessment account, approved by the client, with the least roles below.

## Roles

| Collector | Least role that works | Notes |
|---|---|---|
| Graph | Global Reader plus Reports Reader | Reports Reader covers usage reports. Copilot catalog may need a Copilot or AI admin role; see the Learn page for the packages API. |
| SharePoint | SharePoint Administrator | Data access governance reports also need SharePoint Advanced Management (or Copilot licensing that includes it). |
| Purview | Compliance Administrator or Global Reader | Needed for Get-Label, Get-DlpCompliancePolicy, Get-RetentionCompliancePolicy. |
| Exchange audit | View-Only Audit Logs (and Global Reader for configuration) | Search-UnifiedAuditLog requires an audit role. |
| Power Platform | Power Platform Administrator | Inventory API is delegated only. |
| Fabric | Fabric Administrator | Tenant settings API. |

## Microsoft Graph scopes

Requested by `Connect-MgGraph` (admin consent is needed once for the Microsoft Graph Command Line Tools app, or use a client-approved app):

`Organization.Read.All, User.Read.All, ReportSettings.Read.All, Reports.Read.All, Policy.Read.All, RoleManagement.Read.Directory, SharePointTenantSettings.Read.All, CopilotPackages.Read.All, SecurityEvents.Read.All`

If usage reports conceal user names (Microsoft 365 admin center > Settings > Org settings > Reports), joins between exports by user principal name are not possible. The toolkit detects concealed names and skips the join-based metrics rather than producing wrong figures. Ask the client to show names for the assessment window or accept the reduced analysis.

## Clouds

| Cloud | Graph | Exchange / Compliance | SharePoint | Copilot usage APIs | Power Platform and Fabric APIs |
|---|---|---|---|---|---|
| Commercial | graph.microsoft.com | default | Default region | Yes | Yes |
| GCC | graph.microsoft.com | default | Default region | Yes | Import portal exports (disabled in v1.0) |
| GCC High | graph.microsoft.us | O365USGovGCCHigh, ps.compliance.protection.office365.us | ITAR region | Not available (import the portal export) | Import portal exports (disabled in v1.0) |

Endpoints are in `config/clouds.json`.

## Recommended run sequence

1. Day 1: ask the client to export the portal reports in [EVIDENCE.md](EVIDENCE.md) into one folder. If SharePoint Advanced Management is available, run with `-Collect SharePoint -DagMode Start` to request the data access governance reports.
2. Day 2 or later (reports take hours): run the full assessment with `-DagMode Export` and `-EvidencePath` pointing at the export folder.
3. Re-run with `-OfflineOnly` whenever new exports arrive; collection does not need to be repeated.
