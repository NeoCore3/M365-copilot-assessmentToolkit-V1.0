# Evidence importer: recognizes manually exported portal reports (CSV and XLSX) by their column headers,
# not by file name, so renamed files are still recognized. Every file in the evidence folders is inventoried
# (name, size, SHA-256, matched dataset, row count), including files that are not recognized.

function Get-FileDateKey {
    <# Sort key for picking the newest snapshot when two exports map to the same dataset. #>
    param([System.IO.FileInfo]$File)
    $d = Get-FileNameDate $File
    if ($d) { return $d }
    return $File.LastWriteTimeUtc
}

function Get-FileNameDate {
    <# Export date embedded in a portal file name, or $null. #>
    param([System.IO.FileInfo]$File)
    $n = $File.Name
    if ($n -match '(20\d{2})[-_]?(\d{2})[-_]?(\d{2})') {
        try { return [datetime]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3]) } catch { }
    }
    if ($n -match '(\d{1,2})_(\d{1,2})_(20\d{2})') {
        try { return [datetime]::new([int]$Matches[3], [int]$Matches[1], [int]$Matches[2]) } catch { }
    }
    return $null
}

function Read-CsvText {
    <# Reads a CSV, strips one or more byte order marks, and returns objects. Handles quoted line breaks. #>
    param([string]$Path)
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $text = $text.TrimStart([char]0xFEFF, [char]0x200B)
    if ([string]::IsNullOrWhiteSpace($text)) { return , @() }
    return , @($text | ConvertFrom-Csv)
}

function Get-CsvHeader {
    param([string]$Path)
    $sr = [System.IO.StreamReader]::new($Path, [System.Text.Encoding]::UTF8)
    try { $line = $sr.ReadLine() } finally { $sr.Dispose() }
    if (-not $line) { return @() }
    $line = $line.TrimStart([char]0xFEFF, [char]0x200B)
    try { return @(($line | ConvertFrom-Csv -Header (1..400 | ForEach-Object { "c$_" })).PSObject.Properties | Where-Object { $_.Value } | ForEach-Object { [string]$_.Value }) }
    catch { return @($line -split ',') }
}

function Repair-CopilotSearchCsv {
    <# The Copilot Search export writes unquoted display names and dates that contain commas,
       for example: user@contoso.com,Doe, Jane,3,Wednesday,, 23 September 2026 #>
    param([string]$Path)
    $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
    $out = [System.Collections.Generic.List[object]]::new()
    $bad = 0
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $l = $lines[$i].TrimStart([char]0xFEFF)
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        $m = [regex]::Match($l, '^(?<upn>[^,]+),(?<name>.*?),(?<n>\d+),(?<date>[^,]*(?:,.*)?)$')
        $m2 = [regex]::Match($l, '^(?<upn>[^,]+),(?<name>.*),(?<n>\d+),(?<date>[A-Za-z]+day,.*)$')
        $use = if ($m2.Success) { $m2 } elseif ($m.Success) { $m } else { $null }
        if (-not $use) { $bad++; continue }
        $dateText = ($use.Groups['date'].Value -replace '^[A-Za-z]+day,,?\s*', '').Trim().Trim('"')
        $dt = $null; $tmp = [datetime]::MinValue
        if ([datetime]::TryParseExact($dateText, 'd MMMM yyyy', [System.Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$tmp)) { $dt = $tmp.ToString('yyyy-MM-dd') }
        $out.Add([pscustomobject][ordered]@{
                'User ID'                   = $use.Groups['upn'].Value.Trim()
                'Display name'              = $use.Groups['name'].Value.Trim().Trim('"')
                'Total searches'            = [int]$use.Groups['n'].Value
                'Last activity date (UTC)'  = if ($dt) { $dt } else { $dateText }
            })
    }
    return [pscustomobject]@{ Rows = $out.ToArray(); Unparsed = $bad }
}

function Test-HeaderMatch {
    param([string[]]$Headers, $Rule)
    $keys = @($Headers | ForEach-Object { ConvertTo-Key $_ })
    foreach ($c in @($Rule.Columns)) { if ($keys -notcontains (ConvertTo-Key $c)) { return $false } }
    if ($Rule.PSObject.Properties['Exclude']) { foreach ($c in @($Rule.Exclude)) { if ($keys -contains (ConvertTo-Key $c)) { return $false } } }
    return $true
}

function Get-DocxImageCount {
    param([string]$Path)
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try { return @($z.Entries | Where-Object { $_.FullName -like 'word/media/*' }).Count } finally { $z.Dispose() }
    }
    catch { return $null }
}

function Invoke-EvidenceImport {
    param([string[]]$EvidencePath, [string]$RulesPath)
    $rules = Get-Content -LiteralPath $RulesPath -Raw | ConvertFrom-Json
    $folders = @($EvidencePath | Where-Object { $_ }) + @($script:Ctx.ExtraEvidenceFolders)
    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $toolkitRoot = (Split-Path $PSScriptRoot -Parent).TrimEnd('\', '/')
    $toolkitDirs = @('src', 'config', 'report', 'docs', 'tests', '.github', '.git', 'output')
    $skipped = 0
    foreach ($f in $folders) {
        if (-not (Test-Path -LiteralPath $f)) { [void](Add-Diagnostic 'Import' 'Evidence folder' "Folder not found: $f" 'Check -EvidencePath.'); continue }
        $isExtra = $f -in @($script:Ctx.ExtraEvidenceFolders)
        $full = (Resolve-Path -LiteralPath $f).Path.TrimEnd('\', '/')
        if ($full -eq $toolkitRoot) { Write-Log "Evidence path is the toolkit folder itself. Toolkit files and earlier run outputs are skipped; put the portal exports in their own folder and pass that with -EvidencePath." 'Warn' }
        $runFolders = @(Get-ChildItem -LiteralPath $f -Filter 'manifest.json' -File -Recurse -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.DirectoryName 'run.log') } | ForEach-Object { $_.DirectoryName })
        foreach ($fi in Get-ChildItem -LiteralPath $f -File -Recurse -ErrorAction SilentlyContinue) {
            if (-not $isExtra -and $fi.FullName.StartsWith($script:Ctx.OutDir)) { continue }
            if (-not $isExtra -and ($runFolders | Where-Object { $fi.FullName.StartsWith($_) })) { $skipped++; continue }
            if (-not $isExtra -and $fi.FullName.StartsWith($toolkitRoot)) {
                $rel = $fi.FullName.Substring($toolkitRoot.Length).TrimStart('\', '/')
                $first = ($rel -split '[\\/]')[0]
                if ($rel -notmatch '[\\/]' -or $first -in $toolkitDirs) { $skipped++; continue }
            }
            if ($fi.Name -like '~$*') { continue }
            $files.Add($fi)
        }
    }
    Write-Log "Evidence import: $($files.Count) files found in $($folders.Count) folder(s)$(if ($skipped) { "; $skipped toolkit or earlier-output files skipped" })"

    $invList = [System.Collections.Generic.List[object]]::new()
    $hits = [System.Collections.Generic.List[object]]::new()
    foreach ($fi in $files) {
        $ext = $fi.Extension.ToLowerInvariant()
        $inv = [ordered]@{ File = $fi.Name; Folder = $fi.DirectoryName; SizeBytes = $fi.Length; LastWriteUtc = $fi.LastWriteTimeUtc.ToString('o'); Sha256 = ''; Dataset = ''; Sheet = ''; Rows = ''; Note = '' }
        try { $inv.Sha256 = (Get-FileHash -LiteralPath $fi.FullName -Algorithm SHA256).Hash } catch { }
        try {
            if ($ext -eq '.csv') {
                $hdr = Get-CsvHeader $fi.FullName
                $rule = $rules | Where-Object { $_.Format -in @('csv', 'any') -and (Test-HeaderMatch $hdr $_) } | Select-Object -First 1
                if ($rule) { $hits.Add([pscustomobject]@{ File = $fi; Rule = $rule; Kind = 'csv'; Sheet = ''; Inv = $inv }) }
                else { $inv.Note = 'Not recognized (no import rule matches the header row)' }
            }
            elseif ($ext -eq '.xlsx') {
                $sheets = Read-XlsxSheets $fi.FullName
                $hit = $false
                foreach ($rule in ($rules | Where-Object { $_.Format -in @('xlsx', 'any') -and $_.PSObject.Properties['SheetHeader'] })) {
                    foreach ($sn in $sheets.Keys) {
                        $objs = ConvertFrom-SheetRows -SheetRows $sheets[$sn] -HeaderKeys @($rule.SheetHeader)
                        if ($null -ne $objs) {
                            $summary = $null
                            foreach ($other in $sheets.Keys) { if ($other -match '^summary$') { $summary = Get-SummaryPairs $sheets[$other] } }
                            $hits.Add([pscustomobject]@{ File = $fi; Rule = $rule; Kind = 'xlsx'; Sheet = $sn; Objects = $objs; Summary = $summary; Inv = $inv })
                            $hit = $true; break
                        }
                    }
                    if ($hit) { break }
                }
                if (-not $hit) { $inv.Note = 'Workbook not recognized (no sheet header matches an import rule)' }
            }
            elseif ($ext -eq '.docx') {
                $n = Get-DocxImageCount $fi.FullName
                $inv.Dataset = 'ScreenshotPack'; $inv.Rows = $n; $inv.Note = "Word document with $n embedded image(s). Screenshots are referenced manually as SS-nnn in the deliverable."
            }
            else { $inv.Note = 'Not a CSV, XLSX, or DOCX file; inventoried only' }
        }
        catch { $inv.Note = 'Read error: ' + (Add-Diagnostic 'Import' $fi.Name $_ 'Re-export the file from the portal or save it as CSV UTF-8.') }
        $invList.Add($inv)
    }

    # Resolve each match to a final dataset id (with splits), then pick newest snapshot per id.
    $resolved = [System.Collections.Generic.List[object]]::new()
    foreach ($m in $hits) {
        $id = $m.Rule.Dataset
        $rows = $null; $note = ''
        if ($m.Kind -eq 'csv') {
            if ($m.Rule.PSObject.Properties['Repair'] -and $m.Rule.Repair -eq 'CopilotSearch') {
                $rep = Repair-CopilotSearchCsv $m.File.FullName
                $rows = $rep.Rows
                $note = "Repaired unquoted commas in the portal export; $($rep.Unparsed) line(s) could not be parsed."
            }
            else { $rows = Read-CsvText $m.File.FullName }
        }
        else {
            $rows = @($m.Objects | Where-Object { "$($_.PSObject.Properties.Value | Select-Object -First 1)" -ne 'Note:' })
            $noteRow = @($m.Objects | Where-Object { "$($_.PSObject.Properties.Value | Select-Object -First 1)" -eq 'Note:' } | Select-Object -First 1)
            if ($noteRow.Count) { $note = 'Portal note: ' + [string](@($noteRow[0].PSObject.Properties.Value)[1]) }
        }
        $rows = @($rows)
        if ($m.Rule.PSObject.Properties['SplitOneDrive'] -and $m.Rule.SplitOneDrive) {
            $map = Get-HeaderMap $rows; $uc = Resolve-Column $map @('Site URL')
            $od = @($rows | Select-Object -First 200 | Where-Object { "$(Get-Val $_ $uc)" -match '-my\.sharepoint\.' }).Count
            $id = if ($od -gt ([math]::Min(200, $rows.Count) / 2) -or $m.File.Name -match 'onedrive') { 'IMP_DagOneDrive' } else { 'IMP_DagSharePoint' }
        }
        if ($m.Rule.PSObject.Properties['SplitEveryone'] -and $m.Rule.SplitEveryone) {
            $map = Get-HeaderMap $rows; $rc = Resolve-Column $map @('Recipient')
            $eeeu = @($rows | Select-Object -First 200 | Where-Object { "$(Get-Val $_ $rc)" -match 'except external' }).Count
            $id = if ($eeeu -gt 0 -or $m.File.Name -match 'except') { 'IMP_DagEEEUItems' } else { 'IMP_DagEveryoneItems' }
        }
        if ($m.Rule.PSObject.Properties['SplitAiApps'] -and $m.Rule.SplitAiApps -and $m.File.Name -match 'AI Apps') { $id = 'IMP_AIObservabilityApps' }
        $resolved.Add([pscustomobject]@{ Id = $id; M = $m; Rows = $rows; Note = $note; DateKey = (Get-FileDateKey $m.File) })
    }

    foreach ($g in ($resolved | Group-Object Id)) {
        $ordered = @($g.Group | Sort-Object DateKey, @{ Expression = { $_.M.File.LastWriteTimeUtc } } -Descending)
        for ($i = 0; $i -lt $ordered.Count; $i++) {
            $r = $ordered[$i]; $m = $r.M
            $finalId = if ($i -eq 0) { $r.Id } else { "$($r.Id)_Prior$i" }
            $expl = "Portal export recognized by header columns. Portal path: $($m.Rule.Portal)."
            if ($i -gt 0) { $expl += ' Older snapshot of the same report; kept for trend comparison only.' }
            if ($r.Note) { $expl += " $($r.Note)" }
            $status = if ($r.Rows.Count) { 'Imported' } else { 'Empty' }
            $copy = if ($m.Kind -eq 'csv' -and -not ($m.Rule.PSObject.Properties['Repair'])) { $m.File.FullName } else { '' }
            Add-Dataset -Id $finalId -Workstream $m.Rule.Workstream -Status $status -Origin 'Imported' -Source $m.File.Name -Explanation $expl -Rows $r.Rows -File $m.File.Name -CopyFrom $copy
            $script:Ctx.Datasets[$finalId].Sheet = $m.Sheet
            $script:Ctx.Datasets[$finalId].FileDate = Get-FileNameDate $m.File
            $script:Ctx.Datasets[$finalId].Summary = if ($m.PSObject.Properties['Summary']) { $m.Summary } else { $null }
            $script:Ctx.Datasets[$finalId].Truncated = [bool]($r.Note -match 'limited to')
            $m.Inv.Dataset = $finalId; $m.Inv.Sheet = $m.Sheet; $m.Inv.Rows = $r.Rows.Count
            if ($r.Note) { $m.Inv.Note = $r.Note }
            Write-Log ("{0}: {1} rows from {2}" -f $finalId, $r.Rows.Count, $m.File.Name) 'Ok'
        }
    }
    foreach ($i in $invList) { $script:Ctx.Inventory.Add([pscustomobject]$i) }
}
