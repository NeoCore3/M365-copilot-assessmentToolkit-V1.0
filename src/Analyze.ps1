# Analysis: turns datasets into metrics. Every metric records its value, denominator, and the dataset(s) it came from.
# A metric is only created when its source data exists; absent data produces no metric, and the related check reports NotAssessed.

$script:Domains = [ordered]@{
    LIC = @{ Name = 'Licensing and Deployment'; Weight = 4 }
    USE = @{ Name = 'Usage and Adoption'; Weight = 7 }
    CCS = @{ Name = 'Copilot Control System Configuration'; Weight = 6 }
    ID  = @{ Name = 'Identity and Access'; Weight = 10 }
    EP  = @{ Name = 'Endpoint and App Readiness'; Weight = 4 }
    DA  = @{ Name = 'Data Access and Oversharing'; Weight = 13 }
    IP  = @{ Name = 'Information Protection'; Weight = 10 }
    LC  = @{ Name = 'Data Lifecycle and Content Quality'; Weight = 6 }
    AM  = @{ Name = 'Audit, Monitoring, and AI Risk Detection'; Weight = 8 }
    AG  = @{ Name = 'Agent and Extensibility Governance'; Weight = 6 }
    PP  = @{ Name = 'Power Platform and Copilot Studio Governance'; Weight = 7 }
    DV  = @{ Name = 'Dataverse Readiness'; Weight = 4 }
    FB  = @{ Name = 'Microsoft Fabric and Copilot in Power BI'; Weight = 6 }
    DC  = @{ Name = 'Agent Catalog and Store Management'; Weight = 3 }
    GOV = @{ Name = 'AI Governance and Operating Model'; Weight = 6 }
}

function Get-Prop {
    <# Safe nested property access under StrictMode: Get-Prop $obj 'a.b.c' #>
    param($Object, [string]$Path)
    $cur = $Object
    foreach ($p in $Path.Split('.')) {
        if ($null -eq $cur) { return $null }
        if ($cur -is [System.Collections.IDictionary]) { if ($cur.Contains($p)) { $cur = $cur[$p] } else { return $null } ; continue }
        $prop = $cur.PSObject.Properties[$p]
        if (-not $prop) { return $null }
        $cur = $prop.Value
    }
    return $cur
}

function Set-Metric {
    param([string]$Key, [string]$Domain, [string]$Label, $Value, [string]$Denominator = '', [string]$Source = '', [string]$Note = '', [ValidateSet('n', 'pct', 'text', 'date')][string]$Kind = 'n')
    $display = switch ($Kind) {
        'n' { if ($null -eq $Value) { '' } elseif ([math]::Abs([double]$Value - [math]::Round([double]$Value)) -lt 1e-9) { '{0:N0}' -f [double]$Value } else { '{0:N1}' -f [double]$Value } }
        'pct' { if ($null -eq $Value) { '' } else { '{0:N1}%' -f [double]$Value } }
        'date' { if ($Value -is [datetime]) { $Value.ToString('yyyy-MM-dd') } else { [string]$Value } }
        default { [string]$Value }
    }
    $m = [pscustomobject][ordered]@{ Key = $Key; Domain = $Domain; DomainName = $script:Domains[$Domain].Name; Label = $Label; Value = $Value; Display = $display; Denominator = $Denominator; Source = $Source; Note = $Note }
    $script:Ctx.Metrics[$Key] = $m
    $script:Ctx.MetricRows.Add($m)
}

function Get-Metric { param([string]$Key) if ($script:Ctx.Metrics.Contains($Key)) { return $script:Ctx.Metrics[$Key].Value } return $null }
function Test-Metric { param([string]$Key) return $script:Ctx.Metrics.Contains($Key) }

function Get-FirstDataset {
    <# Returns @{ Id; Rows; Source } for the first dataset id that has rows. #>
    param([string[]]$Ids)
    foreach ($id in $Ids) {
        $d = Get-DatasetInfo $id
        if ($d -and $d.Status -in @('Collected', 'Imported') -and $d.RowCount -gt 0) {
            $src = if ($d.Origin -eq 'Imported') { $d.File } else { "$($d.Id) ($($d.Source))" }
            return [pscustomobject]@{ Id = $id; Rows = @($d.Rows); Source = $src; Info = $d }
        }
    }
    return $null
}

function Get-ColumnSum { param($Rows, [string]$Col) $s = 0.0; foreach ($r in $Rows) { $v = ConvertTo-Num (Get-Val $r $Col); if ($null -ne $v) { $s += $v } }; return $s }
function Get-Median { param([double[]]$Values) if (-not $Values -or $Values.Count -eq 0) { return $null } $s = @($Values | Sort-Object); $n = $s.Count; if ($n % 2) { return $s[[int][math]::Floor($n / 2)] } return ($s[$n / 2 - 1] + $s[$n / 2]) / 2 }
function Test-NamesVisible { param($Rows, [string]$Col) if (-not $Col) { return $false } return (@($Rows | Select-Object -First 50 | Where-Object { "$(Get-Val $_ $Col)" -match '@' }).Count -gt 0) }
function Get-Upn { param($Value) if ($null -eq $Value) { return '' } return ([string]$Value).Trim().ToLowerInvariant() }

$script:CopilotSkuIds = @('639dec6b-bb19-468b-871c-c5c441c4b0cb')   # Microsoft 365 Copilot (Microsoft Learn: product names and service plan identifiers for licensing)

function Invoke-Analysis {
    Write-Log 'Analyzing datasets...'
    Measure-Licensing
    Measure-Usage
    Measure-Identity
    Measure-DataAccess
    Measure-InformationProtection
    Measure-Lifecycle
    Measure-Audit
    Measure-Agents
    Measure-PowerPlatform
    Measure-Fabric
    Write-Log "Analysis produced $($script:Ctx.MetricRows.Count) metrics" 'Ok'
}

function Measure-Licensing {
    $sku = Get-FirstDataset @('Graph_SubscribedSkus')
    if ($sku) {
        $cop = @($sku.Rows | Where-Object { "$(Get-Prop $_ 'skuPartNumber')" -match 'Copilot' -or (Get-Prop $_ 'skuId') -in $script:CopilotSkuIds })
        $purchased = 0; $consumed = 0
        foreach ($s in $cop) { $purchased += [double](Get-Prop $s 'prepaidUnits.enabled'); $consumed += [double](Get-Prop $s 'consumedUnits') }
        Set-Metric 'lic.skus' 'LIC' 'Subscribed SKUs in tenant' $sku.Rows.Count -Source $sku.Source
        if ($cop.Count) {
            Set-Metric 'lic.copilot.purchased' 'LIC' 'Copilot licenses purchased (enabled units)' $purchased -Source $sku.Source -Note (($cop | ForEach-Object { Get-Prop $_ 'skuPartNumber' }) -join ', ')
            Set-Metric 'lic.copilot.consumed' 'LIC' 'Copilot licenses assigned (consumed units)' $consumed -Denominator ("{0:N0} purchased" -f $purchased) -Source $sku.Source
            Set-Metric 'lic.copilot.available' 'LIC' 'Copilot licenses unassigned' ($purchased - $consumed) -Denominator ("{0:N0} purchased" -f $purchased) -Source $sku.Source
            Set-Metric 'lic.copilot.assignedPct' 'LIC' 'Copilot license pool assigned' (Get-Pct $consumed $purchased) -Kind pct -Denominator ("{0:N0} purchased" -f $purchased) -Source $sku.Source
        }
    }
    $u = Get-FirstDataset @('Graph_Users', 'IMP_EntraUsers')
    if ($u) {
        $map = Get-HeaderMap $u.Rows
        $cType = Resolve-Column $map @('userType'); $cLic = Resolve-Column $map @('assignedLicenses')
        $members = 0; $guests = 0; $licensed = 0; $copilot = 0
        foreach ($r in $u.Rows) {
            $t = "$(Get-Val $r $cType)"; if ($t -eq 'Guest') { $guests++ } elseif ($t -eq 'Member') { $members++ }
            $al = Get-Val $r $cLic
            $txt = if ($al -is [string]) { $al } else { ConvertTo-Json -InputObject $al -Depth 5 -Compress }
            if ($txt -and $txt -match '[0-9a-f]{8}-') { $licensed++ }
            foreach ($id in $script:CopilotSkuIds) { if ($txt -match $id) { $copilot++; break } }
        }
        $n = $u.Rows.Count
        Set-Metric 'lic.users.total' 'LIC' 'Directory user objects' $n -Source $u.Source
        Set-Metric 'lic.users.members' 'LIC' 'Member users' $members -Denominator ("{0:N0} objects" -f $n) -Source $u.Source
        Set-Metric 'lic.users.guests' 'ID' 'Guest users' $guests -Denominator ("{0:N0} objects" -f $n) -Source $u.Source
        Set-Metric 'lic.users.licensed' 'LIC' 'Objects with at least one license' $licensed -Denominator ("{0:N0} objects" -f $n) -Source $u.Source
        Set-Metric 'lic.users.copilot' 'LIC' 'Users with a Microsoft 365 Copilot license (directory)' $copilot -Denominator ("{0:N0} objects" -f $n) -Source $u.Source -Note 'Matched on the Microsoft 365 Copilot SKU ID in assignedLicenses.'
    }
    $rd = Get-FirstDataset @('IMP_CopilotReadiness')
    if ($rd) {
        $map = Get-HeaderMap $rd.Rows
        $cL = Resolve-Column $map @('Has Copilot license assigned'); $cS = Resolve-Column $map @('Suggested candidate for Copilot'); $cCh = Resolve-Column $map @('Uses eligible update channel'); $cRef = Resolve-Column $map @('Report Refresh Date')
        $lic = @($rd.Rows | Where-Object { ConvertTo-Bool (Get-Val $_ $cL) })
        $unl = @($rd.Rows | Where-Object { -not (ConvertTo-Bool (Get-Val $_ $cL)) })
        $cand = @($unl | Where-Object { ConvertTo-Bool (Get-Val $_ $cS) })
        $n = $rd.Rows.Count
        $ref = ConvertTo-Date (Get-Val $rd.Rows[0] $cRef)
        Set-Metric 'lic.ready.population' 'LIC' 'Users in Copilot readiness report' $n -Source $rd.Source -Note ("Report refresh date {0}" -f $(if ($ref) { $ref.ToString('yyyy-MM-dd') } else { 'not stated' }))
        Set-Metric 'lic.ready.licensed' 'LIC' 'Users with a Copilot license (readiness report)' $lic.Count -Denominator ("{0:N0} users in report" -f $n) -Source $rd.Source
        Set-Metric 'lic.ready.candidates' 'LIC' 'Unlicensed users flagged as suggested Copilot candidates' $cand.Count -Denominator ("{0:N0} unlicensed users" -f $unl.Count) -Source $rd.Source
        if ($cCh) {
            $lc = @($lic | Where-Object { ConvertTo-Bool (Get-Val $_ $cCh) }).Count
            $uc = @($unl | Where-Object { ConvertTo-Bool (Get-Val $_ $cCh) }).Count
            Set-Metric 'ep.channel.licensedPct' 'EP' 'Licensed users on an eligible Microsoft 365 Apps update channel' (Get-Pct $lc $lic.Count) -Kind pct -Denominator ("{0:N0} of {1:N0} licensed users" -f $lc, $lic.Count) -Source $rd.Source
            Set-Metric 'ep.channel.unlicensedPct' 'EP' 'Unlicensed users on an eligible update channel' (Get-Pct $uc $unl.Count) -Kind pct -Denominator ("{0:N0} of {1:N0} unlicensed users" -f $uc, $unl.Count) -Source $rd.Source
        }
        if ($script:Ctx.Metrics.Contains('lic.users.copilot')) {
            $a = Get-Metric 'lic.users.copilot'; $b = $lic.Count
            if ($a -ne $b) { Set-Metric 'lic.reconcile.copilot' 'LIC' 'Copilot licensed users: directory versus readiness report (delta)' ($b - $a) -Denominator ("directory {0:N0}; readiness {1:N0}" -f $a, $b) -Source "$($rd.Source) | directory users" -Note 'Different exports taken on different dates are different populations; both values are reported.' }
        }
    }
}

function Measure-Usage {
    $us = Get-FirstDataset @('IMP_CopilotUsage', 'Graph_CopilotUsage')
    if ($us) {
        $rows = $us.Rows; $map = Get-HeaderMap $rows
        $cRef = Resolve-Column $map @('Report Refresh Date'); $cLast = Resolve-Column $map @('Last Activity Date'); $cP = Resolve-Column $map @('Prompts submitted for All Apps')
        $cUpn = Resolve-Column $map @('User Principal Name')
        $ref = ConvertTo-Date (Get-Val $rows[0] $cRef)
        if (-not $ref) { $ref = ($rows | ForEach-Object { ConvertTo-Date (Get-Val $_ $cLast) } | Where-Object { $_ } | Measure-Object -Maximum).Maximum }
        $n = $rows.Count
        $den = "{0:N0} users in export" -f $n
        Set-Metric 'use.users' 'USE' 'Users in Copilot usage report' $n -Source $us.Source -Note ("Report refresh date {0}" -f $(if ($ref) { $ref.ToString('yyyy-MM-dd') } else { 'not stated' }))
        if ($cP) {
            $pv = [double[]]@($rows | ForEach-Object { $v = ConvertTo-Num (Get-Val $_ $cP); if ($null -eq $v) { 0 } else { $v } })
            $total = ($pv | Measure-Object -Sum).Sum
            Set-Metric 'use.prompts' 'USE' 'Prompts submitted (all apps, report period)' $total -Denominator $den -Source $us.Source
            Set-Metric 'use.prompts.median' 'USE' 'Median prompts per user' (Get-Median $pv) -Denominator $den -Source $us.Source
            $sorted = @($pv | Sort-Object -Descending)
            if ($total -gt 0) {
                $k10 = [math]::Max(1, [int][math]::Floor($n * 0.1)); $k20 = [math]::Max(1, [int][math]::Floor($n * 0.2))
                Set-Metric 'use.prompts.top10Share' 'USE' 'Share of prompts from the top 10% of users' (Get-Pct (($sorted | Select-Object -First $k10 | Measure-Object -Sum).Sum) $total) -Kind pct -Denominator ("{0:N0} prompts" -f $total) -Source $us.Source
                Set-Metric 'use.prompts.top20Share' 'USE' 'Share of prompts from the top 20% of users' (Get-Pct (($sorted | Select-Object -First $k20 | Measure-Object -Sum).Sum) $total) -Kind pct -Denominator ("{0:N0} prompts" -f $total) -Source $us.Source
            }
        }
        if ($ref -and $cLast) {
            $a7 = 0; $a30 = 0; $none = 0
            foreach ($r in $rows) { $d = ConvertTo-Date (Get-Val $r $cLast); if (-not $d) { $none++; continue }; $age = ($ref - $d).TotalDays; if ($age -le 7) { $a7++ }; if ($age -le 30) { $a30++ } }
            Set-Metric 'use.active7' 'USE' 'Users active within 7 days of report date' $a7 -Denominator $den -Source $us.Source
            Set-Metric 'use.active30' 'USE' 'Users active within 30 days of report date' $a30 -Denominator $den -Source $us.Source
            Set-Metric 'use.active30Pct' 'USE' 'Users active within 30 days (percent)' (Get-Pct $a30 $n) -Kind pct -Denominator $den -Source $us.Source
            Set-Metric 'use.noActivity' 'USE' 'Users with no activity in the report period' $none -Denominator $den -Source $us.Source
            # Per-app activity
            # Portal export: "Last activity date of Word Copilot (UTC)"; Graph CSV: "Word Copilot Last Activity Date"
            $appCols = @($map.Values | Where-Object { $_ -match '^Last activity date of (.+?) \(UTC\)$' -or ($_ -match '^(.+?) Last Activity Date$' -and $_ -ne $cLast) })
            foreach ($c in $appCols) {
                $app = if ($c -match '^Last activity date of (.+?) \(UTC\)$') { $Matches[1] } else { ([regex]::Match($c, '^(.+?) Last Activity Date$')).Groups[1].Value }
                $any = 0; $r30 = 0
                foreach ($r in $rows) { $d = ConvertTo-Date (Get-Val $r $c); if ($d) { $any++; if (($ref - $d).TotalDays -le 30) { $r30++ } } }
                $key = 'use.app.' + (ConvertTo-Key $app)
                Set-Metric $key 'USE' "Users active in $app within 30 days" $r30 -Denominator ("{0:N0} active in period; {1}" -f $any, $den) -Source $us.Source
            }
            # Idle licensed users (requires readiness report for current license state)
            $rd = Get-FirstDataset @('IMP_CopilotReadiness')
            if ($rd -and $cUpn -and (Test-NamesVisible $rows $cUpn)) {
                $rm = Get-HeaderMap $rd.Rows; $rU = Resolve-Column $rm @('User Principal Name'); $rL = Resolve-Column $rm @('Has Copilot license assigned')
                $lastBy = @{}; foreach ($r in $rows) { $lastBy[(Get-Upn (Get-Val $r $cUpn))] = ConvertTo-Date (Get-Val $r $cLast) }
                $lic = @($rd.Rows | Where-Object { ConvertTo-Bool (Get-Val $_ $rL) })
                $idle = 0; $never = 0
                foreach ($r in $lic) {
                    $k = Get-Upn (Get-Val $r $rU)
                    $d = if ($lastBy.ContainsKey($k)) { $lastBy[$k] } else { $null }
                    if (-not $d) { $idle++; $never++ } elseif (($ref - $d).TotalDays -gt 30) { $idle++ }
                }
                $concealed = (@($lic | Select-Object -First 50 | Where-Object { (Get-Val $_ $rU) -match '@' }).Count -eq 0)
                if (-not $concealed) {
                    Set-Metric 'lic.idle' 'LIC' 'Licensed users idle more than 30 days or never active' $idle -Denominator ("{0:N0} licensed users (readiness report)" -f $lic.Count) -Source "$($us.Source) | $($rd.Source)" -Note "$never with no recorded activity. Joined on user principal name."
                    Set-Metric 'lic.idlePct' 'LIC' 'Licensed users idle (percent)' (Get-Pct $idle $lic.Count) -Kind pct -Denominator ("{0:N0} licensed users" -f $lic.Count) -Source "$($us.Source) | $($rd.Source)"
                }
            }
        }
    }
    $ch = Get-FirstDataset @('IMP_CopilotChat')
    if ($ch) {
        $rows = $ch.Rows; $map = Get-HeaderMap $rows
        $cP = Resolve-Column $map @('Prompts submitted'); $cD = Resolve-Column $map @('Active usage days'); $cU = Resolve-Column $map @('User principal name')
        $act = @($rows | Where-Object { (ConvertTo-Num (Get-Val $_ $cP)) -gt 0 })
        $den = "{0:N0} users listed" -f $rows.Count
        Set-Metric 'chat.listed' 'USE' 'Users listed in Copilot Chat report' $rows.Count -Source $ch.Source
        Set-Metric 'chat.active' 'USE' 'Copilot Chat users who submitted prompts in the report period' $act.Count -Denominator $den -Source $ch.Source
        Set-Metric 'chat.prompts' 'USE' 'Copilot Chat prompts in the report period' (Get-ColumnSum $act $cP) -Denominator ("{0:N0} active users" -f $act.Count) -Source $ch.Source
        $a10 = @($act | Where-Object { (ConvertTo-Num (Get-Val $_ $cD)) -ge 10 })
        Set-Metric 'chat.active10' 'USE' 'Copilot Chat users active on 10 or more days' $a10.Count -Denominator ("{0:N0} active users" -f $act.Count) -Source $ch.Source
        $rd = Get-FirstDataset @('IMP_CopilotReadiness')
        if ($rd -and $cU -and (Test-NamesVisible $rows $cU)) {
            $rm = Get-HeaderMap $rd.Rows; $rU = Resolve-Column $rm @('User Principal Name'); $rL = Resolve-Column $rm @('Has Copilot license assigned'); $rS = Resolve-Column $rm @('Suggested candidate for Copilot'); $rC = Resolve-Column $rm @('Uses eligible update channel')
            $ready = @{}; foreach ($r in $rd.Rows) { $ready[(Get-Upn (Get-Val $r $rU))] = $r }
            $unlAct = 0; $qual = 0
            foreach ($r in $act) {
                $k = Get-Upn (Get-Val $r $cU); $x = if ($ready.ContainsKey($k)) { $ready[$k] } else { $null }
                if ($x -and (ConvertTo-Bool (Get-Val $x $rL))) { continue }
                $unlAct++
                if ($x -and (ConvertTo-Num (Get-Val $r $cD)) -ge 10 -and (ConvertTo-Bool (Get-Val $x $rS)) -and (ConvertTo-Bool (Get-Val $x $rC))) { $qual++ }
            }
            Set-Metric 'chat.activeUnlicensed' 'USE' 'Active Copilot Chat users without a Copilot license' $unlAct -Denominator ("{0:N0} active Chat users" -f $act.Count) -Source "$($ch.Source) | $($rd.Source)" -Note 'License state from the readiness report; users not found in it are counted as unlicensed.'
            Set-Metric 'lic.qualifiedPool' 'LIC' 'Qualified expansion candidates (unlicensed, Chat active 10+ days, suggested candidate, eligible channel)' $qual -Denominator ("{0:N0} unlicensed active Chat users" -f $unlAct) -Source "$($ch.Source) | $($rd.Source)" -Note 'All three signals required. Thresholds are SHI conventions; adjust to the engagement.'
        }
    }
    $vv = Get-FirstDataset @('IMP_VivaCopilot')
    if ($vv) {
        $rows = $vv.Rows; $map = Get-HeaderMap $rows
        $cP = Resolve-Column $map @('PersonId'); $cW = Resolve-Column $map @('MetricDate'); $cE = Resolve-Column $map @('Copilot Enabled User'); $cA = Resolve-Column $map @('Total Copilot active days'); $cU = Resolve-Column $map @('Days of active Copilot Chat usage (without Copilot license)')
        $weeks = @($rows | ForEach-Object { Get-Val $_ $cW } | Select-Object -Unique | Sort-Object { ConvertTo-Date $_ })
        if ($weeks.Count -and $cE -and $cA) {
            $lw = $weeks[-1]; $last12 = @($weeks | Select-Object -Last 12)
            $activeWeeks = @{}; $lic = [System.Collections.Generic.List[object]]::new(); $licAct = 0; $unlAct = 0
            $set12 = [System.Collections.Generic.HashSet[string]]::new([string[]]$last12)
            foreach ($r in $rows) {
                $w = [string](Get-Val $r $cW)
                $a = ConvertTo-Num (Get-Val $r $cA)
                if ($set12.Contains($w) -and $a -gt 0) { $p = [string](Get-Val $r $cP); $activeWeeks[$p] = 1 + $(if ($activeWeeks.ContainsKey($p)) { $activeWeeks[$p] } else { 0 }) }
                if ($w -eq $lw) {
                    if ((ConvertTo-Num (Get-Val $r $cE)) -eq 1) { $lic.Add($r); if ($a -gt 0) { $licAct++ } }
                    if ($cU -and (ConvertTo-Num (Get-Val $r $cU)) -gt 0) { $unlAct++ }
                }
            }
            $habit = 0; foreach ($r in $lic) { $p = [string](Get-Val $r $cP); if ($activeWeeks.ContainsKey($p) -and $activeWeeks[$p] -ge 9) { $habit++ } }
            Set-Metric 'viva.weeks' 'USE' 'Weeks in Viva Insights export' $weeks.Count -Source $vv.Source -Note ("Latest week starting {0}" -f $lw)
            Set-Metric 'viva.licensed' 'USE' 'Copilot-enabled persons in latest week (Viva Insights)' $lic.Count -Source $vv.Source -Note "Week starting $lw"
            Set-Metric 'viva.activeRate' 'USE' 'Copilot-enabled persons active in latest week' (Get-Pct $licAct $lic.Count) -Kind pct -Denominator ("{0:N0} of {1:N0} enabled persons" -f $licAct, $lic.Count) -Source $vv.Source
            Set-Metric 'viva.habitual' 'USE' 'Enabled persons active in 9 or more of the last 12 weeks' (Get-Pct $habit $lic.Count) -Kind pct -Denominator ("{0:N0} of {1:N0} enabled persons" -f $habit, $lic.Count) -Source $vv.Source
            if ($cU) { Set-Metric 'viva.unlicensedChat' 'USE' 'Persons using Copilot Chat without a license in latest week' $unlAct -Source $vv.Source }
        }
    }
    $se = Get-FirstDataset @('IMP_CopilotSearch')
    if ($se) {
        $map = Get-HeaderMap $se.Rows; $c = Resolve-Column $map @('Total searches')
        Set-Metric 'use.search.users' 'USE' 'Copilot Search users' $se.Rows.Count -Source $se.Source
        Set-Metric 'use.search.total' 'USE' 'Copilot Search searches' (Get-ColumnSum $se.Rows $c) -Denominator ("{0:N0} users" -f $se.Rows.Count) -Source $se.Source
    }
    $tr = Get-FirstDataset @('Graph_CopilotUserCountSummary')
    if ($tr) { Set-Metric 'use.api.summary' 'USE' 'Copilot user count summary rows (API)' $tr.Rows.Count -Source $tr.Source }
}

function Measure-Identity {
    $ca = Get-FirstDataset @('Graph_ConditionalAccess')
    $caInfo = Get-DatasetInfo 'Graph_ConditionalAccess'
    if ($ca -or ($caInfo -and $caInfo.Status -eq 'Empty')) {
        $rows = if ($ca) { $ca.Rows } else { @() }
        $src = if ($ca) { $ca.Source } else { 'Graph_ConditionalAccess' }
        $enabled = @($rows | Where-Object { (Get-Prop $_ 'state') -eq 'enabled' })
        $report = @($rows | Where-Object { (Get-Prop $_ 'state') -eq 'enabledForReportingButNotEnforced' })
        $mfaAll = @($enabled | Where-Object { @(Get-Prop $_ 'conditions.users.includeUsers') -contains 'All' -and (@(Get-Prop $_ 'grantControls.builtInControls') -contains 'mfa' -or (Get-Prop $_ 'grantControls.authenticationStrength')) })
        $legacy = @($enabled | Where-Object { $apps = @(Get-Prop $_ 'conditions.clientAppTypes'); ($apps -contains 'exchangeActiveSync' -or $apps -contains 'other') -and @(Get-Prop $_ 'grantControls.builtInControls') -contains 'block' })
        Set-Metric 'id.ca.total' 'ID' 'Conditional Access policies' $rows.Count -Source $src
        Set-Metric 'id.ca.enabled' 'ID' 'Conditional Access policies enforced' $enabled.Count -Denominator ("{0:N0} policies; {1:N0} report-only" -f $rows.Count, $report.Count) -Source $src
        Set-Metric 'id.ca.mfaAll' 'ID' 'Enforced policies requiring MFA or authentication strength for all users' $mfaAll.Count -Source $src
        Set-Metric 'id.ca.legacyBlock' 'ID' 'Enforced policies blocking legacy authentication' $legacy.Count -Source $src
    }
    $sd = Get-FirstDataset @('Graph_SecurityDefaults')
    if ($sd) { Set-Metric 'id.securityDefaults' 'ID' 'Security defaults enabled' ([string](Get-Prop $sd.Rows[0] 'isEnabled')) -Kind text -Source $sd.Source }
    $ra = Get-FirstDataset @('Graph_RoleAssignments'); $rdf = Get-FirstDataset @('Graph_RoleDefinitions')
    if ($ra -and $rdf) {
        $names = @{}; foreach ($d in $rdf.Rows) { $names[[string](Get-Prop $d 'id')] = [string](Get-Prop $d 'displayName'); $names[[string](Get-Prop $d 'templateId')] = [string](Get-Prop $d 'displayName') }
        $byRole = @{}
        foreach ($a in $ra.Rows) { $n = $names[[string](Get-Prop $a 'roleDefinitionId')]; if ($n) { $byRole[$n] = 1 + $(if ($byRole.ContainsKey($n)) { $byRole[$n] } else { 0 }) } }
        $ga = if ($byRole.ContainsKey('Global Administrator')) { $byRole['Global Administrator'] } else { 0 }
        $ai = if ($byRole.ContainsKey('AI Administrator')) { $byRole['AI Administrator'] } else { 0 }
        Set-Metric 'id.roles.globalAdmins' 'ID' 'Active Global Administrator assignments' $ga -Source "$($ra.Source) | $($rdf.Source)" -Note 'Active assignments only; PIM-eligible assignments are not included.'
        Set-Metric 'ccs.aiAdmins' 'CCS' 'Active AI Administrator assignments' $ai -Source "$($ra.Source) | $($rdf.Source)" -Note 'Active assignments only; PIM-eligible assignments are not included.'
    }
    $ss = Get-FirstDataset @('Graph_SecureScore')
    if ($ss) {
        $cur = ConvertTo-Num (Get-Prop $ss.Rows[0] 'currentScore'); $max = ConvertTo-Num (Get-Prop $ss.Rows[0] 'maxScore')
        if ($max) { Set-Metric 'id.secureScore' 'ID' 'Microsoft Secure Score' (Get-Pct $cur $max) -Kind pct -Denominator ("{0:N1} of {1:N1} points" -f $cur, $max) -Source $ss.Source }
    }
}

function Measure-DataAccess {
    $sp = Get-FirstDataset @('IMP_DagSharePoint')
    if ($sp) {
        $rows = $sp.Rows; $map = Get-HeaderMap $rows
        $cU = Resolve-Column $map @('Number of users having access'); $cI = Resolve-Column $map @('Items with unique permissions count'); $cA = Resolve-Column $map @('Anyone link count')
        $cE = Resolve-Column $map @('EEEU permission count'); $cEv = Resolve-Column $map @('Everyone permission count'); $cPriv = Resolve-Column $map @('Site privacy'); $cF = Resolve-Column $map @('File count'); $cL = Resolve-Column $map @('Site sensitivity')
        $n = $rows.Count; $den = "{0:N0} sites in report" -f $n
        $bi = @($rows | Where-Object { (ConvertTo-Num (Get-Val $_ $cI)) -gt 0 })
        Set-Metric 'da.sp.sites' 'DA' 'Sites in SharePoint permissions report' $n -Source $sp.Source
        Set-Metric 'da.sp.brokenInheritance' 'DA' 'Sites with uniquely permissioned items' $bi.Count -Denominator $den -Source $sp.Source -Note ("{0:N0} items with unique permissions" -f (Get-ColumnSum $bi $cI))
        Set-Metric 'da.sp.brokenInheritancePct' 'DA' 'Sites with uniquely permissioned items (percent)' (Get-Pct $bi.Count $n) -Kind pct -Denominator $den -Source $sp.Source
        $wide = @($rows | Where-Object { (ConvertTo-Num (Get-Val $_ $cU)) -ge 1000 })
        $widePriv = @($wide | Where-Object { "$(Get-Val $_ $cPriv)" -eq 'Private' })
        $maxU = ($rows | ForEach-Object { ConvertTo-Num (Get-Val $_ $cU) } | Measure-Object -Maximum).Maximum
        Set-Metric 'da.sp.wide1000' 'DA' 'Sites reachable by 1,000 or more users' $wide.Count -Denominator $den -Source $sp.Source -Note ("{0:N0} private; {1:N0} files on these sites; largest reach {2:N0} users" -f $widePriv.Count, (Get-ColumnSum $wide $cF), $maxU)
        Set-Metric 'da.sp.wide1000Private' 'DA' 'Private sites reachable by 1,000 or more users' $widePriv.Count -Denominator $den -Source $sp.Source
        if ($cA) { $al = @($rows | Where-Object { (ConvertTo-Num (Get-Val $_ $cA)) -gt 0 }); Set-Metric 'da.sp.anyoneLinks' 'DA' 'Anyone links on SharePoint sites' (Get-ColumnSum $rows $cA) -Denominator ("{0:N0} sites with at least one" -f $al.Count) -Source $sp.Source }
        if ($cE) { $es = @($rows | Where-Object { (ConvertTo-Num (Get-Val $_ $cE)) -gt 0 }); Set-Metric 'da.sp.eeeuSites' 'DA' 'Sites with Everyone except external users permissions' $es.Count -Denominator $den -Source $sp.Source -Note ("{0:N0} EEEU permissions" -f (Get-ColumnSum $rows $cE)) }
        if ($cEv) { $vs = @($rows | Where-Object { (ConvertTo-Num (Get-Val $_ $cEv)) -gt 0 }); Set-Metric 'da.sp.everyoneSites' 'DA' 'Sites with Everyone permissions' $vs.Count -Denominator $den -Source $sp.Source }
        if ($cL) { $lab = @($rows | Where-Object { "$(Get-Val $_ $cL)".Trim() -ne '' }); Set-Metric 'ip.sitesLabeled' 'IP' 'Sites with a sensitivity label' (Get-Pct $lab.Count $n) -Kind pct -Denominator ("{0:N0} of {1:N0} sites" -f $lab.Count, $n) -Source $sp.Source }
    }
    $od = Get-FirstDataset @('IMP_DagOneDrive')
    if ($od) {
        $rows = $od.Rows; $map = Get-HeaderMap $rows
        $cU = Resolve-Column $map @('Number of users having access'); $cI = Resolve-Column $map @('Items with unique permissions count'); $cA = Resolve-Column $map @('Anyone link count')
        $n = $rows.Count; $den = "{0:N0} OneDrive accounts" -f $n
        $w100 = @($rows | Where-Object { (ConvertTo-Num (Get-Val $_ $cU)) -ge 100 }).Count
        $w1000 = @($rows | Where-Object { (ConvertTo-Num (Get-Val $_ $cU)) -ge 1000 }).Count
        Set-Metric 'da.od.accounts' 'DA' 'OneDrive accounts in permissions report' $n -Source $od.Source
        Set-Metric 'da.od.wide100' 'DA' 'OneDrive accounts reachable by 100 or more users' $w100 -Denominator $den -Source $od.Source -Note ("{0:N0} reachable by 1,000 or more" -f $w1000)
        Set-Metric 'da.od.wide100Pct' 'DA' 'OneDrive accounts reachable by 100 or more users (percent)' (Get-Pct $w100 $n) -Kind pct -Denominator $den -Source $od.Source
        $bi = @($rows | Where-Object { (ConvertTo-Num (Get-Val $_ $cI)) -gt 0 }).Count
        Set-Metric 'da.od.brokenInheritance' 'DA' 'OneDrive accounts with uniquely permissioned items' $bi -Denominator $den -Source $od.Source
        if ($cA) { $al = @($rows | Where-Object { (ConvertTo-Num (Get-Val $_ $cA)) -gt 0 }).Count; Set-Metric 'da.od.anyoneLinks' 'DA' 'Anyone links in OneDrive' (Get-ColumnSum $rows $cA) -Denominator ("{0:N0} accounts with at least one" -f $al) -Source $od.Source }
    }
    $ee = Get-FirstDataset @('IMP_DagEEEUItems')
    if ($ee) {
        $rows = $ee.Rows; $map = Get-HeaderMap $rows
        $cR = Resolve-Column $map @('Role definition'); $cS = Resolve-Column $map @('Site ID')
        $edit = @($rows | Where-Object { "$(Get-Val $_ $cR)" -match 'Edit|Contribut|Full Control|Design|Owner|Write|Creator' })
        $fc = @($rows | Where-Object { "$(Get-Val $_ $cR)" -match 'Full Control' })
        $sites = @($rows | ForEach-Object { Get-Val $_ $cS } | Select-Object -Unique).Count
        Set-Metric 'da.eeeu.grants' 'DA' 'Item-level Everyone except external users grants' $rows.Count -Denominator ("{0:N0} site collections" -f $sites) -Source $ee.Source
        Set-Metric 'da.eeeu.editPlus' 'DA' 'EEEU grants with Edit or higher' $edit.Count -Denominator ("{0:N0} grants; {1:N0} Full Control" -f $rows.Count, $fc.Count) -Source $ee.Source
    }
    $ev = Get-FirstDataset @('IMP_DagEveryoneItems')
    if ($ev) { Set-Metric 'da.everyone.grants' 'DA' 'Item-level Everyone grants' $ev.Rows.Count -Source $ev.Source }
    $t = Get-FirstDataset @('SPO_Tenant')
    if ($t) {
        $r = $t.Rows[0]
        foreach ($p in 'SharingCapability', 'OneDriveSharingCapability', 'DefaultSharingLinkType', 'DefaultLinkPermission', 'RequireAnonymousLinksExpireInDays', 'ExternalUserExpirationRequired', 'ExternalUserExpireInDays') {
            $v = Get-Prop $r $p; if ($null -ne $v) { Set-Metric ("da.tenant." + $p) 'DA' "SharePoint tenant setting: $p" ([string]$v) -Kind text -Source $t.Source }
        }
    }
    $gs = Get-FirstDataset @('Graph_SharePointSettings')
    if ($gs -and -not (Test-Metric 'da.tenant.SharingCapability')) {
        $v = Get-Prop $gs.Rows[0] 'sharingCapability'; if ($null -ne $v) { Set-Metric 'da.tenant.SharingCapability' 'DA' 'SharePoint tenant setting: SharingCapability' ([string]$v) -Kind text -Source $gs.Source }
    }
}

function Measure-InformationProtection {
    $lab = Get-FirstDataset @('PV_SensitivityLabels'); $labInfo = Get-DatasetInfo 'PV_SensitivityLabels'
    if ($lab) { Set-Metric 'ip.labels' 'IP' 'Sensitivity labels defined' $lab.Rows.Count -Source $lab.Source }
    elseif ($labInfo -and $labInfo.Status -eq 'Empty') { Set-Metric 'ip.labels' 'IP' 'Sensitivity labels defined' 0 -Source 'Get-Label' }
    $lp = Get-FirstDataset @('PV_LabelPolicies'); if ($lp) { Set-Metric 'ip.labelPolicies' 'IP' 'Label publishing policies' $lp.Rows.Count -Source $lp.Source }
    $dlpInfo = Get-DatasetInfo 'PV_DlpPolicies'; $dlp = Get-FirstDataset @('PV_DlpPolicies')
    if ($dlp -or ($dlpInfo -and $dlpInfo.Status -eq 'Empty')) {
        $rows = if ($dlp) { $dlp.Rows } else { @() }
        $enf = @($rows | Where-Object { "$(Get-Prop $_ 'Mode')" -eq 'Enable' })
        $cop = @($rows | Where-Object { (ConvertTo-Json -InputObject $_ -Depth 4 -Compress) -match 'Copilot' })
        Set-Metric 'ip.dlp.total' 'IP' 'DLP policies' $rows.Count -Source 'Get-DlpCompliancePolicy'
        Set-Metric 'ip.dlp.enforced' 'IP' 'DLP policies in enforcement mode (Mode = Enable)' $enf.Count -Denominator ("{0:N0} policies" -f $rows.Count) -Source 'Get-DlpCompliancePolicy'
        Set-Metric 'ip.dlp.copilot' 'IP' 'DLP policies whose configuration references Copilot' $cop.Count -Denominator ("{0:N0} policies" -f $rows.Count) -Source 'Get-DlpCompliancePolicy' -Note 'Text match on the policy object; confirm the Microsoft 365 Copilot location in the Purview portal.'
        $copEnf = @($cop | Where-Object { "$(Get-Prop $_ 'Mode')" -eq 'Enable' })
        Set-Metric 'ip.dlp.copilotEnforced' 'IP' 'Copilot-related DLP policies in enforcement mode' $copEnf.Count -Denominator ("{0:N0} Copilot-related policies" -f $cop.Count) -Source 'Get-DlpCompliancePolicy'
    }
    $al = Get-FirstDataset @('PV_AutoLabelPolicies'); $alInfo = Get-DatasetInfo 'PV_AutoLabelPolicies'
    if ($al -or ($alInfo -and $alInfo.Status -eq 'Empty')) {
        $rows = if ($al) { $al.Rows } else { @() }
        $enf = @($rows | Where-Object { "$(Get-Prop $_ 'Mode')" -eq 'Enable' })
        Set-Metric 'ip.autolabel.total' 'IP' 'Service-side auto-labeling policies' $rows.Count -Source 'Get-AutoSensitivityLabelPolicy'
        Set-Metric 'ip.autolabel.enforced' 'IP' 'Auto-labeling policies in enforcement mode' $enf.Count -Denominator ("{0:N0} policies" -f $rows.Count) -Source 'Get-AutoSensitivityLabelPolicy'
    }
    $dr = Get-FirstDataset @('IMP_DspmDataRisk')
    if ($dr) {
        $map = Get-HeaderMap $dr.Rows; $cS = Resolve-Column $map @('Total sensitive items'); $cT = Resolve-Column $map @('Total items'); $cL = Resolve-Column $map @('Sensitivity label')
        $unl = @($dr.Rows | Where-Object { "$(Get-Val $_ $cL)" -in @('', 'None') }).Count
        Set-Metric 'ip.dra.sources' 'IP' 'Data sources in DSPM data risk assessment' $dr.Rows.Count -Source $dr.Source -Note ("{0:N0} without a sensitivity label" -f $unl)
        Set-Metric 'ip.dra.sensitiveItems' 'IP' 'Sensitive items in data risk assessment' (Get-ColumnSum $dr.Rows $cS) -Denominator ("{0:N0} items assessed" -f (Get-ColumnSum $dr.Rows $cT)) -Source $dr.Source
    }
    $ap = Get-FirstDataset @('IMP_DspmApps')
    if ($ap) {
        $map = Get-HeaderMap $ap.Rows; $cD = Resolve-Column $map @('Data protection')
        $prot = @($ap.Rows | Where-Object { "$(Get-Val $_ $cD)" -match '^[1-9]' }).Count
        Set-Metric 'gov.ai.appsProtected' 'GOV' 'AI apps with at least one data protection policy (DSPM)' $prot -Denominator ("{0:N0} AI apps" -f $ap.Rows.Count) -Source $ap.Source
    }
}

function Measure-Lifecycle {
    $as = Get-FirstDataset @('IMP_ActiveSites')
    if ($as) {
        $rows = $as.Rows; $map = Get-HeaderMap $rows
        $cL = Resolve-Column $map @('Last activity (UTC)'); $cF = Resolve-Column $map @('Files'); $cG = Resolve-Column $map @('Storage used (GB)'); $cS = Resolve-Column $map @('Sensitivity')
        $ref = $as.Info['FileDate']
        $refNote = 'export date from file name'
        if (-not $ref -or $ref -isnot [datetime]) { $ref = ($rows | ForEach-Object { ConvertTo-Date (Get-Val $_ $cL) } | Where-Object { $_ } | Measure-Object -Maximum).Maximum; $refNote = 'latest activity date in export' }
        $stale = [System.Collections.Generic.List[object]]::new(); $noDate = 0
        foreach ($r in $rows) {
            if ((ConvertTo-Num (Get-Val $r $cF)) -le 0) { continue }
            $d = ConvertTo-Date (Get-Val $r $cL)
            if (-not $d) { $noDate++ } elseif (($ref - $d).TotalDays -gt 180) { $stale.Add($r) }
        }
        $n = $rows.Count
        Set-Metric 'lc.sites' 'LC' 'Sites in Active sites export' $n -Source $as.Source -Note ("Reference date {0} ({1})" -f $ref.ToString('yyyy-MM-dd'), $refNote)
        Set-Metric 'lc.inactive180' 'LC' 'Sites inactive more than 180 days that still hold files' $stale.Count -Denominator ("{0:N0} sites" -f $n) -Source $as.Source -Note ("{0:N0} GB; a further {1:N0} sites with files have no recorded activity date" -f (Get-ColumnSum $stale $cG), $noDate)
        Set-Metric 'lc.inactive180Pct' 'LC' 'Inactive sites holding files (percent)' (Get-Pct $stale.Count $n) -Kind pct -Denominator ("{0:N0} sites" -f $n) -Source $as.Source
        if ($cS) {
            $ul = @($rows | Where-Object { "$(Get-Val $_ $cS)".Trim() -eq '' })
            $tot = Get-ColumnSum $rows $cG; $ug = Get-ColumnSum $ul $cG
            Set-Metric 'lc.unlabeledStoragePct' 'LC' 'Storage on sites without a sensitivity label' (Get-Pct $ug $tot) -Kind pct -Denominator ("{0:N0} of {1:N0} GB; {2:N0} sites" -f $ug, $tot, $ul.Count) -Source $as.Source
        }
    }
    $rp = Get-FirstDataset @('PV_RetentionPolicies'); $rpI = Get-DatasetInfo 'PV_RetentionPolicies'
    if ($rp) { Set-Metric 'lc.retentionPolicies' 'LC' 'Retention policies' $rp.Rows.Count -Source $rp.Source }
    elseif ($rpI -and $rpI.Status -eq 'Empty') { Set-Metric 'lc.retentionPolicies' 'LC' 'Retention policies' 0 -Source 'Get-RetentionCompliancePolicy' }
    $rl = Get-FirstDataset @('PV_RetentionLabels'); if ($rl) { Set-Metric 'lc.retentionLabels' 'LC' 'Retention labels' $rl.Rows.Count -Source $rl.Source }
    $sites = Get-FirstDataset @('SPO_Sites')
    if ($sites -and -not (Test-Metric 'lc.sites')) {
        $map = Get-HeaderMap $sites.Rows; $cL = Resolve-Column $map @('LastContentModifiedDate')
        $now = [datetime]::UtcNow
        $old = @($sites.Rows | Where-Object { $d = ConvertTo-Date (Get-Val $_ $cL); $d -and ($now - $d).TotalDays -gt 180 }).Count
        Set-Metric 'lc.sites' 'LC' 'Sites in tenant inventory' $sites.Rows.Count -Source $sites.Source
        Set-Metric 'lc.inactive180Pct' 'LC' 'Sites with no content change in 180 days (percent)' (Get-Pct $old $sites.Rows.Count) -Kind pct -Denominator ("{0:N0} of {1:N0} sites" -f $old, $sites.Rows.Count) -Source $sites.Source
    }
}

function Measure-Audit {
    $ac = Get-FirstDataset @('EXO_AuditConfig')
    if ($ac) { Set-Metric 'am.ual' 'AM' 'Unified audit log ingestion enabled' ([string](Get-Prop $ac.Rows[0] 'UnifiedAuditLogIngestionEnabled')) -Kind text -Source $ac.Source }
    $cs = Get-FirstDataset @('EXO_CopilotAuditSample'); $csI = Get-DatasetInfo 'EXO_CopilotAuditSample'
    if ($cs) { Set-Metric 'am.copilotAudit' 'AM' 'CopilotInteraction audit records in sample window' $cs.Rows.Count -Source $cs.Source -Note 'Capped at 5,000; a sample, not a total.' }
    elseif ($csI -and $csI.Status -eq 'Empty') { Set-Metric 'am.copilotAudit' 'AM' 'CopilotInteraction audit records in sample window' 0 -Source 'Search-UnifiedAuditLog' }
    $ai = Get-FirstDataset @('IMP_DspmAiActivity')
    if ($ai) {
        $map = Get-HeaderMap $ai.Rows; $cT = Resolve-Column $map @('Timestamp (UTC)'); $cS = Resolve-Column $map @('Sensitive info type count')
        $ds = @($ai.Rows | ForEach-Object { ConvertTo-Date (Get-Val $_ $cT) } | Where-Object { $_ } | Sort-Object)
        $span = if ($ds.Count -gt 1) { ($ds[-1] - $ds[0]).TotalHours } else { 0 }
        $sens = if ($cS) { @($ai.Rows | Where-Object { (ConvertTo-Num (Get-Val $_ $cS)) -gt 0 }).Count } else { 0 }
        $trunc = [bool]$ai.Info['Truncated']
        Set-Metric 'am.dspm.aiActivity' 'AM' 'AI interactions in DSPM activity export' $ai.Rows.Count -Source $ai.Source -Note ("Spans {0:N1} hours{1}" -f $span, $(if ($trunc) { '; export capped by the portal, so this is a sample' } else { '' }))
        Set-Metric 'am.dspm.sensitive' 'AM' 'AI interactions with sensitive information types (sample)' $sens -Denominator ("{0:N0} interactions in export" -f $ai.Rows.Count) -Source $ai.Source
    }
    $ob = Get-FirstDataset @('IMP_AIObservability')
    if ($ob) {
        $map = Get-HeaderMap $ob.Rows; $cR = Resolve-Column $map @('Risk level')
        $risk = @($ob.Rows | Where-Object { "$(Get-Val $_ $cR)" -notin @('', 'None', 'N/A') }).Count
        Set-Metric 'am.obs.agents' 'AM' 'Agents in AI observability inventory' $ob.Rows.Count -Source $ob.Source
        Set-Metric 'am.obs.risky' 'AM' 'Agents with a risk level other than None' $risk -Denominator ("{0:N0} agents" -f $ob.Rows.Count) -Source $ob.Source
    }
}

function Measure-Agents {
    $rg = Get-FirstDataset @('IMP_AgentRegistry')
    if ($rg) {
        $map = Get-HeaderMap $rg.Rows; $cO = Resolve-Column $map @('Owner'); $cP = Resolve-Column $map @('Publisher Type'); $cPl = Resolve-Column $map @('Platform')
        $n = $rg.Rows.Count
        $org = @($rg.Rows | Where-Object { "$(Get-Val $_ $cP)" -eq 'Shared' })
        $noOwner = @($org | Where-Object { "$(Get-Val $_ $cO)".Trim() -in @('', '-') }).Count
        Set-Metric 'ag.registry' 'AG' 'Agents in Microsoft 365 admin center registry' $n -Source $rg.Source
        Set-Metric 'ag.registry.noOwner' 'AG' 'Organization-built (Shared) registry agents with no Owner value' $noOwner -Denominator ("{0:N0} organization-built agents; {1:N0} in registry" -f $org.Count, $n) -Source $rg.Source -Note 'Microsoft and third-party agents do not carry an owner in this export and are excluded. Compare with the ownerless tile in the Agents overview, which may use a different definition.'
        Set-Metric 'ag.registry.noOwnerPct' 'AG' 'Organization-built agents with no Owner value (percent)' (Get-Pct $noOwner $org.Count) -Kind pct -Denominator ("{0:N0} organization-built agents" -f $org.Count) -Source $rg.Source
        $byPub = $rg.Rows | Group-Object { "$(Get-Val $_ $cP)" } | Sort-Object Count -Descending | ForEach-Object { "{0}: {1:N0}" -f $(if ($_.Name) { $_.Name } else { '(blank)' }), $_.Count }
        Set-Metric 'ag.registry.byPublisher' 'AG' 'Registry agents by publisher type' ($byPub -join '; ') -Kind text -Source $rg.Source
        $byPl = $rg.Rows | Group-Object { "$(Get-Val $_ $cPl)" } | Sort-Object Count -Descending | Select-Object -First 6 | ForEach-Object { "{0}: {1:N0}" -f $(if ($_.Name) { $_.Name } else { '(blank)' }), $_.Count }
        Set-Metric 'ag.registry.byPlatform' 'AG' 'Registry agents by platform (top 6)' ($byPl -join '; ') -Kind text -Source $rg.Source
    }
    $ua = Get-FirstDataset @('IMP_AgentUsageAgents')
    if ($ua) { Set-Metric 'ag.usage.agents' 'AG' 'Agents with usage in report period' $ua.Rows.Count -Source $ua.Source }
    $uu = Get-FirstDataset @('IMP_AgentUsageUsers')
    if ($uu) { Set-Metric 'ag.usage.users' 'AG' 'Users of agents in report period' $uu.Rows.Count -Source $uu.Source }
    $cn = Get-FirstDataset @('IMP_ConnectorsUsage')
    if ($cn) { Set-Metric 'ag.connectors' 'AG' 'Copilot connectors with usage' $cn.Rows.Count -Source $cn.Source }
    $pk = Get-FirstDataset @('Graph_CopilotPackages')
    if ($pk) {
        $pend = @($pk.Rows | Where-Object { "$(Get-Prop $_ 'requestStatus')" -match 'pending' }).Count
        Set-Metric 'dc.packages' 'DC' 'Agents and apps in the admin center catalog (API)' $pk.Rows.Count -Source $pk.Source
        Set-Metric 'dc.pending' 'DC' 'Catalog items with a pending request' $pend -Denominator ("{0:N0} catalog items" -f $pk.Rows.Count) -Source $pk.Source
    }
}

function Measure-PowerPlatform {
    $cs = Get-FirstDataset @('IMP_CopilotStudioInventory')
    if ($cs) {
        $rows = $cs.Rows; $map = Get-HeaderMap $rows
        $cT = Resolve-Column $map @('Environment type'); $cM = Resolve-Column $map @('Managed environment'); $cA = Resolve-Column $map @('Authentication'); $cB = Resolve-Column $map @('Created by'); $cI = Resolve-Column $map @('Created in'); $cC = Resolve-Column $map @('Connectors')
        $n = $rows.Count; $den = "{0:N0} agents" -f $n
        $def = @($rows | Where-Object { "$(Get-Val $_ $cT)" -eq 'Default' }).Count
        $unm = @($rows | Where-Object { "$(Get-Val $_ $cM)" -eq 'No' }).Count
        $noAuth = @($rows | Where-Object { "$(Get-Val $_ $cA)" -match '^(None|No authentication)$' }).Count
        $creators = @($rows | ForEach-Object { "$(Get-Val $_ $cB)".Trim() } | Where-Object { $_ -and $_ -ne '-' } | Select-Object -Unique).Count
        Set-Metric 'pp.agents' 'PP' 'Copilot Studio and Agent Builder agents (inventory)' $n -Source $cs.Source
        Set-Metric 'pp.agents.default' 'PP' 'Agents in the default environment' $def -Denominator $den -Source $cs.Source
        Set-Metric 'pp.agents.defaultPct' 'PP' 'Agents in the default environment (percent)' (Get-Pct $def $n) -Kind pct -Denominator $den -Source $cs.Source
        Set-Metric 'pp.agents.unmanagedPct' 'PP' 'Agents in environments that are not Managed Environments' (Get-Pct $unm $n) -Kind pct -Denominator ("{0:N0} of {1}" -f $unm, $den) -Source $cs.Source
        Set-Metric 'pp.agents.noAuth' 'PP' 'Agents with no authentication' $noAuth -Denominator $den -Source $cs.Source
        Set-Metric 'pp.agents.creators' 'PP' 'Distinct agent creators' $creators -Denominator ("{0:N0} agents with a named creator" -f @($rows | Where-Object { "$(Get-Val $_ $cB)".Trim() -notin @('', '-') }).Count) -Source $cs.Source
        if ($cI) { Set-Metric 'pp.agents.byTool' 'PP' 'Agents by authoring tool' (($rows | Group-Object { "$(Get-Val $_ $cI)" } | Sort-Object Count -Descending | ForEach-Object { "{0}: {1:N0}" -f $_.Name, $_.Count }) -join '; ') -Kind text -Source $cs.Source }
        if ($cC) { $dv = @($rows | Where-Object { "$(Get-Val $_ $cC)" -match 'dataverse|commondataservice' }).Count; Set-Metric 'dv.agentsUsingDataverse' 'DV' 'Agents using a Dataverse connector' $dv -Denominator $den -Source $cs.Source }
    }
    elseif (($pi = Get-FirstDataset @('PP_Inventory'))) {
        $ag = @($pi.Rows | Where-Object { "$(Get-Prop $_ 'Type')" -match 'copilotstudio/agents' })
        Set-Metric 'pp.agents' 'PP' 'Copilot Studio agents (inventory API)' $ag.Count -Source $pi.Source
    }
    $fl = Get-FirstDataset @('IMP_AgentFlows')
    if ($fl) {
        $map = Get-HeaderMap $fl.Rows; $cT = Resolve-Column $map @('Environment type')
        $def = @($fl.Rows | Where-Object { "$(Get-Val $_ $cT)" -eq 'Default' }).Count
        Set-Metric 'pp.flows' 'PP' 'Agent flows (inventory)' $fl.Rows.Count -Denominator ("{0:N0} in default environment" -f $def) -Source $fl.Source
    }
    $env = Get-FirstDataset @('PP_Environments')
    if ($env) {
        $dvn = @($env.Rows | Where-Object { ConvertTo-Bool (Get-Prop $_ 'HasDataverse') }).Count
        Set-Metric 'pp.environments' 'PP' 'Power Platform environments' $env.Rows.Count -Source $env.Source
        Set-Metric 'dv.environments' 'DV' 'Environments with Dataverse' $dvn -Denominator ("{0:N0} environments" -f $env.Rows.Count) -Source $env.Source
        $db = 0.0; foreach ($e in $env.Rows) { $v = ConvertTo-Num (Get-Prop $e 'DatabaseMB'); if ($v) { $db += $v } }
        Set-Metric 'dv.databaseGB' 'DV' 'Dataverse database capacity consumed (GB)' ([math]::Round($db / 1024, 1)) -Source $env.Source
    }
}

function Measure-Fabric {
    $fb = Get-FirstDataset @('FAB_TenantSettings')
    if ($fb) {
        $cop = @($fb.Rows | Where-Object { "$(Get-Prop $_ 'SettingName') $(Get-Prop $_ 'Title')" -match 'Copilot|OpenAI|AISkill|DataAgent' })
        $on = @($cop | Where-Object { ConvertTo-Bool (Get-Prop $_ 'Enabled') })
        $scoped = @($on | Where-Object { "$(Get-Prop $_ 'EnabledSecurityGroups')".Trim() -ne '' })
        Set-Metric 'fb.copilotSettings' 'FB' 'Fabric tenant settings related to Copilot and AI' $cop.Count -Source $fb.Source
        Set-Metric 'fb.copilotOn' 'FB' 'Copilot and AI settings enabled' $on.Count -Denominator ("{0:N0} settings; {1:N0} enabled settings scoped to security groups" -f $cop.Count, $scoped.Count) -Source $fb.Source
    }
}
