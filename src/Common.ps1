# Common helpers: run context, logging, dataset registry, safe CSV export, XLSX reader, field access.
# StrictMode is intentionally not enabled: Microsoft APIs omit properties freely, and a missing property must
# read as $null (then reported as no data), never stop a collector.

function New-RunContext {
    param([string]$OutDir, [string]$CustomerName, [string]$TenantId, [string]$Cloud)
    $script:Ctx = [ordered]@{
        OutDir       = $OutDir
        CustomerName = $CustomerName
        TenantId     = $TenantId
        Cloud        = $Cloud
        StartedUtc   = [datetime]::UtcNow
        Datasets     = [ordered]@{}
        Status       = [System.Collections.Generic.List[object]]::new()
        Diagnostics  = [System.Collections.Generic.List[object]]::new()
        Inventory    = [System.Collections.Generic.List[object]]::new()
        Metrics      = [ordered]@{}
        MetricRows   = [System.Collections.Generic.List[object]]::new()
        Checks       = [System.Collections.Generic.List[object]]::new()
        ExtraEvidenceFolders = @()
    }
    foreach ($d in @($OutDir, (Join-Path $OutDir 'csv'), (Join-Path $OutDir 'csv/data'), (Join-Path $OutDir 'raw'))) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
    return $script:Ctx
}

function Write-Log {
    param([string]$Message, [ValidateSet('Info', 'Warn', 'Error', 'Ok')][string]$Level = 'Info')
    $color = @{ Info = 'Gray'; Warn = 'Yellow'; Error = 'Red'; Ok = 'Green' }[$Level]
    $line = '{0:u} [{1}] {2}' -f [datetime]::UtcNow, $Level.ToUpper(), $Message
    Write-Host $line -ForegroundColor $color
    if ($script:Ctx) { Add-Content -LiteralPath (Join-Path $script:Ctx.OutDir 'run.log') -Value $line -Encoding utf8 }
}

function Add-Diagnostic {
    param([string]$Area, [string]$Operation, $ErrorRecord, [string]$Guidance = '')
    $msg = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { $ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
    $script:Ctx.Diagnostics.Add([pscustomobject]@{
            TimeUtc   = [datetime]::UtcNow.ToString('o')
            Area      = $Area
            Operation = $Operation
            Message   = ($msg -replace '\s+', ' ').Trim()
            Guidance  = $Guidance
        })
    return ($msg -replace '\s+', ' ').Trim()
}

function Add-Dataset {
    <#
      Registers a dataset. Origin: Collected (API/PowerShell) or Imported (portal export).
      Status: Collected, Imported, Failed, NotRequested, Unsupported, ManualRequired, Empty.
    #>
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Workstream,
        [Parameter(Mandatory)][string]$Status,
        [string]$Origin = 'Collected',
        [string]$Source = '',
        [string]$Explanation = '',
        [object[]]$Rows = @(),
        [string]$File = '',
        [string]$CopyFrom = ''
    )
    $Rows = @($Rows | Where-Object { $null -ne $_ })
    $entry = [ordered]@{
        Id = $Id; Workstream = $Workstream; Status = $Status; Origin = $Origin; Source = $Source
        Explanation = $Explanation; RowCount = $Rows.Count; File = $File; Rows = $Rows
        RecordedUtc = [datetime]::UtcNow.ToString('o')
    }
    $script:Ctx.Datasets[$Id] = $entry
    $script:Ctx.Status.Add([pscustomobject]@{
            Dataset = $Id; Workstream = $Workstream; Status = $Status; Origin = $Origin; Rows = $Rows.Count
            Source = $Source; File = $File; Explanation = $Explanation; RecordedUtc = $entry.RecordedUtc
        })
    if ($Status -in @('Collected', 'Imported') -and $Rows.Count -gt 0) {
        $safeName = ($Id -replace '[^A-Za-z0-9_\-]', '_')
        if ($CopyFrom -and (Test-Path -LiteralPath $CopyFrom) -and $CopyFrom -like '*.csv') { Copy-Item -LiteralPath $CopyFrom -Destination (Join-Path $script:Ctx.OutDir "csv/data/$safeName.csv") -Force; return }
        Export-SafeCsv -Rows $Rows -Path (Join-Path $script:Ctx.OutDir "csv/data/$safeName.csv")
        if ($Origin -eq 'Collected') {
            ConvertTo-Json -InputObject $Rows -Depth 20 -Compress | Set-Content -LiteralPath (Join-Path $script:Ctx.OutDir "raw/$safeName.json") -Encoding utf8
        }
    }
}

function Get-DatasetRows {
    param([string[]]$Ids)
    foreach ($id in $Ids) {
        if ($script:Ctx.Datasets.Contains($id) -and $script:Ctx.Datasets[$id].Status -in @('Collected', 'Imported') -and $script:Ctx.Datasets[$id].RowCount -gt 0) {
            return , @($script:Ctx.Datasets[$id].Rows)
        }
    }
    return $null
}

function Get-DatasetInfo {
    param([string]$Id)
    if ($script:Ctx.Datasets.Contains($Id)) { return $script:Ctx.Datasets[$Id] }
    return $null
}

function ConvertTo-SafeCell {
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return $Value.ToString('o') }
    if ($Value -isnot [string] -and ($Value -is [System.Collections.IEnumerable] -or $Value -is [System.Management.Automation.PSCustomObject] -or $Value -is [System.Collections.IDictionary])) {
        $Value = ConvertTo-Json -InputObject $Value -Depth 10 -Compress
    }
    $s = [string]$Value
    # Prevent spreadsheet formula injection when CSVs are opened in Excel.
    if ($s -match '^\s*[=+\-@]' -and $s -notmatch '^-?\d+(\.\d+)?$') { return "'" + $s }
    return $s
}

function Export-SafeCsv {
    param([object[]]$Rows, [string]$Path)
    $Rows = @($Rows)
    if ($Rows.Count -eq 0) { '"Status"' + [Environment]::NewLine + '"No rows"' | Set-Content -LiteralPath $Path -Encoding utf8; return }
    $columns = [System.Collections.Generic.List[string]]::new()
    foreach ($r in ($Rows | Select-Object -First 500)) {
        $names = if ($r -is [System.Collections.IDictionary]) { $r.Keys } else { $r.PSObject.Properties.Name }
        foreach ($n in $names) { if (-not $columns.Contains([string]$n)) { $columns.Add([string]$n) } }
    }
    $out = foreach ($r in $Rows) {
        $o = [ordered]@{}
        foreach ($n in $columns) {
            $v = if ($r -is [System.Collections.IDictionary]) { $r[$n] } else { $r.$n }
            $o[$n] = ConvertTo-SafeCell $v
        }
        [pscustomobject]$o
    }
    $out | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8
}

# ---------- Field access tolerant of header differences between API and portal exports ----------
function ConvertTo-Key { param([string]$Name) return ($Name.ToLowerInvariant() -replace '[^a-z0-9]', '') }

function Get-HeaderMap {
    param([object[]]$Rows)
    $map = @{}
    if (-not $Rows -or $Rows.Count -eq 0) { return $map }
    $first = $Rows[0]
    $names = if ($first -is [System.Collections.IDictionary]) { $first.Keys } else { $first.PSObject.Properties.Name }
    foreach ($n in $names) { $k = ConvertTo-Key $n; if (-not $map.ContainsKey($k)) { $map[$k] = [string]$n } }
    return $map
}

function Resolve-Column {
    param([hashtable]$Map, [string[]]$Candidates)
    foreach ($c in $Candidates) {
        $k = ConvertTo-Key $c
        if ($Map.ContainsKey($k)) { return $Map[$k] }
    }
    foreach ($c in $Candidates) {
        $k = ConvertTo-Key $c
        $hit = $Map.Keys | Where-Object { $_.StartsWith($k) } | Select-Object -First 1
        if ($hit) { return $Map[$hit] }
    }
    return $null
}

function Get-Val { param($Row, [string]$Column) if (-not $Column) { return $null } if ($Row -is [System.Collections.IDictionary]) { return $Row[$Column] } return $Row.$Column }

function ConvertTo-Num {
    param($Value)
    if ($null -eq $Value) { return $null }
    $s = ([string]$Value).Trim() -replace ',', ''
    if ($s -eq '' -or $s -eq '-') { return $null }
    $d = 0.0
    if ([double]::TryParse($s, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return $null
}

function ConvertTo-Bool {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [bool]) { return $Value }
    $s = ([string]$Value).Trim().ToLowerInvariant()
    if ($s -in @('true', 'yes', '1', 'y')) { return $true }
    if ($s -in @('false', 'no', '0', 'n')) { return $false }
    return $null
}

function ConvertTo-Date {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value }
    $s = ([string]$Value).Trim()
    if ($s -eq '' -or $s -eq '-' -or $s -match '^(none|never|no data)') { return $null }
    $d = ConvertTo-Num $s
    if ($null -ne $d -and $d -gt 20000 -and $d -lt 80000 -and $s -notmatch '[-/]') { return [datetime]::FromOADate($d) }
    $formats = @('yyyy-MM-dd', 'yyyy-MM-ddTHH:mm:ssZ', 'yyyy-MM-ddTHH:mm:ss.fffZ', 'M/d/yyyy h:mm:ss tt', 'M/d/yyyy H:mm:ss', 'M/d/yyyy', 'MM/dd/yyyy HH:mm:ss', 'dd/MM/yyyy', 'yyyy-MM-dd HH:mm:ss')
    $dt = [datetime]::MinValue
    foreach ($f in $formats) {
        if ([datetime]::TryParseExact($s, $f, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$dt)) { return $dt }
    }
    if ([datetime]::TryParse($s, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$dt)) { return $dt }
    return $null
}

function Get-Pct { param([double]$Part, [double]$Whole, [int]$Digits = 1) if ($Whole -le 0) { return $null } return [math]::Round(100.0 * $Part / $Whole, $Digits) }

# ---------- Minimal XLSX reader (no Excel or external module required) ----------
function Read-XlsxSheets {
    <# Returns ordered dictionary: sheetName -> list of row arrays (strings or numbers). #>
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        function Read-Entry([string]$name) {
            $e = $zip.Entries | Where-Object { $_.FullName -eq $name } | Select-Object -First 1
            if (-not $e) { return $null }
            $sr = [System.IO.StreamReader]::new($e.Open())
            try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
        }
        $shared = [System.Collections.Generic.List[string]]::new()
        $ssXml = Read-Entry 'xl/sharedStrings.xml'
        if ($ssXml) {
            $x = [xml]$ssXml
            foreach ($si in $x.DocumentElement.ChildNodes) {
                if ($si.LocalName -ne 'si') { continue }
                $parts = foreach ($n in $si.SelectNodes('.//*[local-name()="t" and not(ancestor::*[local-name()="rPh"])]')) { $n.InnerText }
                $shared.Add((@($parts) -join ''))
            }
        }
        $wb = [xml](Read-Entry 'xl/workbook.xml')
        $rels = [xml](Read-Entry 'xl/_rels/workbook.xml.rels')
        $relMap = @{}
        foreach ($r in $rels.DocumentElement.ChildNodes) { if ($r.LocalName -eq 'Relationship') { $relMap[$r.GetAttribute('Id')] = $r.GetAttribute('Target') } }
        $result = [ordered]@{}
        foreach ($s in $wb.SelectNodes('//*[local-name()="sheet"]')) {
            $rid = $s.GetAttribute('id', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships')
            $target = $relMap[$rid]; if (-not $target) { continue }
            $target = $target.TrimStart('/'); if ($target -notlike 'xl/*') { $target = 'xl/' + $target }
            $sheetXml = Read-Entry $target; if (-not $sheetXml) { continue }
            $sx = [xml]$sheetXml
            $rows = [System.Collections.Generic.List[object]]::new()
            foreach ($row in $sx.SelectNodes('//*[local-name()="sheetData"]/*[local-name()="row"]')) {
                $vals = @{}; $max = -1; $pos = -1
                foreach ($c in $row.ChildNodes) {
                    if ($c.LocalName -ne 'c') { continue }
                    $ref = $c.GetAttribute('r')
                    if ($ref) {
                        $letters = ($ref -replace '\d', '')
                        $idx = 0; foreach ($ch in $letters.ToCharArray()) { $idx = $idx * 26 + ([int][char]$ch - 64) }; $idx--
                    }
                    else { $idx = $pos + 1 }
                    $pos = $idx
                    $t = $c.GetAttribute('t')
                    $vNode = $c.SelectSingleNode('*[local-name()="v"]')
                    $raw = if ($vNode) { $vNode.InnerText } else { $null }
                    $v = $null
                    if ($t -eq 's' -and $null -ne $raw) { $v = $shared[[int]$raw] }
                    elseif ($t -eq 'inlineStr') { $isNode = $c.SelectSingleNode('*[local-name()="is"]'); $v = if ($isNode) { $isNode.InnerText } else { '' } }
                    elseif ($t -eq 'b') { $v = ($raw -eq '1') }
                    else { $v = $raw }
                    $vals[$idx] = $v; if ($idx -gt $max) { $max = $idx }
                }
                $arr = for ($i = 0; $i -le $max; $i++) { $vals[$i] }
                $rows.Add(@($arr))
            }
            $result[[string]$s.GetAttribute('name')] = $rows
        }
        return $result
    }
    finally { $zip.Dispose() }
}

function ConvertFrom-SheetRows {
    <# Finds the header row (first row containing all key columns) and returns objects. #>
    param($SheetRows, [string[]]$HeaderKeys)
    $keys = $HeaderKeys | ForEach-Object { ConvertTo-Key $_ }
    $hdrIndex = -1
    for ($i = 0; $i -lt [math]::Min($SheetRows.Count, 60); $i++) {
        $cells = @($SheetRows[$i] | ForEach-Object { ConvertTo-Key ([string]$_) })
        $ok = $true; foreach ($k in $keys) { if ($cells -notcontains $k) { $ok = $false; break } }
        if ($ok) { $hdrIndex = $i; break }
    }
    if ($hdrIndex -lt 0) { return $null }
    $headers = @($SheetRows[$hdrIndex] | ForEach-Object { [string]$_ })
    $out = [System.Collections.Generic.List[object]]::new()
    for ($i = $hdrIndex + 1; $i -lt $SheetRows.Count; $i++) {
        $r = $SheetRows[$i]; if (-not $r -or @($r | Where-Object { "$_" -ne '' }).Count -eq 0) { continue }
        $o = [ordered]@{}
        for ($j = 0; $j -lt $headers.Count; $j++) { if ($headers[$j]) { $o[$headers[$j]] = if ($j -lt $r.Count) { $r[$j] } else { $null } } }
        $out.Add([pscustomobject]$o)
    }
    return , $out.ToArray()
}

function Get-SummaryPairs {
    <# Reads key/value pairs from a Purview summary sheet (label in column A, value in column B). #>
    param($SheetRows)
    $h = [ordered]@{}
    foreach ($r in $SheetRows) { if ($r.Count -ge 2 -and $r[0] -and $null -ne $r[1] -and "$($r[1])" -ne '') { $h[[string]$r[0]] = $r[1] } }
    return $h
}

function Get-Prop {
    <# Safe nested property access: Get-Prop $obj 'a.b.c'. Returns $null when any segment is missing. #>
    param($Object, [string]$Path)
    $cur = $Object
    foreach ($p in $Path.Split('.')) {
        if ($null -eq $cur) { return $null }
        if ($cur -is [System.Collections.IDictionary]) { if ($cur.Contains($p)) { $cur = $cur[$p] } else { return $null }; continue }
        $prop = $cur.PSObject.Properties[$p]
        if (-not $prop) { return $null }
        $cur = $prop.Value
    }
    return $cur
}

# ---------- Collector isolation ----------
# Each collector group runs in its own PowerShell process because the Microsoft Graph, SharePoint, Exchange Online,
# and Az modules ship different versions of the same authentication libraries (MSAL, System.Text.Json). Loading
# them into one process makes whichever module loads second fail. The child saves its results; the parent merges them.

function Save-CollectorResult {
    param([string]$Path)
    $payload = [ordered]@{
        Datasets = $script:Ctx.Datasets; Status = @($script:Ctx.Status); Diagnostics = @($script:Ctx.Diagnostics)
        ExtraEvidenceFolders = @($script:Ctx.ExtraEvidenceFolders)
    }
    Export-Clixml -InputObject $payload -Path $Path -Depth 12
}

function Merge-CollectorResult {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $r = Import-Clixml -LiteralPath $Path
    foreach ($k in $r.Datasets.Keys) {
        $d = $r.Datasets[$k]
        $entry = [ordered]@{}
        foreach ($p in $d.Keys) { $entry[$p] = $d[$p] }
        $entry.Rows = @($d.Rows)
        $script:Ctx.Datasets[$k] = $entry
    }
    foreach ($s in $r.Status) { $script:Ctx.Status.Add($s) }
    foreach ($x in $r.Diagnostics) { $script:Ctx.Diagnostics.Add($x) }
    foreach ($f in $r.ExtraEvidenceFolders) { if ($f) { $script:Ctx.ExtraEvidenceFolders += , $f } }
    return $true
}

function Import-ModuleSafe {
    <#
      Imports the newest installed version of a module, skipping versions listed as broken in config/modules.json.
      Returns the version imported. Throws with guidance when only broken versions are installed.
    #>
    param([string]$Name, [hashtable]$Extra = @{})
    $bad = @()
    $cfg = Join-Path (Split-Path $PSScriptRoot -Parent) 'config/modules.json'
    if (Test-Path -LiteralPath $cfg) {
        $j = Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json
        $entry = $j.KnownBad | Where-Object { $_.Name -eq $Name }
        if ($entry) { $bad = @($entry.Versions) }
    }
    $all = @(Get-Module -ListAvailable -Name $Name | Sort-Object Version -Descending)
    if (-not $all.Count) { throw "$Name is not installed. Run ./Install-Prerequisites.ps1." }
    $good = @($all | Where-Object { "$($_.Version)" -notin $bad })
    if (-not $good.Count) { throw "Only $Name $($all[0].Version) is installed, and that version is known to fail to load ($($j.KnownBad | Where-Object { $_.Name -eq $Name } | ForEach-Object { $_.Reason })). Install a working version: Install-Module $Name -RequiredVersion $(($j.KnownBad | Where-Object { $_.Name -eq $Name }).Recommended) -Scope CurrentUser" }
    $pick = $good[0]
    Import-Module -Name $pick.Path -ErrorAction Stop -WarningAction SilentlyContinue @Extra
    return "$($pick.Version)"
}

function Write-CollectionSummary {
    $rows = @($script:Ctx.Status | Where-Object { $_.Origin -eq 'Collected' })
    if (-not $rows.Count) { return }
    Write-Log '--- Collection summary ---'
    foreach ($g in ($rows | Group-Object Workstream)) {
        $ok = @($g.Group | Where-Object { $_.Status -in @('Collected', 'Empty') }).Count
        $bad = @($g.Group | Where-Object Status -eq 'Failed').Count
        $lvl = if ($bad -and -not $ok) { 'Error' } elseif ($bad) { 'Warn' } else { 'Ok' }
        Write-Log ("{0,-14} collected {1}, failed {2}, other {3}" -f $g.Name, $ok, $bad, ($g.Count - $ok - $bad)) $lvl
    }
    foreach ($d in ($script:Ctx.Diagnostics | Select-Object -First 8)) { Write-Log ("  {0} / {1}: {2}" -f $d.Area, $d.Operation, $d.Message) 'Warn' }
}
