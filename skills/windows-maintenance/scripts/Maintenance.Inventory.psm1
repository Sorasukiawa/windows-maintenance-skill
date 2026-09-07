# PowerShell 5.1+. Local read-only inventory; importing this module does not collect anything.
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Maintenance.ReadOnly.psm1') -Force

function Get-MaintenanceMachineKey {
    try {
        $id=(Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
        if ([string]::IsNullOrWhiteSpace($id)) { return $null }
        $sha=[Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($id)))).Replace('-','').ToLowerInvariant() }
        finally { $sha.Dispose() }
    } catch { return $null }
}

function Get-MaintenanceDirectoryInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string[]]$Path,[ValidateRange(1,10)][int]$MaxDepth=3,[ValidateRange(0,3600)][double]$MaxSeconds=30,[ValidateRange(1,1000000)][int]$MaxEntries=100000)
    $roots=@(foreach ($p in $Path) { (Get-MaintenanceTreeSize -Path $p -MaxSeconds 0).Path.TrimEnd([char[]]@('\','/')) + '\' })
    for ($i=0;$i -lt $roots.Count;$i++) {
        for ($j=0;$j -lt $roots.Count;$j++) {
            if ($i -ne $j -and $roots[$i].StartsWith($roots[$j],[StringComparison]::OrdinalIgnoreCase)) { throw 'Overlapping or duplicate scan roots are not allowed.' }
        }
    }
    $clock=[Diagnostics.Stopwatch]::StartNew(); $started=[DateTime]::UtcNow.ToString('o')
    $errors=New-Object 'System.Collections.Generic.List[object]'
    $rows=New-Object 'System.Collections.Generic.List[object]'
    $stack=New-Object 'System.Collections.Generic.Stack[object]'
    $summaries=@{}; [long]$seen=0; [long]$links=0; $interrupted=$false
    foreach ($root in $roots) {
        $item=[pscustomobject]@{Key=$root;Path=$root;Kind='RootSummary';Category='SelectedRoot';LogicalBytes=[long]0;Files=[long]0;DeletionAuthorized=$false;Complete=$false}
        $rows.Add($item); $summaries[$root]=$item
        $stack.Push([pscustomobject]@{Path=$root;Depth=0;Ancestors=@($root)})
    }
    while ($stack.Count -gt 0) {
        if ($clock.Elapsed.TotalSeconds -ge $MaxSeconds -or $seen -ge $MaxEntries) { $interrupted=$true; break }
        $node=$stack.Pop()
        try {
            $dir=Get-Item -LiteralPath $node.Path -Force -ErrorAction Stop
            if (($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $links++; continue }
            foreach ($entry in ([IO.DirectoryInfo]$dir).EnumerateFileSystemInfos()) {
                if ($clock.Elapsed.TotalSeconds -ge $MaxSeconds -or $seen -ge $MaxEntries) { $interrupted=$true; break }
                $seen++
                if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $links++; continue }
                if (($entry.Attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                    $ancestors=@($node.Ancestors)
                    if ($node.Depth -lt $MaxDepth) {
                        $category='NeedsReview'
                        if ($entry.Name -eq 'node_modules' -and [IO.File]::Exists((Join-Path $dir.FullName 'package.json'))) { $category='DependencyCache' }
                        elseif ($entry.Name -eq '__pycache__') { $category='GeneratedPythonCache' }
                        elseif ($entry.Name -eq '.git') { $category='RepositoryMetadata' }
                        elseif ($entry.Name -match '^(models?|checkpoints?|saves?|recordings?|downloads?|documents?)$') { $category='UserData' }
                        elseif ($entry.Name -in @('build','dist') -and ([IO.File]::Exists((Join-Path $dir.FullName 'package.json')) -or [IO.File]::Exists((Join-Path $dir.FullName 'pyproject.toml')))) { $category='BuildOutputReview' }
                        $key=$entry.FullName.TrimEnd('\') + '\'
                        $row=[pscustomobject]@{Key=$key;Path=$entry.FullName;Kind='DirectorySummary';Category=$category;LogicalBytes=[long]0;Files=[long]0;DeletionAuthorized=$false;Complete=$false}
                        $summaries[$key]=$row; $rows.Add($row); $ancestors+=@($key)
                    }
                    $stack.Push([pscustomobject]@{Path=$entry.FullName;Depth=($node.Depth+1);Ancestors=$ancestors})
                } else {
                    foreach ($key in $node.Ancestors) { $summaries[$key].LogicalBytes+=$entry.Length; $summaries[$key].Files++ }
                }
            }
        } catch { $errors.Add([pscustomobject]@{Path=$node.Path;Message=$_.Exception.Message}) }
        if ($interrupted) { break }
    }
    $complete=(-not $interrupted -and $errors.Count -eq 0)
    foreach ($row in $rows) { $row.Complete=$complete }
    if ($interrupted) { $errors.Add([pscustomobject]@{Path=$null;Message='Time or entry limit reached; sizes are lower bounds.'}) }
    $status='Succeeded'; if (-not $complete) { $status='Partial' }
    [pscustomobject]@{Name='Directories';QueryStatus=$status;Complete=$complete;Scope=[pscustomobject]@{Roots=@($roots | Sort-Object);ReportDepth=$MaxDepth;Source='local-non-reparse-logical-size/v1'};Started=$started;Finished=[DateTime]::UtcNow.ToString('o');Data=@($rows.ToArray());Errors=@($errors.ToArray());SkippedReparsePoints=$links;VisitedEntries=$seen;Meaning='Directory rows overlap their parents. Sum only disjoint RootSummary rows. Logical bytes may count hard links more than once; not reclaimable space. Classification never authorizes deletion.'}
}

function Get-MaintenanceSnapshot {
    [CmdletBinding()]
    param([ValidateSet('System','Storage','Drivers','Software','Startup','Stability','Security')][string[]]$Groups=@('System','Storage','Drivers','Software','Startup','Stability','Security'),[ValidateRange(1,60)][int]$GroupTimeoutSeconds=45,[ValidateRange(1,90)][int]$EventDays=14,[ValidateRange(1,5000)][int]$MaxEvents=200)
    $collections=New-Object 'System.Collections.Generic.List[object]'
    $principalSid=$null; $isElevated=$null; $identityError=$null; $identity=$null
    try {
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
        $principalSid=$identity.User.Value
        $principal=New-Object Security.Principal.WindowsPrincipal($identity)
        $isElevated=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { $identityError=$_.Exception.Message }
    finally { if ($null -ne $identity) { $identity.Dispose() } }
    $worker={
        param($ReadModule,$Group,$Days,$EventLimit)
        Import-Module $ReadModule -Force
        Invoke-MaintenanceRead -Name $Group -Action {
            switch ($Group) {
                'System' {
                    $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 15 -ErrorAction Stop
                    $version=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
                    [pscustomobject]@{Key='windows';Name=$os.Caption;Version=$os.Version;Build=$os.BuildNumber;UBR=$version.UBR;Architecture=$os.OSArchitecture;LastBootUtc=$os.LastBootUpTime.ToUniversalTime().ToString('o')}
                    Get-CimInstance Win32_BaseBoard -OperationTimeoutSec 15 -ErrorAction Stop | ForEach-Object { [pscustomobject]@{Key=('board/'+$_.Tag);Manufacturer=$_.Manufacturer;Model=$_.Product;Revision=$_.Version} }
                    Get-CimInstance Win32_BIOS -OperationTimeoutSec 15 -ErrorAction Stop | ForEach-Object { [pscustomobject]@{Key='bios/system';Version=$_.SMBIOSBIOSVersion;ReleaseDate=$_.ReleaseDate;Manufacturer=$_.Manufacturer} }
                    Get-CimInstance Win32_Processor -OperationTimeoutSec 15 -ErrorAction Stop | ForEach-Object { [pscustomobject]@{Key=('cpu/'+$_.DeviceID);Name=$_.Name;Cores=$_.NumberOfCores;LogicalProcessors=$_.NumberOfLogicalProcessors} }
                    Get-CimInstance Win32_PhysicalMemory -OperationTimeoutSec 15 -ErrorAction Stop | ForEach-Object { [pscustomobject]@{Key=('ram/'+$_.DeviceLocator);Manufacturer=$_.Manufacturer;PartNumber=$_.PartNumber;Capacity=$_.Capacity;ConfiguredClockSpeed=$_.ConfiguredClockSpeed} }
                    $cbs=Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' -ErrorAction Stop
                    $wu=Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' -ErrorAction Stop
                    $session=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction Stop
                    [pscustomobject]@{Key='reboot-signals';CBS=$cbs;WindowsUpdate=$wu;PendingFileRenameOperations=($null -ne $session.PendingFileRenameOperations -and @($session.PendingFileRenameOperations).Count -gt 0);Meaning='Signals only; may not cover vendor-specific reboot requirements.'}
                }
                'Storage' {
                    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -OperationTimeoutSec 15 -ErrorAction Stop | ForEach-Object { [pscustomobject]@{Key=('volume/'+$_.DeviceID);Volume=$_.DeviceID;FileSystem=$_.FileSystem;SizeBytes=$_.Size;FreeBytes=$_.FreeSpace} }
                    Get-PhysicalDisk -ErrorAction Stop | ForEach-Object { [pscustomobject]@{Key=('disk/'+$_.DeviceId);Name=$_.FriendlyName;SizeBytes=$_.Size;MediaType=[string]$_.MediaType;HealthStatus=[string]$_.HealthStatus;OperationalStatus=($_.OperationalStatus -join ',');FirmwareVersion=$_.FirmwareVersion;Meaning='Storage provider summary; not a complete SMART or load test.'} }
                }
                'Drivers' {
                    Get-CimInstance Win32_PnPSignedDriver -OperationTimeoutSec 20 -ErrorAction Stop | ForEach-Object { [pscustomobject]@{Key=$_.DeviceID;Name=$_.DeviceName;Class=$_.DeviceClass;Version=$_.DriverVersion;InfName=$_.InfName;Provider=$_.DriverProviderName;IsSigned=$_.IsSigned} }
                    Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -OperationTimeoutSec 15 -ErrorAction Stop | ForEach-Object { [pscustomobject]@{Key=('problem/'+$_.DeviceID);Name=$_.Name;ProblemCode=$_.ConfigManagerErrorCode} }
                }
                'Software' {
                    foreach ($hive in @([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryHive]::CurrentUser)) {
                        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
                            $base=$null; $uninstall=$null
                            try {
                                $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
                                $uninstall=$base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
                                if ($null -eq $uninstall) { continue }
                                foreach ($name in $uninstall.GetSubKeyNames()) {
                                    $key=$null
                                    try {
                                        $key=$uninstall.OpenSubKey($name)
                                        if ($null -eq $key) { throw "Uninstall key disappeared or is unreadable: $name" }
                                        $display=$key.GetValue('DisplayName')
                                        if (-not [string]::IsNullOrWhiteSpace($display)) { [pscustomobject]@{Key=($hive.ToString()+'/'+$view.ToString()+'/'+$name);Name=$display;Version=$key.GetValue('DisplayVersion');Publisher=$key.GetValue('Publisher');InstallLocation=$key.GetValue('InstallLocation')} }
                                    } finally { if ($null -ne $key) { $key.Dispose() } }
                                }
                            } finally { if ($null -ne $uninstall) { $uninstall.Dispose() }; if ($null -ne $base) { $base.Dispose() } }
                        }
                    }
                }
                'Startup' {
                    Get-CimInstance Win32_StartupCommand -OperationTimeoutSec 15 -ErrorAction Stop | ForEach-Object { [pscustomobject]@{Key=($_.Location+'/'+$_.User+'/'+$_.Name);Name=$_.Name;Command=$_.Command;Location=$_.Location;Meaning='Registration only; effective enabled state requires StartupApproved or application-specific verification.'} }
                    Get-ScheduledTask -ErrorAction Stop | Where-Object TaskPath -notlike '\Microsoft\*' | ForEach-Object { [pscustomobject]@{Key=('task/'+$_.TaskPath+$_.TaskName);Name=$_.TaskName;Enabled=$_.Settings.Enabled;Actions=@($_.Actions | Select-Object Execute,Arguments,WorkingDirectory)} }
                }
                'Stability' {
                    $begin=(Get-Date).AddDays(-$Days); $finish=Get-Date
                    try {
                        $events=@(Get-WinEvent -FilterHashtable @{LogName='System';Level=@(1,2);StartTime=$begin;EndTime=$finish} -MaxEvents $EventLimit -ErrorAction Stop)
                    } catch { if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { $events=@() } else { throw } }
                    foreach ($event in $events) { [pscustomobject]@{Key=('System/'+$event.RecordId);TimeUtc=$event.TimeCreated.ToUniversalTime().ToString('o');Provider=$event.ProviderName;Id=$event.Id;RecordId=$event.RecordId;Message=$event.Message;Xml=$event.ToXml()} }
                    $oldest=@(Get-WinEvent -LogName System -Oldest -MaxEvents 1 -ErrorAction Stop)
                    if ($oldest.Count -gt 0 -and $oldest[0].TimeCreated -gt $begin) { Write-Error 'Available System log starts after requested window; historical coverage is incomplete.' -ErrorAction Continue }
                    if ($events.Count -ge $EventLimit) { Write-Error 'Event limit reached; this is a bounded sample, not a complete event count.' -ErrorAction Continue }
                }
                'Security' {
                    Get-MpComputerStatus -ErrorAction Stop | ForEach-Object { [pscustomobject]@{Key='defender';AntivirusEnabled=$_.AntivirusEnabled;RealTimeProtectionEnabled=$_.RealTimeProtectionEnabled;AMProductVersion=$_.AMProductVersion;AntivirusSignatureVersion=$_.AntivirusSignatureVersion;SignatureUpdated=$_.AntivirusSignatureLastUpdated;QuickScanEndTime=$_.QuickScanEndTime} }
                }
            }
        }
    }
    foreach ($group in @($Groups | Select-Object -Unique)) {
        $start=[DateTime]::UtcNow.ToString('o'); $job=$null; $result=$null
        try {
            $job=Start-Job -ScriptBlock $worker -ArgumentList (Join-Path $PSScriptRoot 'Maintenance.ReadOnly.psm1'),$group,$EventDays,$MaxEvents -ErrorAction Stop
            $done=Wait-Job -Job $job -Timeout $GroupTimeoutSeconds
            if ($null -eq $done) {
                $result=[pscustomobject]@{Name=$group;Started=$start;Finished=[DateTime]::UtcNow.ToString('o');QueryStatus='TimedOut';Data=@();Errors=@([pscustomobject]@{Message='Collection exceeded its timeout. No partial job output is assumed complete.'})}
            } else {
                $received=@(Receive-Job -Job $job -ErrorAction Stop)
                if ($received.Count -ne 1) { throw 'Collector did not return exactly one query record.' }
                $result=$received[0]
            }
        } catch { $result=[pscustomobject]@{Name=$group;Started=$start;Finished=[DateTime]::UtcNow.ToString('o');QueryStatus='Failed';Data=@();Errors=@([pscustomobject]@{Message=$_.Exception.Message})} }
        finally { if ($null -ne $job) { if ($job.State -in @('Running','NotStarted')) { Stop-Job -Job $job }; Remove-Job -Job $job -Force } }
        $scope=[ordered]@{Source=($group+'/local-v1')}
        if ($group -in @('Software','Startup','Security')) {
            $scope['PrincipalSid']=$principalSid; $scope['IsElevated']=$isElevated
            if ($null -ne $identityError) {
                $result.QueryStatus='Partial'
                $result.Errors+=@([pscustomobject]@{Message=('Caller identity could not be established: '+$identityError)})
            }
        }
        if ($group -eq 'Software') { $scope['Coverage']='HKLM/HKCU 32/64-bit uninstall registry; excludes Store, portable applications, other users and active executable versions.' }
        if ($group -eq 'Stability') { $scope['EventDays']=$EventDays; $scope['MaxEvents']=$MaxEvents; $scope['WindowEndUtc']=$start }
        $collections.Add([pscustomobject]@{Name=$group;QueryStatus=$result.QueryStatus;Complete=($result.QueryStatus -in @('Succeeded','Empty'));Started=$result.Started;Finished=$result.Finished;Scope=[pscustomobject]$scope;Data=@($result.Data);Errors=@($result.Errors)})
    }
    [pscustomobject]@{Schema='windows-maintenance.snapshot/v1';ToolVersion='2.0.0';MachineKey=(Get-MaintenanceMachineKey);CapturedUtc=[DateTime]::UtcNow.ToString('o');Collections=@($collections.ToArray());NotCollected=@('Online update availability','Store and portable software inventory','Active application versions','Full SMART and temperatures','DISM/SFC health conclusions','Firmware update applicability','Application configuration adoption','Load stability')}
}

Export-ModuleMember -Function Get-MaintenanceSnapshot,Get-MaintenanceDirectoryInventory,Get-MaintenanceMachineKey
