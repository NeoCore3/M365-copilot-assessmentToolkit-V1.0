# Changelog

## 1.0.0 (2026-10-01)

First release of the rebuilt toolkit (replaces NeoCore3/m365-copilot-assessmen).

- Hybrid model: read-only collection (Microsoft Graph, SharePoint Online, Security & Compliance, Exchange Online audit, Power Platform, Fabric) plus automatic recognition of 24 portal export types by header row (CSV and XLSX, including Purview exports with title blocks).
- Commercial, GCC, and GCC High cloud profiles.
- Analysis engine producing about 90 metrics with denominators and sources, and 55 checks across 15 readiness domains with Microsoft Learn references.
- Automated readiness indicator with risk-weighted domain scores, coverage, and confidence flags; missing data reported as NO DATA AVAILABLE and never scored as a failure.
- Self-contained HTML dashboard (overview, domains, checks with details panel, metrics, data coverage, evidence inventory with SHA-256, diagnostics, dark mode, print).
- CSV exports for metrics, checks, domain scores, dataset status, evidence inventory, diagnostics, and normalized source data; manifest and run log.
- Repairs the Copilot Search export (unquoted commas), detects OneDrive versus SharePoint DAG reports by URL, splits Everyone and EEEU item reports, keeps older snapshots as prior versions, labels portal-capped exports as samples.
- Synthetic sample evidence generator, offline self-test, and GitHub Actions validation on Windows and Linux.
