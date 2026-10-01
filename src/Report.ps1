# Output writers: CSV exports, manifest, and the self-contained HTML dashboard.

function Export-Results {
    param([string]$TemplatePath, [string]$ToolkitVersion, [string]$Mode, [switch]$IncludeRowPreview, [hashtable]$RunParameters = @{})
    $out = $script:Ctx.OutDir
    $csv = Join-Path $out 'csv'
    $scores = Get-Scores

    Export-SafeCsv -Rows @($script:Ctx.MetricRows | Select-Object Key, Domain, DomainName, Label, Display, Value, Denominator, Source, Note) -Path (Join-Path $csv 'metrics.csv')
    Export-SafeCsv -Rows @($script:Ctx.Checks) -Path (Join-Path $csv 'checks.csv')
    Export-SafeCsv -Rows @($scores.Domains) -Path (Join-Path $csv 'domain-scores.csv')
    Export-SafeCsv -Rows @($script:Ctx.Status) -Path (Join-Path $csv 'collection-status.csv')
    Export-SafeCsv -Rows @($script:Ctx.Inventory) -Path (Join-Path $csv 'evidence-inventory.csv')
    Export-SafeCsv -Rows @($script:Ctx.Diagnostics) -Path (Join-Path $csv 'diagnostics.csv')

    $highlightKeys = 'lic.ready.licensed', 'use.active30Pct', 'use.prompts', 'chat.activeUnlicensed', 'lic.qualifiedPool', 'da.sp.brokenInheritance', 'da.eeeu.editPlus', 'pp.agents.defaultPct', 'ag.registry', 'lic.users.copilot'
    $highlights = @($highlightKeys | Where-Object { Test-Metric $_ } | Select-Object -First 8 | ForEach-Object { $m = $script:Ctx.Metrics[$_]; [ordered]@{ Key = $m.Key; Label = $m.Label; Display = $m.Display; Denominator = $m.Denominator } })

    $datasets = foreach ($s in $script:Ctx.Status) {
        $o = [ordered]@{ Dataset = $s.Dataset; Workstream = $s.Workstream; Status = $s.Status; Origin = $s.Origin; Rows = $s.Rows; Source = $s.Source; Explanation = $s.Explanation }
        if ($IncludeRowPreview -and $s.Status -in @('Collected', 'Imported')) {
            $d = $script:Ctx.Datasets[$s.Dataset]
            $o.Preview = @($d.Rows | Select-Object -First 25 | ForEach-Object {
                    $r = $_; $p = [ordered]@{}
                    $names = if ($r -is [System.Collections.IDictionary]) { $r.Keys } else { $r.PSObject.Properties.Name }
                    foreach ($n in ($names | Select-Object -First 30)) { $v = ConvertTo-SafeCell $(if ($r -is [System.Collections.IDictionary]) { $r[$n] } else { $r.$n }); if ($v.Length -gt 200) { $v = $v.Substring(0, 200) + '...' }; $p[[string]$n] = $v }
                    $p
                })
        }
        $o
    }

    $meta = [ordered]@{
        customer = $script:Ctx.CustomerName; tenantId = $script:Ctx.TenantId; cloud = $script:Ctx.Cloud
        runUtc = $script:Ctx.StartedUtc.ToString('yyyy-MM-ddTHH:mm:ssZ'); mode = $Mode; toolkitVersion = $ToolkitVersion
        rowPreview = [bool]$IncludeRowPreview
    }
    foreach ($k in $RunParameters.Keys) { $meta[$k] = $RunParameters[$k] }

    $data = [ordered]@{
        meta = $meta
        scores = $scores
        highlights = $highlights
        checks = @($script:Ctx.Checks)
        metrics = @($script:Ctx.MetricRows | Select-Object Key, Domain, DomainName, Label, Display, Denominator, Source, Note)
        datasets = @($datasets)
        inventory = @($script:Ctx.Inventory)
        diagnostics = @($script:Ctx.Diagnostics)
    }
    $json = ConvertTo-Json -InputObject $data -Depth 8 -Compress
    # Keep the JSON inert inside the <script> block.
    $json = $json.Replace('</', '<\/').Replace('<!--', '<\!--')
    $tpl = Get-Content -LiteralPath $TemplatePath -Raw -Encoding utf8
    $title = if ($script:Ctx.CustomerName) { [System.Net.WebUtility]::HtmlEncode($script:Ctx.CustomerName) + ' | Copilot Readiness Dashboard' } else { 'Copilot Readiness Dashboard' }
    $html = $tpl.Replace('<title>Copilot Readiness Dashboard</title>', "<title>$title</title>").Replace('__REPORT_DATA__', $json)
    $htmlPath = Join-Path $out 'CopilotReadinessDashboard.html'
    [System.IO.File]::WriteAllText($htmlPath, $html, [System.Text.UTF8Encoding]::new($false))

    $manifest = [ordered]@{
        toolkitVersion = $ToolkitVersion; customer = $script:Ctx.CustomerName; tenantId = $script:Ctx.TenantId; cloud = $script:Ctx.Cloud
        startedUtc = $script:Ctx.StartedUtc.ToString('o'); finishedUtc = [datetime]::UtcNow.ToString('o'); mode = $Mode
        overallScore = $scores.Overall; rating = $scores.Rating; checkCoveragePct = $scores.CoveragePct
        datasets = @($script:Ctx.Status | Select-Object Dataset, Status, Origin, Rows, File)
        files = @(Get-ChildItem -LiteralPath $out -Recurse -File | Where-Object { $_.Name -ne 'manifest.json' } | ForEach-Object { [ordered]@{ path = $_.FullName.Substring($out.Length).TrimStart('/', '\'); bytes = $_.Length } })
    }
    ConvertTo-Json -InputObject $manifest -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'manifest.json') -Encoding utf8
    return [pscustomobject]@{ Html = $htmlPath; Scores = $scores }
}
