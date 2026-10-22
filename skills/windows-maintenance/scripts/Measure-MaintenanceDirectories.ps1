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
$reportPaths=Resolve-MaintenanceReportPaths -JsonPath ($OutputBase+'.json') -MarkdownPath ($OutputBase+'.md')
$collection=Get-MaintenanceDirectoryInventory -Path $Path -MaxDepth $ReportDepth -MaxSeconds $MaxSeconds -MaxEntries $MaxEntries
$snapshot=[pscustomobject]@{Schema='windows-maintenance.snapshot/v1';ToolVersion='2.0.0';MachineKey=(Get-MaintenanceMachineKey);CapturedUtc=[DateTime]::UtcNow.ToString('o');Collections=@($collection);NotCollected=@('System, Storage, Drivers, Software, Startup, Stability, and Security groups (directory-only run)','Online update availability','Store and portable software inventory','Active application versions','Full SMART and temperatures','DISM/SFC health conclusions','Firmware update applicability','Application configuration adoption','Load stability')}
Export-MaintenanceReport -InputObject $snapshot -JsonPath $reportPaths.JsonPath -MarkdownPath $reportPaths.MarkdownPath
[pscustomobject]@{Json=$reportPaths.JsonPath;Markdown=$reportPaths.MarkdownPath;Complete=$collection.Complete;Meaning=$collection.Meaning}
