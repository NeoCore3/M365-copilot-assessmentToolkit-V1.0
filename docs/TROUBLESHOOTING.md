# Troubleshooting

Every failure is recorded in `csv/diagnostics.csv` and on the dashboard Diagnostics page with the operation, the error, and guidance. A failed collector never stops the run; its datasets are marked Failed and the related checks show Not assessed.

| Symptom | Cause and fix |
|---|---|
| Every collector fails within a second and the report is empty | You are running v1.0.0, which loaded all Microsoft modules into one process. Update to 1.0.1 or later; each collector group now runs in its own process. |
| `Could not load file or assembly 'System.Text.Json, Version=10.0.0.0'` at Connect-MgGraph | Microsoft.Graph.Authentication 2.41.0 on PowerShell 7.5. Run `./Install-Prerequisites.ps1` (adds 2.40.0; the toolkit skips 2.41.0 automatically). |
| `Could not load file or assembly ... Microsoft.Identity.Client.dll ... manifest definition does not match` | Another module's authentication library was already loaded. Fixed by process isolation in 1.0.1. If it still appears, close all PowerShell windows and run from a fresh `pwsh -NoProfile`. |
| `No valid OAuth 2.0 authentication session exists` (SharePoint) | Same cause as above. 1.0.1 also retries through Windows PowerShell compatibility automatically. |
| Evidence import counts toolkit files (for example README.md) | -EvidencePath points at the toolkit folder. Put the portal exports in their own folder and pass that path. 1.0.1 skips toolkit files and earlier outputs. |
| `Signed-in tenant ... does not match -TenantId` | The account signed in to a different tenant. Sign out (`Disconnect-MgGraph`) and use an account in the target tenant. |
| Graph datasets Failed with 403 | Missing admin consent for a scope or missing role. See PERMISSIONS.md section 2. |
| Graph_CopilotUsage fails with 403 but other Graph data works | The per-user Copilot usage API does not accept Global Reader. Add Reports Reader (or AI Administrator) to the account. |
| Graph_SecureScore fails with 403 | Add Security Reader. |
| Graph_CopilotPackages fails | Microsoft Learn states the packages API requires a Microsoft Agent 365 license. Record it as not available. |
| Copilot usage, report settings, or packages Unsupported | These APIs are global service only per Microsoft Learn (not GCC High). Import the portal export. |
| `Connect-SPOService` access denied | The SharePoint module requires SharePoint Administrator. Activate the PIM role, or skip SharePoint collection and import the admin center downloads. |
| `Connect-SPOService` fails on PowerShell 7 | Install the latest Microsoft.Online.SharePoint.PowerShell. On Windows the toolkit retries with Windows PowerShell compatibility. Use the `-admin` URL. |
| DAG cmdlets not found or fail | Requires SharePoint Advanced Management (Microsoft 365 E5 without it gets activity reports only, no snapshot reports) and a current SharePoint module (`Update-Module Microsoft.Online.SharePoint.PowerShell`). Otherwise download the reports from the SharePoint admin center and import them. |
| DAG reports not ready | Generation takes hours. Run `-DagMode Start`, then later `-DagMode Export`. |
| `Search-UnifiedAuditLog` fails | Needs an audit role; the CopilotInteraction record type requires a current ExchangeOnlineManagement module. Search in the Purview portal and treat the result as evidence. |
| Power Platform or Fabric token refused | Install Az.Accounts and sign in with Power Platform Administrator or Fabric Administrator. Otherwise export the inventory from the Power Platform admin center. |
| A file shows "Not recognized" in Evidence files | The header row does not match an import rule. Check the export type in EVIDENCE.md, re-export, or add a rule. |
| Idle users or qualified pool missing | Usage reports conceal user names, so exports cannot be joined. Show names for the assessment window and re-export. |
| Numbers differ from the portal tile | Tiles and exports use different windows and populations. The dashboard reports the export value with its denominator; record the tile value and the delta in the written assessment. |
| Large exports take time | The Viva Insights person-week export can exceed 100,000 rows; allow one to two minutes. |
