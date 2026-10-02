# Changelog

## 1.0.1 (2026-10-02)

Fixes found in the first live customer run, where every collector failed and the report was empty.

- **Collectors now run in separate PowerShell processes.** Microsoft Graph, SharePoint Online, Exchange Online, and Az modules ship conflicting versions of MSAL and System.Text.Json; loaded into one process, the second module to sign in failed ("Could not load file or assembly Microsoft.Identity.Client", "No valid OAuth 2.0 authentication session exists"). Each group (Graph, SharePoint, Purview plus Exchange, Power Platform plus Fabric) now loads its module in a clean process and hands its results back to the main run.
- **Microsoft.Graph.Authentication 2.41.0 is skipped.** It fails to load System.Text.Json 10.0.0.0 on PowerShell 7.5 (msgraph-sdk-powershell issue 3810). The toolkit uses the newest other installed version, and Install-Prerequisites.ps1 installs 2.40.0 when only 2.41.0 is present (config/modules.json).
- **Missing API properties no longer stop a collector.** StrictMode is removed and every API field is read safely, so an omitted property (for example `linkedEnvironmentMetadata` or `enabledSecurityGroups`) becomes an empty value.
- **Graph paging fixed.** `@odata.nextLink` is now followed correctly.
- **Power Platform inventory request fixed** (HTTP 400): the request body now follows the Microsoft Learn example with `$type` first in each clause, and includes environment type and Managed Environment state, which now feed checks PP-01 and PP-02 when no portal export is supplied.
- **Fabric tenant settings** read from `tenantSettings` as documented, with continuation paging.
- **SharePoint** retries through Windows PowerShell compatibility when the native sign-in fails, as Microsoft Learn recommends for PowerShell 7.
- **Graph Copilot usage JSON** column names (for example `wordCopilotLastActivityDate`) are mapped for per-app metrics.
- **Evidence import** skips the toolkit's own files and earlier run outputs when -EvidencePath points at the toolkit folder, and warns.
- **Visibility:** a collection summary is printed after collection, an error line appears when no tenant data was collected, and the dashboard shows a red banner linking to Diagnostics when collectors fail.
- **Tests:** a mock tenant (tests/Mock-Tenant.ps1) now exercises every live collector end to end in separate processes, and a Windows CI job installs the real Microsoft modules and verifies each group loads in isolation (tests/Test-ModuleLoad.ps1).

## 1.0.0 (2026-10-01)

First release of the rebuilt toolkit (replaces NeoCore3/m365-copilot-assessmen).

- Hybrid model: read-only collection (Microsoft Graph, SharePoint Online, Security & Compliance, Exchange Online audit, Power Platform, Fabric) plus automatic recognition of 24 portal export types by header row (CSV and XLSX, including Purview exports with title blocks).
- Commercial, GCC, and GCC High cloud profiles.
- Analysis engine producing about 90 metrics with denominators and sources, and 55 checks across 15 readiness domains with Microsoft Learn references.
- Automated readiness indicator with risk-weighted domain scores, coverage, and confidence flags; missing data reported as NO DATA AVAILABLE and never scored as a failure.
- Self-contained HTML dashboard (overview, domains, checks with details panel, metrics, data coverage, evidence inventory with SHA-256, diagnostics, dark mode, print).
- CSV exports for metrics, checks, domain scores, dataset status, evidence inventory, diagnostics, and normalized source data; manifest and run log.
- Repairs the Copilot Search export (unquoted commas), detects OneDrive versus SharePoint DAG reports by URL, splits Everyone and EEEU item reports, keeps older snapshots as prior versions, labels portal-capped exports as samples.
- Permissions verified against Microsoft Learn: docs/PERMISSIONS.md (roles, Graph scopes, consent options, per-API requirements, access request template), Test-Prerequisites.ps1, and -GraphClientId for a client-registered app.
- Global-service-only Graph APIs (Copilot reports, report settings, Copilot packages) are marked Unsupported in GCC High instead of being called.
- Synthetic sample evidence generator, offline self-test, and GitHub Actions validation on Windows and Linux.
