param([Parameter(Mandatory=$true)][string]$WorkDirectory)
$SkillRoot = Split-Path $PSScriptRoot -Parent
if ($WorkDirectory -notmatch '^[a-zA-Z]:[\\/]') { throw 'WorkDirectory must be a fully qualified local directory.' }
$workItem=Get-Item -LiteralPath $WorkDirectory -Force -ErrorAction Stop
if (-not $workItem.PSIsContainer) { throw 'WorkDirectory must be an existing directory.' }
$ErrorActionPreference = 'Stop'
$script:passed = 0
function Assert([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }; $script:passed++
}
function Reject([scriptblock]$Action, [string]$Name) {
    $didThrow=$false; try { $null=& $Action } catch { $didThrow=$true }; Assert $didThrow $Name
}
Assert (Test-Path -LiteralPath (Join-Path $SkillRoot 'scripts\Maintenance.Report.psm1')) 'snapshot comparison and reporting module is available'
Import-Module (Join-Path $SkillRoot 'scripts\Maintenance.Report.psm1') -Force
Import-Module (Join-Path $SkillRoot 'scripts\Maintenance.Inventory.psm1') -Force
function Collection($Status,$Data,$Scope='registry-v1') {
    [pscustomobject]@{Name='Software';QueryStatus=$Status;Complete=($Status -in @('Succeeded','Empty'));Scope=$Scope;Data=@($Data);Errors=@()}
}
function Snapshot($Collection) {
    [pscustomobject]@{Schema='windows-maintenance.snapshot/v1';ToolVersion='2.0.0';MachineKey='fixture-host';CapturedUtc='2026-09-06T12:00:00Z';Collections=@($Collection)}
}
$old=Snapshot (Collection 'Succeeded' @([pscustomobject]@{Key='app/a';Version='1';Name='A'},[pscustomobject]@{Key='app/b';Version='1';Name='B'}))
$new=Snapshot (Collection 'Succeeded' @([pscustomobject]@{Name='B';Version='1';Key='app/b'},[pscustomobject]@{Key='app/a';Name='A';Version='2'},[pscustomobject]@{Key='app/c';Name='C';Version=$null}))
$d=Compare-MaintenanceSnapshot $old $new
Assert (@($d.Collections[0].Changes | Where-Object Change -eq 'Changed').Count -eq 1) 'version change detected independent of row/property order'
Assert (@($d.Collections[0].Changes | Where-Object Change -eq 'Added').Count -eq 1) 'new registry observation detected'
Assert (@($d.Collections[0].Changes | Where-Object Change -eq 'Removed').Count -eq 0) 'unchanged row retained'
$failed=Snapshot (Collection 'Failed' @())
$d=Compare-MaintenanceSnapshot $old $failed
Assert ($d.Collections[0].ComparisonStatus -eq 'Incomparable' -and @($d.Collections[0].Changes).Count -eq 0) 'failed query never creates removals'
$partial=Snapshot (Collection 'Partial' @([pscustomobject]@{Key='app/a';Version='2'}))
$d=Compare-MaintenanceSnapshot $old $partial
Assert ($d.Collections[0].ComparisonStatus -eq 'Incomparable') 'partial query never implies complete delta'
$empty=Snapshot (Collection 'Empty' @())
$d=Compare-MaintenanceSnapshot $old $empty
Assert (@($d.Collections[0].Changes).Count -eq 2) 'complete empty collection differs from a failed query'
$scope=Snapshot (Collection 'Succeeded' @() 'different-source')
Assert ((Compare-MaintenanceSnapshot $old $scope).Collections[0].ComparisonStatus -eq 'Incomparable') 'different query sources not compared'
$userA=Snapshot (Collection 'Succeeded' @([pscustomobject]@{Key='app/a'}) ([pscustomobject]@{Source='Software/local-v1';PrincipalSid='S-1-fixture-A';IsElevated=$false}))
$userB=Snapshot (Collection 'Empty' @() ([pscustomobject]@{Source='Software/local-v1';PrincipalSid='S-1-fixture-B';IsElevated=$false}))
Assert ((Compare-MaintenanceSnapshot $userA $userB).Collections[0].ComparisonStatus -eq 'Incomparable') 'different user registry scopes cannot imply software removal'
$bad=Snapshot (Collection 'Succeeded' @([pscustomobject]@{Key='duplicate'},[pscustomobject]@{Key='DUPLICATE'}))
Assert ((Compare-MaintenanceSnapshot $old $bad).Collections[0].ComparisonStatus -eq 'Incomparable') 'ambiguous identities not silently overwritten'
$hostMismatch=Snapshot (Collection 'Empty' @()); $hostMismatch.MachineKey='other-host'
Reject { Compare-MaintenanceSnapshot $old $hostMismatch } 'different computers rejected'
$hostMismatch.MachineKey=$null
Reject { Compare-MaintenanceSnapshot $old $hostMismatch } 'unknown computer identity rejected'
$hostMismatch.Schema='future/v2'
Reject { Compare-MaintenanceSnapshot $old $hostMismatch } 'unsupported schema rejected'
$nullBefore=Snapshot (Collection 'Succeeded' @([pscustomobject]@{Key='x';Value=$null}))
$zeroAfter=Snapshot (Collection 'Succeeded' @([pscustomobject]@{Key='x';Value=0}))
Assert (@((Compare-MaintenanceSnapshot $nullBefore $zeroAfter).Collections[0].Changes).Count -eq 1) 'unknown is different from zero'
$caseBefore=Snapshot (Collection 'Succeeded' @([pscustomobject]@{Key='x';Arguments='--profile A'}))
$caseAfter=Snapshot (Collection 'Succeeded' @([pscustomobject]@{Key='x';Arguments='--profile a'}))
Assert (@((Compare-MaintenanceSnapshot $caseBefore $caseAfter).Collections[0].Changes).Count -eq 1) 'case sensitive argument changes are preserved'
$arrayBefore=Snapshot (Collection 'Succeeded' @([pscustomobject]@{Key='x';Values=@($null,1)}))
$arrayAfter=Snapshot (Collection 'Succeeded' @([pscustomobject]@{Key='x';Values=@(1)}))
Assert (@((Compare-MaintenanceSnapshot $arrayBefore $arrayAfter).Collections[0].Changes).Count -eq 1) 'unknown array elements are not silently removed'
$fixture=Join-Path $workItem.FullName ('fixture-' + [guid]::NewGuid().ToString('N'))
$project=Join-Path $fixture 'project'; $outside=Join-Path $fixture 'outside'
$null=New-Item -ItemType Directory -Path $project,$outside,(Join-Path $project 'node_modules'),(Join-Path $project 'src'),(Join-Path $project 'models'),(Join-Path $project 'cache-unconfirmed') -Force
[IO.File]::WriteAllText((Join-Path $project 'package.json'),'{}')
[IO.File]::WriteAllBytes((Join-Path $project 'node_modules\dependency.bin'),[byte[]](1,2,3))
[IO.File]::WriteAllText((Join-Path $project 'src\index.js'),'source')
[IO.File]::WriteAllText((Join-Path $outside 'private.bin'),'external')
$null=New-Item -ItemType Junction -Path (Join-Path $project 'link') -Target $outside
$dir=Get-MaintenanceDirectoryInventory -Path $project -MaxDepth 3 -MaxSeconds 30
Assert ($dir.Complete -and $dir.SkippedReparsePoints -eq 1) 'directory scan skips junction without traversing target'
$dep=@($dir.Data | Where-Object Category -eq 'DependencyCache')
Assert ($dep.Count -eq 1 -and $dep[0].LogicalBytes -eq 3 -and -not $dep[0].DeletionAuthorized) 'project dependencies classified but never authorized for deletion'
Assert (@($dir.Data | Where-Object Category -eq 'UserData').Count -ge 1) 'models remain user data'
Assert (@($dir.Data | Where-Object Path -like '*private.bin*').Count -eq 0) 'outside junction target absent'
$size=@($dir.Data | Where-Object Kind -eq 'RootSummary')[0]
Assert ($size.LogicalBytes -eq 11) 'root size covers normal files exactly once'
$otherDir=Get-MaintenanceDirectoryInventory -Path $outside
$rootDiff=Compare-MaintenanceSnapshot (Snapshot $dir) (Snapshot $otherDir)
Assert ($rootDiff.Collections[0].ComparisonStatus -eq 'Incomparable') 'same length but different root paths are different query scopes'
$timeout=Get-MaintenanceDirectoryInventory -Path $project -MaxSeconds 0
Assert (-not $timeout.Complete -and $timeout.QueryStatus -eq 'Partial') 'directory timeout remains incomplete'
Reject { Get-MaintenanceDirectoryInventory -Path @($project,(Join-Path $project 'src')) } 'overlapping scan roots rejected'
Reject { Get-MaintenanceDirectoryInventory -Path (Join-Path $project 'link') } 'reparse root rejected'
$limited=Get-MaintenanceDirectoryInventory -Path $project -MaxEntries 1
Assert (-not $limited.Complete) 'entry limit remains incomplete'
$json=Join-Path $fixture 'report.json'; $md=Join-Path $fixture 'report.md'
Export-MaintenanceReport -InputObject $new -JsonPath $json -MarkdownPath $md
$roundTrip=Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
Assert ($roundTrip.Schema -eq $new.Schema -and $null -eq $roundTrip.Collections[0].Data[2].Version) 'JSON round trip preserves schema and unknown version'
Assert ((Get-Item -LiteralPath $md).Length -gt 100) 'readable report generated'
$hash=(Get-FileHash -LiteralPath $json).Hash
Reject { Export-MaintenanceReport -InputObject $old -JsonPath $json -MarkdownPath $md } 'existing report cannot be overwritten'
Assert ((Get-FileHash -LiteralPath $json).Hash -eq $hash) 'failed overwrite leaves original evidence intact'
$d=Compare-MaintenanceSnapshot $old $failed
Export-MaintenanceReport -InputObject $d -JsonPath (Join-Path $fixture 'diff.json') -MarkdownPath (Join-Path $fixture 'diff.md')
Assert ((Get-Content -LiteralPath (Join-Path $fixture 'diff.md') -Raw) -match 'Incomparable') 'report exposes incomparable state'
[pscustomobject]@{Passed=$script:passed;PowerShell=$PSVersionTable.PSVersion.ToString();Fixture=$fixture;SideEffects='Only isolated fixture/report creation; no system mutation.'} | ConvertTo-Json
