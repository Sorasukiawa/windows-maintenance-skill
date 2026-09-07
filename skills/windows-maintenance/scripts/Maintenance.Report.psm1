# PowerShell 5.1+. Writes only explicitly named new report files.
Set-StrictMode -Version 2.0

function ConvertTo-MaintenanceCanonicalValue {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [DateTime]) { return $Value.ToUniversalTime().ToString('o') }
    if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime.ToString('o') }
    # Pipeline-decorated strings can satisfy -is [pscustomobject] as well as -is [string].
    # Preserve scalar values before examining their adapted PSObject properties (e.g. Length).
    if ($Value -is [string] -or $Value -is [bool] -or $Value.GetType().IsPrimitive -or $Value -is [decimal] -or $Value -is [Guid]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $map=[ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object)) { $map[$key]=ConvertTo-MaintenanceCanonicalValue $Value[$key] }
        return $map
    }
    if ($Value -is [pscustomobject]) {
        $map=[ordered]@{}
        foreach ($p in @($Value.PSObject.Properties | Sort-Object Name)) { $map[$p.Name]=ConvertTo-MaintenanceCanonicalValue $p.Value }
        return $map
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items=@(foreach ($v in $Value) { ConvertTo-MaintenanceCanonicalValue $v })
        return ,$items
    }
    return $Value
}

function Get-MaintenanceCanonicalJson {
    param($Value)
    ConvertTo-Json -InputObject (ConvertTo-MaintenanceCanonicalValue $Value) -Depth 30 -Compress
}

function Compare-MaintenanceSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Before,[Parameter(Mandatory=$true)]$After)
    if ($Before.Schema -ne 'windows-maintenance.snapshot/v1' -or $After.Schema -ne $Before.Schema) { throw 'Unsupported snapshot schema.' }
    if ([string]::IsNullOrWhiteSpace($Before.MachineKey) -or $Before.MachineKey -ne $After.MachineKey) { throw 'Snapshots require the same known MachineKey.' }
    $results=New-Object 'System.Collections.Generic.List[object]'
    $names=@(@($Before.Collections | ForEach-Object Name) + @($After.Collections | ForEach-Object Name) | Sort-Object -Unique)
    foreach ($name in $names) {
        $b=@($Before.Collections | Where-Object Name -eq $name); $a=@($After.Collections | Where-Object Name -eq $name)
        $reason=$null; $changes=New-Object 'System.Collections.Generic.List[object]'
        if ($b.Count -ne 1 -or $a.Count -ne 1) { $reason='Collection absent or duplicated.' }
        elseif ($name -eq 'Stability') { $reason='Rolling event windows are evidence snapshots; absence is not event removal or recovery.' }
        elseif ($b[0].QueryStatus -notin @('Succeeded','Empty') -or $a[0].QueryStatus -notin @('Succeeded','Empty') -or -not $b[0].Complete -or -not $a[0].Complete) { $reason='At least one query was failed, partial, timed out, or incomplete.' }
        elseif ((Get-MaintenanceCanonicalJson $b[0].Scope) -cne (Get-MaintenanceCanonicalJson $a[0].Scope)) { $reason='Query scopes differ.' }
        else {
            $bm=@{}; $am=@{}
            foreach ($pair in @(@{Rows=$b[0].Data;Map=$bm},@{Rows=$a[0].Data;Map=$am})) {
                foreach ($row in @($pair.Rows)) {
                    if (-not ($row.PSObject.Properties.Name -contains 'Key') -or [string]::IsNullOrWhiteSpace($row.Key) -or $pair.Map.ContainsKey([string]$row.Key)) { $reason='Missing or duplicate stable item identity.'; break }
                    $pair.Map[[string]$row.Key]=$row
                }
            }
            if ($null -eq $reason) {
                foreach ($key in @(@($bm.Keys)+@($am.Keys) | Sort-Object -Unique)) {
                    $change=$null
                    if (-not $bm.ContainsKey($key)) { $change='Added' }
                    elseif (-not $am.ContainsKey($key)) { $change='Removed' }
                    elseif ((Get-MaintenanceCanonicalJson $bm[$key]) -cne (Get-MaintenanceCanonicalJson $am[$key])) { $change='Changed' }
                    if ($null -ne $change) { $changes.Add([pscustomobject]@{Key=$key;Change=$change;Before=$bm[$key];After=$am[$key]}) }
                }
            }
        }
        $status='Compared'; if ($null -ne $reason) { $status='Incomparable' }
        $results.Add([pscustomobject]@{Name=$name;ComparisonStatus=$status;Reason=$reason;Changes=@($changes.ToArray())})
    }
    [pscustomobject]@{Schema='windows-maintenance.comparison/v1';ToolVersion='2.0.0';MachineKey=$After.MachineKey;CapturedUtc=[DateTime]::UtcNow.ToString('o');BeforeUtc=$Before.CapturedUtc;AfterUtc=$After.CapturedUtc;Collections=@($results.ToArray());Meaning='Observed differences within comparable query sources; not proof of an update, uninstall, recovered space, or restored stability.'}
}

function ConvertTo-MaintenanceCell {
    param($Value)
    if ($null -eq $Value) { return '未取得' }
    $s=[string]$Value
    $s=$s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('|','&#124;').Replace('`','&#96;')
    $s=$s -replace '\r?\n',' / '
    return $s
}

function Export-MaintenanceReport {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$InputObject,[Parameter(Mandatory=$true)][string]$JsonPath,[Parameter(Mandatory=$true)][string]$MarkdownPath)
    if ($InputObject.Schema -notin @('windows-maintenance.snapshot/v1','windows-maintenance.comparison/v1')) { throw 'Unsupported report schema.' }
    $paths=@($JsonPath,$MarkdownPath) | ForEach-Object {
        if ($_ -notmatch '^[a-zA-Z]:[\\/]') { throw 'Report paths must be fully qualified local drive paths.' }
        $full=[IO.Path]::GetFullPath($_)
        if (Test-Path -LiteralPath $full) { throw "Report already exists: $full" }
        $parent=Get-Item -LiteralPath ([IO.Path]::GetDirectoryName($full)) -Force -ErrorAction Stop
        if (-not $parent.PSIsContainer) { throw 'Report parent must be a directory.' }
        while ($null -ne $parent) {
            if (($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Report parent contains a reparse point.' }
            $parent=$parent.Parent
        }
        $full
    }
    if ($paths[0] -eq $paths[1]) { throw 'JSON and Markdown paths must differ.' }
    $lines=New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('# Windows 维护采集报告')
    $lines.Add(''); $lines.Add(('采集时间：' + (ConvertTo-MaintenanceCell $InputObject.CapturedUtc)))
    $lines.Add(''); $lines.Add('此报告记录查询证据。未检查的渠道、应用实际功能、系统完整性和负载稳定性需要按任务补证；脚本不执行安装、删除、修复或刷写。')
    if ($InputObject.Schema -eq 'windows-maintenance.comparison/v1') {
        $lines.Add(''); $lines.Add('差异仅表示相同查询来源的观测变化；Removed 不等于已卸载，卷空闲差值不等于清理释放量。')
        foreach ($c in $InputObject.Collections) {
            $lines.Add(''); $lines.Add(('## ' + (ConvertTo-MaintenanceCell $c.Name) + ' — ' + $c.ComparisonStatus))
            if ($c.Reason) { $lines.Add(''); $lines.Add((ConvertTo-MaintenanceCell $c.Reason)) }
            $lines.Add(''); $lines.Add('| 对象 | 差异 | 原观测值 | 新观测值 |'); $lines.Add('|---|---|---|---|')
            foreach ($change in $c.Changes) {
                $lines.Add(('| {0} | {1} | {2} | {3} |' -f (ConvertTo-MaintenanceCell $change.Key),$change.Change,(ConvertTo-MaintenanceCell (Get-MaintenanceCanonicalJson $change.Before)),(ConvertTo-MaintenanceCell (Get-MaintenanceCanonicalJson $change.After))))
            }
        }
    } else {
        $lines.Add(''); $lines.Add('目录行包含子目录，父子行不能相加；只汇总互不重叠的 RootSummary。超时或访问失败的大小只是下限。目录类别只供人工筛选，不是删除许可。')
        $lines.Add(''); $lines.Add('| 范围 | 查询状态 | 完整 | 条目数 |'); $lines.Add('|---|---|---|---|')
        foreach ($c in $InputObject.Collections) { $lines.Add(('| {0} | {1} | {2} | {3} |' -f (ConvertTo-MaintenanceCell $c.Name),$c.QueryStatus,$c.Complete,@($c.Data).Count)) }
        foreach ($c in $InputObject.Collections) {
            $lines.Add(''); $lines.Add(('## ' + (ConvertTo-MaintenanceCell $c.Name)))
            $lines.Add(''); $lines.Add(('查询来源：' + (ConvertTo-MaintenanceCell (Get-MaintenanceCanonicalJson $c.Scope))))
            if ($c.PSObject.Properties.Name -contains 'Meaning') { $lines.Add(''); $lines.Add((ConvertTo-MaintenanceCell $c.Meaning)) }
            foreach ($err in @($c.Errors)) { $lines.Add(''); $lines.Add(('采集错误：' + (ConvertTo-MaintenanceCell $err.Message))) }
            $lines.Add(''); $lines.Add('| 对象 | 观测字段 |'); $lines.Add('|---|---|')
            # Keep detailed event XML and long inventories in JSON; explicitly disclose the preview bound.
            foreach ($row in @($c.Data | Select-Object -First 80)) {
                $display=[ordered]@{}
                foreach ($p in $row.PSObject.Properties) { if ($p.Name -notin @('Key','Xml')) { $display[$p.Name]=$p.Value } }
                $lines.Add(('| {0} | {1} |' -f (ConvertTo-MaintenanceCell $row.Key),(ConvertTo-MaintenanceCell (Get-MaintenanceCanonicalJson $display))))
            }
            if (@($c.Data).Count -gt 80) { $lines.Add(''); $lines.Add('本节只预览前 80 项，全部数据保存在同名 JSON 报告。') }
        }
    }
    $payloads=@((ConvertTo-Json -InputObject $InputObject -Depth 30),($lines.ToArray() -join [Environment]::NewLine))
    for ($i=0;$i -lt 2;$i++) {
        $stream=$null; $writer=$null
        try {
            $stream=[IO.File]::Open($paths[$i],[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            $writer=New-Object IO.StreamWriter($stream,(New-Object Text.UTF8Encoding($true)))
            $writer.Write($payloads[$i]); $writer.Flush()
        } finally { if ($null -ne $writer) { $writer.Dispose() }; if ($null -ne $stream) { $stream.Dispose() } }
    }
}

Export-ModuleMember -Function Compare-MaintenanceSnapshot,Export-MaintenanceReport
