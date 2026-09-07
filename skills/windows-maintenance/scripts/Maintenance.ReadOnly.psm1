# PowerShell 5.1+. This module performs no deletion, installation or registry edits.
Set-StrictMode -Version 2.0

function Invoke-MaintenanceRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][scriptblock]$Action
    )
    # Use for trusted, read-only PowerShell cmdlets. Native exit codes need a separate record.
    $started = [DateTimeOffset]::Now
    $data = New-Object 'System.Collections.Generic.List[object]'
    $errors = New-Object 'System.Collections.Generic.List[object]'
    $ErrorActionPreference = 'Stop'
    try {
        & $Action 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $errors.Add([pscustomobject]@{Message=$_.Exception.Message;Id=$_.FullyQualifiedErrorId})
            } else { $data.Add($_) }
        }
    } catch {
        $errors.Add([pscustomobject]@{Message=$_.Exception.Message;Id=$_.FullyQualifiedErrorId})
    }
    $status = 'Succeeded'
    if ($errors.Count -gt 0) {
        if ($data.Count -gt 0) { $status = 'Partial' } else { $status = 'Failed' }
    } elseif ($data.Count -eq 0) { $status = 'Empty' }
    [pscustomobject]@{
        Name=$Name;Started=$started.ToString('o');Finished=[DateTimeOffset]::Now.ToString('o')
        QueryStatus=$status;Data=@($data.ToArray());Errors=@($errors.ToArray())
    }
}

function Resolve-MaintenanceLocalPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    # Restrict this local-maintenance helper to fully qualified drive paths.
    if ($Path -notmatch '^[a-zA-Z]:[\\/]') { throw 'A fully qualified local drive path is required.' }
    $full = [IO.Path]::GetFullPath($Path)
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    $cursor = $item
    while ($null -ne $cursor) {
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('Reparse point in path: ' + $cursor.FullName)
        }
        $parent = [IO.Directory]::GetParent($cursor.FullName)
        if ($null -eq $parent) { break }
        $cursor = Get-Item -LiteralPath $parent.FullName -Force -ErrorAction Stop
    }
    $item.FullName
}

function Resolve-MaintenanceChildPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$Path
    )
    $rootFull = Resolve-MaintenanceLocalPath -Path $Root
    if (-not (Get-Item -LiteralPath $rootFull -Force -ErrorAction Stop).PSIsContainer) {
        throw 'Root must be an existing directory.'
    }
    $pathFull = Resolve-MaintenanceLocalPath -Path $Path
    $rootComparable = $rootFull.TrimEnd([char[]]@('\','/'))
    $pathComparable = $pathFull.TrimEnd([char[]]@('\','/'))
    $prefix = $rootComparable + [IO.Path]::DirectorySeparatorChar
    if ($pathComparable.Equals($rootComparable, [StringComparison]::OrdinalIgnoreCase) -or
        (-not $pathComparable.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) {
        throw 'Target must be strictly inside the selected root; the root itself is not a child.'
    }
    # This validates location only; it is not evidence that a file is disposable.
    $pathFull
}

function Get-MaintenanceTreeSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [ValidateRange(0,86400)][double]$MaxSeconds = 30
    )
    $full = Resolve-MaintenanceLocalPath -Path $Path
    if (-not (Get-Item -LiteralPath $full -Force -ErrorAction Stop).PSIsContainer) {
        throw 'Path must be an existing directory.'
    }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($full)
    $errors = New-Object 'System.Collections.Generic.List[object]'
    [long]$bytes = 0; [long]$files = 0; [long]$links = 0
    $timedOut = $false
    while ($stack.Count -gt 0) {
        if ($clock.Elapsed.TotalSeconds -ge $MaxSeconds) { $timedOut=$true; break }
        $dir = $stack.Pop()
        try {
            # Recheck queued directories in case a link was introduced after enumeration.
            $directory = Get-Item -LiteralPath $dir -Force -ErrorAction Stop
            if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $links++; continue
            }
            foreach ($entry in ([IO.DirectoryInfo]$directory).EnumerateFileSystemInfos()) {
                if ($clock.Elapsed.TotalSeconds -ge $MaxSeconds) { $timedOut=$true; break }
                try {
                    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                        $links++; continue
                    }
                    if (($entry.Attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                        $stack.Push($entry.FullName)
                    } else {
                        $bytes += $entry.Length; $files++
                    }
                } catch {
                    $errors.Add([pscustomobject]@{Path=$entry.FullName;Message=$_.Exception.Message})
                }
            }
        } catch {
            $errors.Add([pscustomobject]@{Path=$dir;Message=$_.Exception.Message})
        }
        if ($timedOut) { break }
    }
    [pscustomobject]@{
        Path=$full;LogicalBytes=$bytes;Files=$files;SkippedReparsePoints=$links
        Complete=((-not $timedOut) -and ($errors.Count -eq 0));TimedOut=$timedOut
        Errors=@($errors.ToArray());Seconds=[Math]::Round($clock.Elapsed.TotalSeconds,3)
        SizeMeaning='Logical size of readable non-reparse entries; hard links may be counted more than once. Not reclaimable physical space.'
    }
}

Export-ModuleMember -Function Invoke-MaintenanceRead,Resolve-MaintenanceChildPath,Get-MaintenanceTreeSize
