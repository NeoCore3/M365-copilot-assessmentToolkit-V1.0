# Evidence: portal exports the toolkit recognizes

Put all exports in one folder (subfolders are fine) and pass it with `-EvidencePath`. File names do not matter; each file is matched on its header row. CSV files may be UTF-8 with or without a byte order mark. XLSX files are read directly (no Excel needed); the header row may sit below a title block, as in Purview exports.

When two files match the same report, the newest (by the date in the file name, otherwise the modified time) is used for analysis and the older one is kept as `<Dataset>_Prior1` for trend comparison.

| Dataset | Export from | Recognized by these columns |
|---|---|---|
| IMP_EntraUsers | Entra admin center > Users > Download users, or a Graph users export | userPrincipalName, assignedLicenses |
| IMP_CopilotReadiness | Microsoft 365 admin center > Reports > Usage > Microsoft 365 Copilot > Readiness > Export | Has Copilot license assigned, Uses eligible update channel |
| IMP_CopilotUsage | Reports > Usage > Microsoft 365 Copilot > Usage, 180 days > Export | Prompts submitted for All Apps, Last Activity Date |
| IMP_CopilotChat | Reports > Usage > Copilot Chat > Export | Prompts submitted, Active usage days, User principal name |
| IMP_CopilotSearch | Reports > Usage > Copilot Search > Export | Total searches |
| IMP_AgentUsageAgents | Reports > Usage > Agents > Agents tab > Export | Agent ID, Active users (licensed) |
| IMP_AgentUsageUsersAgents | Agents > Users and agents tab > Export | Agent ID, Username, Responses sent to users |
| IMP_AgentUsageUsers | Agents > Users tab > Export | Number of agents used |
| IMP_AgentRegistry | Microsoft 365 admin center > Agents > All agents > Export | Publisher Type, Platform, Owner, Status |
| IMP_CopilotStudioInventory | Power Platform admin center > Manage > Inventory > Agents > Export | Created in, Environment type, Managed environment, Authentication |
| IMP_AgentFlows | Power Platform admin center > Manage > Inventory > Agent flows > Export | Item type, Trigger, Environment type |
| IMP_ConnectorsUsage | Reports > Usage > Connectors > Export | Connection ID, Responses provided in Copilot |
| IMP_ConnectorsUsers | Connectors > Users > Export | Connections used, Responses received from connectors |
| IMP_VivaCopilot | Viva Insights > Copilot Dashboard > Export (person-week metrics) | PersonId, MetricDate |
| IMP_DagSharePoint / IMP_DagOneDrive | SharePoint admin center > Reports > Data access governance > Site permissions > Download (SharePoint and OneDrive reports), or `-DagMode Export` | Number of users having access, Items with unique permissions count (OneDrive is detected from the -my.sharepoint URLs) |
| IMP_DagEEEUItems / IMP_DagEveryoneItems | Data access governance > Content shared with Everyone except external users / Everyone > Download | Role definition, Item url, Parent group type (split on the Recipient value) |
| IMP_ActiveSites | SharePoint admin center > Sites > Active sites > Export | Last activity (UTC), Storage used (GB), Files viewed or edited |
| IMP_AIObservability | Purview > DSPM > AI observability > Export (CSV or XLSX) | Agent ID, Risk level, Risk types (file names containing "AI Apps" become IMP_AIObservabilityApps) |
| IMP_DspmAiActivity | Purview > DSPM > Activity explorer > AI activities > Export | Sheet header: Activity type, Timestamp (UTC), App |
| IMP_DspmAllActivity | Purview > Activity explorer > all activity types > Export | Sheet header: CreationTime (UTC), Activity, Workload |
| IMP_DspmApps | Purview > DSPM > Discover > Apps and agents > Apps > Export | Sheet header: AI app, Data protection, Total prompts (30 days) |
| IMP_DspmAgents | Purview > DSPM > Discover > Apps and agents > Agents > Export | Sheet header: Agent, Data protection, Total prompts (30 days) |
| IMP_DspmDataRisk | Purview > DSPM > Data risk assessments > Default assessment > Export | Sheet header: Site name, Total items, Total sensitive items |

A Word document of screenshots (`.docx`) is inventoried with its image count so screenshot references (SS-nnn) in the written assessment can be traced.

## Export tips

- Before exporting usage reports, confirm that reports show user names (Microsoft 365 admin center > Settings > Org settings > Reports) for the assessment window, or user-level joins are skipped.
- Export the Copilot usage report for 180 days and the readiness report on the same day where possible; the dashboard states the refresh date of each.
- Activity explorer exports are capped at 10,000 rows. Filter by date to export complete slices, or treat the export as a sample (the dashboard does).
- Keep the exports in the client's evidence location. Do not copy them into this repository.

## Adding a new export type

Add an entry to `config/import-rules.json` with a `Dataset` id, `Workstream`, `Format` (`csv`, `xlsx`, or `any`), the `Columns` (CSV) or `SheetHeader` (XLSX) that identify it, and the `Portal` path. Then add metrics for it in `src/Analyze.ps1`.
