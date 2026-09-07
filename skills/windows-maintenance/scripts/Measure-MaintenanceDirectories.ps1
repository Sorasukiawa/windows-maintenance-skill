<#
.SYNOPSIS
Inventory explicitly selected, non-overlapping local directories without deleting anything.
.EXAMPLE
& .\Measure-MaintenanceDirectories.ps1 -Path 'C:\work\project' -OutputBase 'C:\work\space-before'
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string[]]$Path,[Parameter(Mandatory=$true)][string]$OutputBase,[ValidateRange(1,10)][int]$ReportDepth=3,[ValidateRange(0,3600)][double]$MaxSeconds=30,[ValidateRange(1,1000000)][int]$MaxEntries=100000)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Maintenance.Inventory.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Maintenance.Report.psm1') -Force
$collection=Get-MaintenanceDirectoryInventory -Path $Path -MaxDepth $ReportDepth -MaxSeconds $MaxSeconds -MaxEntries $MaxEntries
$snapshot=[pscustomobject]@{Schema='windows-maintenance.snapshot/v1';ToolVersion='2.0.0';MachineKey=(Get-MaintenanceMachineKey);CapturedUtc=[DateTime]::UtcNow.ToString('o');Collections=@($collection)}
Export-MaintenanceReport -InputObject $snapshot -JsonPath ($OutputBase+'.json') -MarkdownPath ($OutputBase+'.md')
[pscustomobject]@{Json=($OutputBase+'.json');Markdown=($OutputBase+'.md');Complete=$collection.Complete;Meaning=$collection.Meaning}
