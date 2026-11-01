<#
.SYNOPSIS
Collect local read-only Windows evidence and write NEW JSON/Markdown report files.
.EXAMPLE
& .\Collect-MaintenanceSnapshot.ps1 -OutputBase 'C:\work\before'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$OutputBase,
    [ValidateSet('System','Storage','Drivers','Software','Startup','Stability','Security')][string[]]$Groups=@('System','Storage','Drivers','Software','Startup','Stability','Security'),
    [ValidateRange(1,60)][int]$GroupTimeoutSeconds=45,
    [ValidateRange(1,90)][int]$EventDays=14,
    [ValidateRange(1,5000)][int]$MaxEvents=200,
    [string[]]$ScanPath=@(),
    [ValidateRange(0,3600)][double]$ScanSeconds=30,
    [ValidateRange(1,10)][int]$ReportDepth=3,
    [ValidateRange(1,1000000)][int]$MaxEntries=100000
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Maintenance.Inventory.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Maintenance.Report.psm1') -Force
$reportPaths=Resolve-MaintenanceReportPaths -JsonPath ($OutputBase+'.json') -MarkdownPath ($OutputBase+'.md')
$snapshot=Get-MaintenanceSnapshot -Groups $Groups -GroupTimeoutSeconds $GroupTimeoutSeconds -EventDays $EventDays -MaxEvents $MaxEvents
if ($ScanPath.Count -gt 0) { $snapshot.Collections+=@(Get-MaintenanceDirectoryInventory -Path $ScanPath -MaxSeconds $ScanSeconds -MaxDepth $ReportDepth -MaxEntries $MaxEntries) }
Export-MaintenanceReport -InputObject $snapshot -JsonPath $reportPaths.JsonPath -MarkdownPath $reportPaths.MarkdownPath
[pscustomobject]@{Json=$reportPaths.JsonPath;Markdown=$reportPaths.MarkdownPath;Incomplete=@($snapshot.Collections | Where-Object { -not $_.Complete } | ForEach-Object Name);Meaning='Report generation completed; query status and system health are separate.'}
