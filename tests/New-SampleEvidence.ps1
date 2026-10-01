#Requires -Version 7.2
<#
.SYNOPSIS
    Generates a synthetic evidence folder (fictitious Contoso data) that mirrors the column layout of the
    Microsoft 365 admin center, Viva Insights, Power Platform, SharePoint, and Purview portal exports.
    Used by tests and for demonstrating the dashboard without client data.
#>
param([string]$Path = (Join-Path $PSScriptRoot 'sample-evidence'), [int]$Seed = 42)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $Path -Force | Out-Null
$rnd = [System.Random]::new($Seed)
function RndInt([int]$a, [int]$b) { return $rnd.Next($a, $b + 1) }
function Pick($arr) { return $arr[$rnd.Next(0, $arr.Count)] }
function D([int]$daysAgo) { return ([datetime]'2026-09-20').AddDays(-$daysAgo).ToString('yyyy-MM-dd') }
function Save([string]$name, $rows) { $rows | Export-Csv -LiteralPath (Join-Path $Path $name) -NoTypeInformation -Encoding utf8BOM }

$first = 'Avery', 'Blake', 'Casey', 'Drew', 'Emery', 'Finley', 'Harper', 'Jordan', 'Kendall', 'Logan', 'Morgan', 'Parker', 'Quinn', 'Riley', 'Rowan', 'Sawyer', 'Taylor'
$last = 'Adams', 'Brooks', 'Chen', 'Diaz', 'Evans', 'Foster', 'Garcia', 'Hughes', 'Ito', 'Jones', 'Kim', 'Lopez', 'Moore', 'Nguyen', 'Patel', 'Reed'
$depts = 'Finance', 'Sales', 'Operations', 'IT', 'Legal', 'HR', 'Marketing', ''
$copilotSku = '639dec6b-bb19-468b-871c-c5c441c4b0cb'; $e3 = '05e9a617-0261-4cee-bb44-138d3ef5d965'
$users = for ($i = 1; $i -le 300; $i++) {
    $f = Pick $first; $l = Pick $last
    [pscustomobject]@{ Upn = "$f.$l$i@contoso.com".ToLower(); Name = "$l, $f"; Id = [guid]::new($rnd.Next(), 1, 1, 0, 0, 0, 0, 0, 0, 0, [byte]($i % 255)).ToString(); Copilot = ($i -le 80); Guest = ($i -gt 285) }
}

# Entra users
Save 'Entra users export.csv' ($users | ForEach-Object {
        $lic = if ($_.Guest) { '[]' } elseif ($_.Copilot) { "[{""disabledPlans"":[],""skuId"":""$copilotSku""},{""disabledPlans"":[],""skuId"":""$e3""}]" } else { "[{""disabledPlans"":[],""skuId"":""$e3""}]" }
        [ordered]@{ id = $_.Id; displayName = $_.Name; userPrincipalName = $_.Upn; userType = $(if ($_.Guest) { 'Guest' } else { 'Member' }); onPremisesSyncEnabled = 'True'; department = (Pick $depts); jobTitle = ''; assignedLicenses = $lic } | ForEach-Object { [pscustomobject]$_ } })
$members = @($users | Where-Object { -not $_.Guest })

# Copilot readiness
Save 'Copilot readiness export.csv' ($members | ForEach-Object { [pscustomobject][ordered]@{ 'Report Refresh Date' = '2026-09-20'; 'User Principal Name' = $_.Upn; 'Has Copilot license assigned' = $_.Copilot; 'Suggested candidate for Copilot' = ((-not $_.Copilot) -and (RndInt 0 2) -eq 0); 'Report Period' = 30; 'Uses eligible update channel' = ((RndInt 0 9) -gt 1); 'Uses Teams meetings' = 'True'; 'Uses Teams chat' = 'True'; 'Uses Outlook email' = 'True'; 'Uses Office docs' = 'True' } })

# Copilot usage (licensed)
$apps = 'Copilot Chat (work)', 'Teams Copilot', 'Word Copilot', 'Excel Copilot', 'PowerPoint Copilot', 'Outlook Copilot', 'OneNote Copilot', 'Loop Copilot'
Save 'Copilot usage export.csv' ($members | Where-Object Copilot | ForEach-Object {
        $o = [ordered]@{ 'Report Refresh Date' = '2026-09-21'; 'User Principal Name' = $_.Upn; 'Display Name' = $_.Name }
        $never = (RndInt 0 19) -eq 0
        $o['Last Activity Date'] = if ($never) { '' } else { D (RndInt 0 60) }
        $o['Report Period'] = 180
        $o['Prompts submitted for All Apps'] = if ($never) { 0 } else { RndInt 5 1500 }
        $o['Active Usage Days for All Apps'] = if ($never) { 0 } else { RndInt 1 120 }
        foreach ($a in $apps) { $o["Last activity date of $a (UTC)"] = if ($never -or (RndInt 0 2) -eq 0) { '' } else { D (RndInt 0 90) } }
        [pscustomobject]$o })

# Copilot Chat (unlicensed and licensed)
Save 'Copilot Chat usage export.csv' ($members | Select-Object -First 220 | ForEach-Object {
        $p = if ((RndInt 0 3) -eq 0) { 0 } else { RndInt 1 200 }
        [pscustomobject][ordered]@{ 'Report refresh date' = '2026-09-22'; 'User guid' = $_.Id; 'User principal name' = $_.Upn; 'Display name' = $_.Name; 'Report period' = 28; 'Prompts submitted' = $p; 'Active usage days' = $(if ($p) { RndInt 1 20 } else { 0 }); 'Last activity date' = $(if ($p) { D (RndInt 0 27) } else { D (RndInt 30 170) }) } })

# Copilot Search (reproduces the portal's unquoted commas)
$lines = @('User ID,Display name,Total searches,Last activity date (UTC)') + @($members | Select-Object -First 25 | ForEach-Object { "{0},{1},{2},Wednesday,, 23 September 2026" -f $_.Upn, $_.Name, (RndInt 1 9) })
Set-Content -LiteralPath (Join-Path $Path 'Copilot Search export.csv') -Value $lines -Encoding utf8

# Agents usage
$agentNames = 'Policy Helper', 'Invoice Checker', 'Sales Coach', 'IT Helpdesk', 'Contract Reviewer', 'Onboarding Buddy', 'Researcher', 'Analyst'
Save 'Agents usage - agents.csv' ($agentNames | ForEach-Object { [pscustomobject][ordered]@{ 'Agent ID' = "T_$([guid]::NewGuid())"; 'Agent name' = $_; 'Creator type' = 'User-created agent'; 'Active users (licensed)' = (RndInt 1 40); 'Active users (unlicensed)' = (RndInt 0 5); 'Responses sent to users' = (RndInt 5 900); 'Last activity date (UTC)' = 'Sep 19, 2026' } })
Save 'Agents usage - users.csv' ($members | Select-Object -First 40 | ForEach-Object { [pscustomobject][ordered]@{ Username = $_.Upn; 'Display name' = $_.Name; 'Number of agents used' = (RndInt 1 4); 'Agent responses received' = (RndInt 1 80); 'Last activity date (UTC)' = 'Sep 19, 2026' } })
Save 'Agents usage - users and agents.csv' ($members | Select-Object -First 40 | ForEach-Object { [pscustomobject][ordered]@{ 'Agent ID' = 'T_00000000-0000-0000-0000-000000000001'; 'Agent name' = (Pick $agentNames); 'Creator type' = 'User-created agent'; Username = $_.Upn; 'Responses sent to users' = (RndInt 1 30); 'Last activity date (UTC)' = 'Sep 19, 2026' } })

# Agent registry (Microsoft 365 admin center > Agents)
Save 'Agents registry export.csv' (1..60 | ForEach-Object {
        $pt = Pick @('Shared', 'Shared', 'Shared', 'FirstParty', 'ThirdParty')
        [pscustomobject][ordered]@{ Name = "Agent $_"; Status = (Pick @('Available', 'Available', 'Draft', 'Not available')); Channel = ''; 'Date created' = '2026-05-01 02:21:07Z'; 'Last Modified' = '2026-09-01 04:06:07Z'; Publisher = ''; 'Publisher Type' = $pt; Version = '1.0'; Owner = $(if ($pt -eq 'Shared' -and (RndInt 0 3) -gt 0) { (Pick $members).Upn } else { '' }); Description = 'Synthetic agent'; Platform = (Pick @('Copilot Studio', 'Agent Builder in Microsoft 365 Copilot', 'SharePoint')) } })

# Power Platform inventory
Save 'Copilot Studio agents inventory.csv' (1..90 | ForEach-Object {
        $et = Pick @('Default', 'Default', 'Default', 'Production', 'Sandbox')
        [pscustomobject][ordered]@{ 'Item name' = "Maker agent $_"; 'Created in' = (Pick @('Copilot Studio', 'Microsoft 365 Copilot Agent Builder')); 'Item ID' = [guid]::NewGuid(); Status = 'Available'; Owner = (Pick $members).Name; Connectors = (Pick @('-', 'shared_commondataserviceforapps', 'shared_sharepointonline')); Model = 'Microsoft 365 Copilot'; Authentication = (Pick @('Microsoft Entra', 'Microsoft Entra', 'Microsoft Entra', 'None')); 'Created by' = (Pick @('-', (Pick $members).Name)); Environment = $(if ($et -eq 'Default') { 'Contoso (default)' } else { "Contoso $et" }); 'Environment type' = $et; 'Managed environment' = $(if ($et -eq 'Production') { 'Yes' } else { 'No' }) } })
Save 'Agent flows inventory.csv' (1..12 | ForEach-Object { [pscustomobject][ordered]@{ 'Item name' = "Flow $_"; 'Item type' = 'Agent flow'; 'Item ID' = [guid]::NewGuid(); Owner = (Pick $members).Name; Connectors = 'shared_sharepointonline'; Trigger = '-'; 'Environment type' = (Pick @('Default', 'Production')); 'Managed environment' = 'No' } })

# Connectors
Save 'Connectors usage.csv' @([pscustomobject][ordered]@{ 'Connection ID' = 'ServiceNowKB'; 'Active users' = 3; 'Responses provided in Copilot' = 11; 'Last activity date (UTC)' = 'Sep 10, 2026' })

# Viva Insights Copilot Dashboard (person-week)
$weeks = 0..11 | ForEach-Object { ([datetime]'2026-09-06').AddDays(-7 * $_).ToString('yyyy-MM-dd') } | Sort-Object
Save 'Viva Copilot dashboard export.csv' $(foreach ($u in ($members | Select-Object -First 120)) { foreach ($w in $weeks) { [pscustomobject][ordered]@{ PersonId = $u.Id; MetricDate = $w; 'Copilot Enabled User' = $(if ($u.Copilot) { 1 } else { '' }); 'Total Copilot active days' = $(if ($u.Copilot -and (RndInt 0 4) -gt 0) { RndInt 1 5 } else { 0 }); 'Days of active Copilot Chat usage (without Copilot license)' = $(if (-not $u.Copilot -and (RndInt 0 2) -eq 0) { RndInt 1 3 } else { 0 }); Organization = (Pick $depts) } } })

# SharePoint data access governance
$dagCols = { param($url, $tmpl, $users, $priv) [pscustomobject][ordered]@{ 'Tenant ID' = '00000000-0000-0000-0000-000000000000'; 'Site ID' = [guid]::NewGuid(); 'Site name' = ($url -split '/')[-1]; 'Site URL' = $url; 'Site template' = $tmpl; 'Primary admin' = 'Owners'; 'External sharing' = 'false'; 'Site privacy' = $priv; 'Site sensitivity' = (Pick @('General', 'Confidential', '')); 'Number of users having access' = $users; 'Entra group count' = (RndInt 0 4); 'File count' = (RndInt 0 3000); 'Items with unique permissions count' = $(if ((RndInt 0 2) -eq 0) { RndInt 1 200 } else { 0 }); 'PeopleInYourOrg link count' = (RndInt 0 20); 'Anyone link count' = (RndInt 0 1); 'EEEU permission count' = $(if ((RndInt 0 9) -eq 0) { 1 } else { 0 }); 'Everyone permission count' = 0; 'Report date' = '2026-09-05T02:10:33Z' } }
Save 'DAG site permissions SharePoint.csv' (1..150 | ForEach-Object { & $dagCols "https://contoso.sharepoint.com/sites/Site$_" 'Team site' $(if ($_ -le 3) { RndInt 1000 5000 } else { RndInt 2 400 }) (Pick @('Private', 'Public')) })
Save 'DAG site permissions OneDrive.csv' (1..200 | ForEach-Object { & $dagCols "https://contoso-my.sharepoint.com/personal/user$_" 'Other site' $(if ($_ -le 6) { RndInt 100 2000 } else { RndInt 1 60 }) '' })
$itemCols = { param($recip, $role) [pscustomobject][ordered]@{ 'Tenant ID' = '00000000-0000-0000-0000-000000000000'; 'Site ID' = "site-$(RndInt 1 12)"; 'Item type' = 'File'; 'Item url' = "sites/Site$(RndInt 1 150)/Shared Documents/file$(RndInt 1 999).docx"; 'Role definition' = $role; Recipient = $recip; 'Parent group type' = 'SharePointGroup'; 'Total user count' = (RndInt 100 900); 'Report date' = '2026-09-09T02:40:37Z' } }
Save 'DAG content shared with Everyone except external users.csv' (1..30 | ForEach-Object { & $itemCols 'Everyone except external users' (Pick @('Edit', 'Edit', 'Read', 'Contribute', 'Full Control')) })
Save 'DAG content shared with Everyone.csv' (1..2 | ForEach-Object { & $itemCols 'Everyone' 'Read' })

# Active sites
Save 'Active sites export.csv' (1..150 | ForEach-Object { [pscustomobject][ordered]@{ 'Site name' = "Site$_"; URL = "https://contoso.sharepoint.com/sites/Site$_"; Teams = 'True'; 'Storage used (GB)' = [math]::Round($rnd.NextDouble() * 50, 2); Template = 'Team site'; 'Last activity (UTC)' = ([datetime]'2026-09-08').AddDays(-(RndInt 0 500)).ToString('M/d/yyyy h:mm:ss tt', [cultureinfo]::InvariantCulture); 'Files viewed or edited' = (RndInt 0 50); Files = (RndInt 0 900); Sensitivity = (Pick @('General', 'Confidential', '')); 'External sharing' = 'Off' } })

# AI observability (CSV variant)
Save 'AI observability export.csv' (1..40 | ForEach-Object { [pscustomobject][ordered]@{ Name = "Agent $_"; Platform = 'EmbeddedCopilotStudio'; Status = 'Available'; 'Agent ID' = "T_$([guid]::NewGuid())"; 'Risk level' = (Pick @('None', 'None', 'None', 'Low')); 'Risk types' = 'No data available'; 'Sensitive activity trend' = 'No sensitive activity detected in the last 30 days' } })

# ---------- XLSX writer (inline strings) for Purview DSPM exports ----------
function New-Xlsx {
    param([string]$File, [System.Collections.Specialized.OrderedDictionary]$Sheets)
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    if (Test-Path $File) { Remove-Item $File }
    $zip = [System.IO.Compression.ZipFile]::Open($File, 'Create')
    function Put([string]$n, [string]$c) { $e = $zip.CreateEntry($n); $w = [System.IO.StreamWriter]::new($e.Open(), [System.Text.UTF8Encoding]::new($false)); $w.Write($c); $w.Dispose() }
    function Col([int]$i) { $s = ''; $i++; while ($i -gt 0) { $m = ($i - 1) % 26; $s = [char](65 + $m) + $s; $i = [int][math]::Floor(($i - 1) / 26) }; return $s }
    $names = @($Sheets.Keys)
    Put '[Content_Types].xml' ('<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' + (($names | ForEach-Object -Begin { $i = 0 } -Process { $i++; "<Override PartName=""/xl/worksheets/sheet$i.xml"" ContentType=""application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml""/>" }) -join '') + '</Types>')
    Put '_rels/.rels' '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
    $i = 0; $sx = ''; $rx = ''
    foreach ($n in $names) { $i++; $sx += "<sheet name=""$([System.Security.SecurityElement]::Escape($n))"" sheetId=""$i"" r:id=""rId$i""/>"; $rx += "<Relationship Id=""rId$i"" Type=""http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"" Target=""worksheets/sheet$i.xml""/>" }
    Put 'xl/workbook.xml' "<?xml version=""1.0"" encoding=""UTF-8""?><workbook xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"" xmlns:r=""http://schemas.openxmlformats.org/officeDocument/2006/relationships""><sheets>$sx</sheets></workbook>"
    Put 'xl/_rels/workbook.xml.rels' "<?xml version=""1.0"" encoding=""UTF-8""?><Relationships xmlns=""http://schemas.openxmlformats.org/package/2006/relationships"">$rx</Relationships>"
    $i = 0
    foreach ($n in $names) {
        $i++; $sb = [System.Text.StringBuilder]::new(); $r = 0
        foreach ($row in $Sheets[$n]) {
            $r++; [void]$sb.Append("<row r=""$r"">")
            for ($c = 0; $c -lt @($row).Count; $c++) {
                $v = @($row)[$c]; if ($null -eq $v -or "$v" -eq '') { continue }
                $ref = (Col $c) + $r
                if ($v -is [int] -or $v -is [double]) { [void]$sb.Append("<c r=""$ref""><v>$v</v></c>") }
                else { [void]$sb.Append("<c r=""$ref"" t=""inlineStr""><is><t>$([System.Security.SecurityElement]::Escape([string]$v))</t></is></c>") }
            }
            [void]$sb.Append('</row>')
        }
        Put "xl/worksheets/sheet$i.xml" "<?xml version=""1.0"" encoding=""UTF-8""?><worksheet xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main""><sheetData>$($sb.ToString())</sheetData></worksheet>"
    }
    $zip.Dispose()
}
$title = , @("Microsoft Purview`nDSPM`nSummary Report")
$blank = @(, @(), , @(), , @(), , @())

$act = [System.Collections.Generic.List[object]]::new()
$act.AddRange([object[]]($title + $blank)); $act.Add(@('Activity type', 'Activity', 'Timestamp (UTC)', 'AI app category', 'App', 'Sensitive info type count'))
$act.Add(@('Note:', 'This export was limited to 10,000 items. Apply filters for more specific data.'))
for ($k = 0; $k -lt 400; $k++) { $act.Add(@('AI Interaction', 'Copilot Interaction', ([datetime]'2026-09-25T05:00:00').AddMinutes(-$k).ToOADate(), 'Copilot experiences & agents', (Pick @('M365Copilot - Bizchat', 'M365Copilot - Teams')), (Pick @(0, 0, 0, 1)))) }
$sum = [System.Collections.Generic.List[object]]::new(); $sum.AddRange([object[]]($title + $blank)); $sum.Add(@('Report generated', '2026-09-25')); $sum.Add(@('Total Activities', 400))
$s = [ordered]@{ 'Summary' = $sum; 'Activity explorer data' = $act }
New-Xlsx -File (Join-Path $Path 'DSPM AI activity export.xlsx') -Sheets $s

$apps = [System.Collections.Generic.List[object]]::new(); $apps.AddRange([object[]]($title + $blank)); $apps.Add(@('AI app', 'Protection status', 'Data protection', 'Active users (30 days)', 'Total prompts (30 days)'))
$apps.Add(@('Microsoft 365 Copilot', 'Monitored', '1 Policy', 120, 5400)); $apps.Add(@('Microsoft Copilot Studio', 'Monitored', '0 Policies', 30, 900)); $apps.Add(@('ChatGPT', 'Not monitored', '0 Policies', 12, 300))
New-Xlsx -File (Join-Path $Path 'DSPM Apps export.xlsx') -Sheets ([ordered]@{ 'Apps data' = $apps })

$dra = [System.Collections.Generic.List[object]]::new(); $dra.AddRange([object[]]($title + $blank)); $dra.Add(@('Site name', 'Source type', 'Sensitivity label', 'Total items', 'Total sensitive items'))
1..15 | ForEach-Object { $t = RndInt 10 900; $dra.Add(@("Site$_", 'SharePoint / Private', (Pick @('None', 'General')), $t, (RndInt 0 $t))) }
New-Xlsx -File (Join-Path $Path 'DSPM data risk assessment export.xlsx') -Sheets ([ordered]@{ 'Data risk assessment results' = $dra })

Write-Host "Synthetic evidence written to $Path ($(@(Get-ChildItem $Path -File).Count) files)."
