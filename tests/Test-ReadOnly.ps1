param([Parameter(Mandatory=$true)][string]$WorkDirectory)
$SkillRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'skills\windows-maintenance'
$ErrorActionPreference = 'Stop'
$module = Join-Path $SkillRoot 'scripts\Maintenance.ReadOnly.psm1'
if (-not (Test-Path -LiteralPath $module)) { throw 'RED: maintenance helper module is not implemented.' }
Import-Module $module -Force
$testRoot = Join-Path $WorkDirectory ('fixture-' + [guid]::NewGuid().ToString('N'))
$inside = Join-Path $testRoot 'inside'
$outside = Join-Path $testRoot 'outside'
$null = New-Item -ItemType Directory -Path $inside,$outside
[IO.File]::WriteAllBytes((Join-Path $inside 'one.bin'), [byte[]](1,2,3))
[IO.File]::WriteAllBytes((Join-Path $outside 'external.bin'), [byte[]](1,2,3,4,5))
$script:passed = 0
function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
}
function Assert-Rejected([scriptblock]$Action, [string]$Name) {
    $rejected = $false
    try { $null = & $Action } catch { $rejected = $true }
    Assert-True $rejected $Name
}
$r = Invoke-MaintenanceRead -Name 'success' -Action { [pscustomobject]@{Value=1} }
Assert-True ($r.QueryStatus -eq 'Succeeded' -and $r.Data.Count -eq 1 -and $r.Errors.Count -eq 0) 'success retains data'
$r = Invoke-MaintenanceRead -Name 'empty' -Action { }
Assert-True ($r.QueryStatus -eq 'Empty' -and $r.Data.Count -eq 0) 'empty is distinct from health/success'
$r = Invoke-MaintenanceRead -Name 'failure' -Action { throw 'Access denied' }
Assert-True ($r.QueryStatus -eq 'Failed' -and $r.Errors.Count -eq 1) 'permission failure is not success'
$r = Invoke-MaintenanceRead -Name 'partial' -Action { 'first'; Write-Error 'second inaccessible' -ErrorAction Continue }
Assert-True ($r.QueryStatus -eq 'Partial' -and $r.Data.Count -eq 1 -and $r.Errors.Count -eq 1) 'partial output retains error'
$safe = Resolve-MaintenanceChildPath -Root $inside -Path (Join-Path $inside 'one.bin')
Assert-True ($safe -eq (Join-Path $inside 'one.bin')) 'literal child accepted'
Assert-Rejected { Resolve-MaintenanceChildPath -Root $inside -Path $inside } 'root itself rejected'
Assert-Rejected { Resolve-MaintenanceChildPath -Root $inside -Path ($inside + '\') } 'root with trailing slash rejected'
Assert-Rejected { Resolve-MaintenanceChildPath -Root $inside -Path (Join-Path $outside 'external.bin') } 'sibling rejected'
Assert-Rejected { Resolve-MaintenanceChildPath -Root $inside -Path (Join-Path $inside '..\outside\external.bin') } 'dot-dot escape rejected'
$r = Get-MaintenanceTreeSize -Path $inside
Assert-True ($r.LogicalBytes -eq 3 -and $r.Files -eq 1 -and $r.Complete) 'exact small-tree logical size'
$link = Join-Path $inside 'external-link'
$null = New-Item -ItemType Junction -Path $link -Target $outside
Assert-Rejected { Resolve-MaintenanceChildPath -Root $inside -Path (Join-Path $link 'external.bin') } 'ancestor junction rejected'
Assert-Rejected { Get-MaintenanceTreeSize -Path $link } 'junction root rejected'
$r = Get-MaintenanceTreeSize -Path $inside
Assert-True ($r.LogicalBytes -eq 3 -and $r.SkippedReparsePoints -eq 1 -and $r.Files -eq 1) 'junction content is not counted twice'
Assert-Rejected { Get-MaintenanceTreeSize -Path (Join-Path $inside 'missing') } 'missing tree rejected'
$r = Get-MaintenanceTreeSize -Path $outside -MaxSeconds 0
Assert-True (-not $r.Complete -and $r.TimedOut -and $r.LogicalBytes -eq 0) 'timeout is explicitly incomplete'
[pscustomobject]@{Passed=$script:passed;Fixture=$testRoot;SideEffects='Only isolated fixture files and a junction were created; no deletion or system changes.'} | ConvertTo-Json
