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
    [ValidateRange(1,10)][int]$ReportDepth=3
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Maintenance.Inventory.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Maintenance.Report.psm1') -Force
if (Test-Path -LiteralPath ($OutputBase+'.json')) { throw 'Choose a new OutputBase; existing evidence is never overwritten.' }
if (Test-Path -LiteralPath ($OutputBase+'.md')) { throw 'Choose a new OutputBase; existing evidence is never overwritten.' }
$snapshot=Get-MaintenanceSnapshot -Groups $Groups -GroupTimeoutSeconds $GroupTimeoutSeconds -EventDays $EventDays -MaxEvents $MaxEvents
if ($ScanPath.Count -gt 0) { $snapshot.Collections+=@(Get-MaintenanceDirectoryInventory -Path $ScanPath -MaxSeconds $ScanSeconds -MaxDepth $ReportDepth) }
Export-MaintenanceReport -InputObject $snapshot -JsonPath ($OutputBase+'.json') -MarkdownPath ($OutputBase+'.md')
[pscustomobject]@{Json=($OutputBase+'.json');Markdown=($OutputBase+'.md');Incomplete=@($snapshot.Collections | Where-Object { -not $_.Complete } | ForEach-Object Name);Meaning='Report generation completed; query status and system health are separate.'}
