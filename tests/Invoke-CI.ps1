param([Parameter(Mandatory=$true)][string]$WorkDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$skill=Join-Path $repo 'skills\windows-maintenance'
if (Test-Path -LiteralPath $WorkDirectory) { throw 'Use a new isolated WorkDirectory.' }
$null=New-Item -ItemType Directory -Path $WorkDirectory -ErrorAction Stop

$sources=@(Get-ChildItem -LiteralPath (Join-Path $repo 'skills'),$PSScriptRoot -Recurse -File | Where-Object Extension -in @('.ps1','.psm1'))
foreach ($file in $sources) {
    $tokens=$null; $errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) { throw ('Syntax failure in '+$file.FullName+': '+($errors.Message -join '; ')) }
    $bytes=[IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) { throw ('Missing UTF-8 BOM: '+$file.Name) }
}
$entry=Get-Content -LiteralPath (Join-Path $skill 'SKILL.md') -Raw -Encoding UTF8
if ($entry -notmatch '(?s)^---\r?\nname: windows-maintenance\r?\ndescription: [^\r\n]+\r?\n---') { throw 'Invalid skill front matter.' }
foreach ($file in @(Get-ChildItem -LiteralPath $repo -Recurse -File -Filter '*.md')) {
    $markdown=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    foreach ($link in [regex]::Matches($markdown,'\]\(([^)]+)\)')) {
        $target=$link.Groups[1].Value
        if ($target -match '^(https?://|#)') { continue }
        $relative=($target -split '#',2)[0]
        if (-not (Test-Path -LiteralPath (Join-Path $file.DirectoryName $relative))) { throw ('Missing local reference: '+$file.Name+' -> '+$target) }
    }
}
$newResult=(& (Join-Path $skill 'scripts\Test-Maintenance.ps1') -WorkDirectory $WorkDirectory) | ConvertFrom-Json
$oldResult=(& (Join-Path $PSScriptRoot 'Test-ReadOnly.ps1') -WorkDirectory $WorkDirectory) | ConvertFrom-Json
if ($newResult.Passed -le 0 -or $oldResult.Passed -le 0) { throw 'Behavior tests did not report passing assertions.' }
[pscustomobject]@{PowerShell=$PSVersionTable.PSVersion.ToString();ParsedScripts=$sources.Count;NewAssertions=$newResult.Passed;OriginalAssertions=$oldResult.Passed;TotalAssertions=($newResult.Passed+$oldResult.Passed);SystemMaintenancePerformed=$false} | ConvertTo-Json
