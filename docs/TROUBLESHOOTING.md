# Troubleshooting

Every failure is recorded in `csv/diagnostics.csv` and on the dashboard Diagnostics page with the operation, the error, and guidance. A failed collector never stops the run; its datasets are marked Failed and the related checks show Not assessed.

| Symptom | Cause and fix |
|---|---|
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
