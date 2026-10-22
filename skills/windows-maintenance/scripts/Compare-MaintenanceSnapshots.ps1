<#
.SYNOPSIS
Compare same-machine snapshots; incomplete or differently scoped queries are incomparable.
.EXAMPLE
& .\Compare-MaintenanceSnapshots.ps1 -BeforePath 'C:\work\before.json' -AfterPath 'C:\work\after.json' -OutputBase 'C:\work\diff'
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$BeforePath,[Parameter(Mandatory=$true)][string]$AfterPath,[Parameter(Mandatory=$true)][string]$OutputBase)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Maintenance.Report.psm1') -Force
$reportPaths=Resolve-MaintenanceReportPaths -JsonPath ($OutputBase+'.json') -MarkdownPath ($OutputBase+'.md')
$before=Get-Content -LiteralPath $BeforePath -Raw -Encoding UTF8 | ConvertFrom-Json
$after=Get-Content -LiteralPath $AfterPath -Raw -Encoding UTF8 | ConvertFrom-Json
$comparison=Compare-MaintenanceSnapshot -Before $before -After $after
Export-MaintenanceReport -InputObject $comparison -JsonPath $reportPaths.JsonPath -MarkdownPath $reportPaths.MarkdownPath
[pscustomobject]@{Json=$reportPaths.JsonPath;Markdown=$reportPaths.MarkdownPath;Incomparable=@($comparison.Collections | Where-Object ComparisonStatus -eq 'Incomparable' | ForEach-Object Name)}
