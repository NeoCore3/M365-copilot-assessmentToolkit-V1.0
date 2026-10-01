# Usage guide

Step-by-step instructions for running the toolkit in a Copilot readiness engagement, with examples for each scenario.

## 1. Install

```powershell
# PowerShell 7.2 or later: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell
git clone https://github.com/NeoCore3/M365-copilot-assessmentToolkit-V1.0.git
cd M365-copilot-assessmentToolkit-V1.0

# Only needed for live collection (not for -OfflineOnly)
./Install-Prerequisites.ps1
```

If scripts are blocked on Windows, run `Unblock-File -Path .\*.ps1, .\src\*.ps1, .\tests\*.ps1` or start PowerShell with `-ExecutionPolicy Bypass` for the session.

## 2. Try it on synthetic data first

```powershell
./tests/New-SampleEvidence.ps1 -Path ./sample-evidence
./Invoke-CopilotReadinessAssessment.ps1 -CustomerName 'Contoso' -EvidencePath ./sample-evidence -OfflineOnly
```

Open `output/Contoso-<timestamp>/CopilotReadinessDashboard.html`. A prebuilt example is in [sample-dashboard.html](sample-dashboard.html) (download and open locally).

## 3. Collect the portal exports from the client

Ask the client admin (or do it with them on a call) to export the reports listed in [EVIDENCE.md](EVIDENCE.md) into one folder, for example `E:\Clients\Contoso\Discovery Documents`. Keep the original exports; the toolkit only reads them.

Minimum useful set:

| Priority | Export |
|---|---|
| Must have | Copilot usage (180 days), Copilot readiness, Copilot Chat usage |
| Must have | SharePoint DAG site permissions (SharePoint and OneDrive), Content shared with EEEU |
| Should have | Agents registry, Copilot Studio inventory, Agents usage, Viva Insights Copilot Dashboard |
| Should have | Purview DSPM: Apps, Agents, data risk assessment, AI activity |
| Nice to have | Active sites, Copilot Search, connectors, AI observability, Entra users |

## 4. Choose a run mode

### Example A: offline, exports only (no tenant access)

Use this when you only have the client's exports, or to re-run after new exports arrive.

```powershell
./Invoke-CopilotReadinessAssessment.ps1 `
    -CustomerName 'Contoso' `
    -EvidencePath 'E:\Clients\Contoso\Discovery Documents' `
    -OfflineOnly
```

Several folders:

```powershell
./Invoke-CopilotReadinessAssessment.ps1 -CustomerName 'Contoso' -OfflineOnly `
    -EvidencePath 'E:\Clients\Contoso\Discovery Documents', 'E:\Clients\Contoso\New SPO reports'
```

### Example B: full run, Commercial tenant

Sign in with a read-only assessment account (roles in [SETUP.md](SETUP.md)). Each service prompts for sign-in once.

```powershell
./Invoke-CopilotReadinessAssessment.ps1 `
    -TenantId 11111111-2222-3333-4444-555555555555 `
    -CustomerName 'Contoso' `
    -EvidencePath 'E:\Clients\Contoso\Discovery Documents' `
    -SharePointAdminUrl 'https://contoso-admin.sharepoint.com' `
    -AdminUpn 'assessment.reader@contoso.com'
```

### Example C: SharePoint data access governance reports in two passes

DAG reports take hours to generate. Request them on day 1, export and analyze on day 2.

```powershell
# Day 1: request the reports (needs SharePoint Advanced Management)
./Invoke-CopilotReadinessAssessment.ps1 -TenantId <guid> -CustomerName 'Contoso' `
    -Collect SharePoint -SharePointAdminUrl 'https://contoso-admin.sharepoint.com' -DagMode Start

# Day 2: download completed reports and run everything
./Invoke-CopilotReadinessAssessment.ps1 -TenantId <guid> -CustomerName 'Contoso' `
    -EvidencePath 'E:\Clients\Contoso\Discovery Documents' `
    -SharePointAdminUrl 'https://contoso-admin.sharepoint.com' -DagMode Export
```

### Example D: only some services

```powershell
# Identity, licensing and Purview only
./Invoke-CopilotReadinessAssessment.ps1 -TenantId <guid> -CustomerName 'Contoso' -Collect Graph, Purview -AdminUpn 'reader@contoso.com'
```

### Example E: GCC High

```powershell
./Invoke-CopilotReadinessAssessment.ps1 -TenantId <guid> -CustomerName 'Agency' -Cloud GCCHigh `
    -EvidencePath 'D:\Agency\Exports' `
    -SharePointAdminUrl 'https://agency-admin.sharepoint.us' -AdminUpn 'reader@agency.onmicrosoft.us'
```

Copilot usage APIs, Power Platform, and Fabric collection are marked Unsupported in GCC High; import the portal exports instead.

### Example F: longer audit sample and row previews

```powershell
./Invoke-CopilotReadinessAssessment.ps1 -TenantId <guid> -CustomerName 'Contoso' -Collect Exchange -AuditDays 30 -IncludeRowPreview
```

`-IncludeRowPreview` embeds the first 25 rows of each dataset in the dashboard. It puts user names and URLs into the HTML; use it only for internal working copies.

## 5. Read the results

| Where | What to look at |
|---|---|
| Dashboard > Overview | Automated readiness indicator, check results, key figures, domain scores, priority findings |
| Dashboard > Checks | Filter by domain, status, or risk; click a row for the finding, recommendation, threshold, evidence file, and Microsoft Learn link |
| Dashboard > Data coverage | Which datasets were collected, imported, failed, or unsupported, and why |
| Dashboard > Evidence files | Every file found, what it was recognized as, and its SHA-256 |
| `csv/metrics.csv` | Every figure with denominator and source file; use it when writing the assessment |
| `csv/checks.csv` | Findings and recommendations ready to adapt into the risk tables |
| `csv/diagnostics.csv` | Anything that failed, with guidance |

## 6. Use the output in the written assessment

1. Copy figures from `metrics.csv` with their denominators; cite the source file shown in the Source column.
2. For each Fail or Warning check, build the 7-row finding table (Observation, Business Impact, Risk Level, Recommendation, Expected Outcome, Priority, Estimated Effort) from the check's finding and recommendation.
3. For Not assessed checks, mark the gap as NO DATA AVAILABLE in the document and list the missing artifact from the Data needed field in the Limitations section.
4. Verify Manual checks in the named portal and add screenshots to the pack.
5. The automated indicator is an input to the consultant scorecard, not a replacement for it. Where coverage is low, say so.

## 7. Re-run and compare

Each run writes a new timestamped folder, so earlier results are kept. Re-run offline after the client sends updated exports; when two exports of the same report exist, the newest is analyzed and the older is kept as `<Dataset>_Prior1`.

## 8. Validate the toolkit after changes

```powershell
./tests/Test-Toolkit.ps1
```
