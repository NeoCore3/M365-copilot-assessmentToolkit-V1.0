# Setup

This page covers the machine, modules, clouds, and the run sequence. Roles, Microsoft Graph scopes, and consent are in [PERMISSIONS.md](PERMISSIONS.md).

## 1. Machine requirements

| Requirement | Detail |
|---|---|
| Operating system | Windows 10 or 11, or Windows Server 2019 or later, for a full run. macOS and Linux can run offline analysis and the Graph, Purview, Exchange, Power Platform, and Fabric collectors, but not the SharePoint collector (the SharePoint module is Windows only). |
| PowerShell | PowerShell 7.2 or later (`pwsh`). Install: [Installing PowerShell on Windows](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows). Windows PowerShell 5.1 must also be present on Windows (it is by default) for the SharePoint module compatibility load. |
| Browser | Needed for interactive sign-in and to open the dashboard. Any current browser. |
| Network | Outbound HTTPS to Microsoft 365, Graph, and login endpoints, plus the PowerShell Gallery for module installs. See [PERMISSIONS.md, section 8](PERMISSIONS.md#8-network). |
| Disk | About 100 MB per run for large tenants (the normalized CSVs). |
| Execution policy | If scripts are blocked: `Unblock-File -Path .\*.ps1, .\src\*.ps1, .\tests\*.ps1`, or run `pwsh -ExecutionPolicy Bypass -File ...` for the session. |

## 2. Modules

Only needed for live collection. Offline analysis (`-OfflineOnly`) needs no modules.

```powershell
./Install-Prerequisites.ps1        # installs or updates for the current user
./Test-Prerequisites.ps1           # checks versions and prints the access the account needs
```

| Module | Collectors | Notes |
|---|---|---|
| Microsoft.Graph.Authentication | Graph | Only the authentication module is used; requests go through `Invoke-MgGraphRequest`. |
| Microsoft.Online.SharePoint.PowerShell | SharePoint | Windows only. Keep current; data access governance cmdlets exist only in recent versions. |
| ExchangeOnlineManagement 3.x | Purview, Exchange | Provides `Connect-IPPSSession` and `Connect-ExchangeOnline`. |
| Az.Accounts | Power Platform, Fabric | Used only to obtain delegated tokens. Skip with `./Install-Prerequisites.ps1 -SkipAz` if you will not collect these. |

## 3. Access

Short version (full detail and Learn references in [PERMISSIONS.md](PERMISSIONS.md)):

| Collector | Roles for the assessment account | Graph scopes or API permission |
|---|---|---|
| Graph | Global Reader, Reports Reader (required for per-user Copilot usage), Security Reader (Secure Score) | Nine delegated scopes with admin consent |
| SharePoint | SharePoint Administrator (PIM, activate for the run); SharePoint Advanced Management license for DAG snapshot reports | n/a |
| Purview | Global Reader (Purview Global Reader role group) | n/a |
| Exchange | View-Only Audit Logs | n/a |
| Power Platform | Power Platform Administrator for environments; Global Reader for inventory | Delegated token through Az.Accounts |
| Fabric | Fabric Administrator | Delegated token (Tenant.Read.All) through Az.Accounts |

## 4. Clouds

| Cloud | `-Cloud` | Graph | Exchange / Compliance | SharePoint admin URL | APIs not available, import instead |
|---|---|---|---|---|---|
| Commercial | `Commercial` | graph.microsoft.com | default | `https://<tenant>-admin.sharepoint.com` | none |
| GCC | `GCC` | graph.microsoft.com | default | `https://<tenant>-admin.sharepoint.com` | Power Platform and Fabric APIs (disabled in v1.0) |
| GCC High | `GCCHigh` | graph.microsoft.us | O365USGovGCCHigh; `ps.compliance.protection.office365.us` | `https://<tenant>-admin.sharepoint.us` (region ITAR) | Copilot report APIs, report settings, Copilot packages (Learn: global service only), Power Platform and Fabric APIs |

Endpoints are in `config/clouds.json`.

## 5. Run sequence for an engagement

| When | Who | Action |
|---|---|---|
| Kickoff | Client admin | Create or nominate the assessment account, assign roles, grant Graph consent ([PERMISSIONS.md section 9](PERMISSIONS.md#9-access-request-template) has a request template). Decide on report name concealment. |
| Kickoff | Client admin or consultant | Export the portal reports in [EVIDENCE.md](EVIDENCE.md) into one folder. |
| Day 1 | Consultant | `./Test-Prerequisites.ps1`. If SharePoint Advanced Management is available: `-Collect SharePoint -DagMode Start` to request DAG reports. |
| Day 2 or later | Consultant | Full run with `-DagMode Export` and `-EvidencePath`. |
| Any time | Consultant | Re-run with `-OfflineOnly` when new exports arrive. Collection does not need repeating. |
| Close | Client admin | Remove the roles, deactivate PIM eligibility, remove consent or delete the app registration if one was created. |

## 6. First live run

```powershell
./Test-Prerequisites.ps1
./Invoke-CopilotReadinessAssessment.ps1 `
    -TenantId <tenant-guid> `
    -CustomerName '<Client>' `
    -EvidencePath '<path to portal exports>' `
    -SharePointAdminUrl 'https://<tenant>-admin.sharepoint.com' `
    -AdminUpn '<assessment account UPN>'
```

Expect up to five sign-in prompts: Microsoft Graph, SharePoint, Security & Compliance, Exchange Online, and one Azure sign-in if Power Platform or Fabric are collected. After the run, review `csv/diagnostics.csv` (or the dashboard Diagnostics page) for anything that failed for lack of a role, fix it, and re-run only that collector with `-Collect`.
