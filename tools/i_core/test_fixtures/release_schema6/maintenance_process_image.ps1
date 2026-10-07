param([Parameter(Mandatory=$true)][string]$Repository,[Parameter(Mandatory=$true)][string]$FixtureRoot,[Parameter(Mandatory=$true)][string]$NodePath)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
$module=Join-Path $Repository 'tools\i_core\maintenance\process_image_binding.ps1'
$priorModulePath=$env:PSModulePath
. $module
. $module
$result=[ordered]@{}
$result.importSafe=(!( 'ProcessImageBindingNative' -as [type]) -and $env:PSModulePath -ceq $priorModulePath)
function Check([string]$Name,[bool]$Value){if(!$Value){throw ('assertion_failed:'+ $Name)};$result[$Name]=$true}
function Rejected([string]$Name,[scriptblock]$Action,[string]$Code){$caught=$false;try{& $Action|Out-Null}catch{if($_.Exception.ToString().Contains($Code)){$caught=$true}else{throw}};Check $Name $caught}
$hash='a'*64;$ti='S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
$policy=@{Path='C:\Windows\System32\conhost.exe';FinalPath='\\?\C:\Windows\System32\conhost.exe';Sha256=$hash;ExpectedSha256=$hash;SystemRoot='C:\Windows';OwnerSid=$ti;HardlinkCount=2}
Check 'systemHardlinkTwoAccepted' (Assert-ProcessImagePolicy @policy)
$copy=$policy.Clone();$copy.OwnerSid='S-1-5-18';Rejected 'systemOwnerRejected' {Assert-ProcessImagePolicy @copy} 'process_image_system_owner_rejected'
$copy=$policy.Clone();$copy.FinalPath='\\?\C:\Windows\WinSxS\conhost.exe';Rejected 'systemAliasRejected' {Assert-ProcessImagePolicy @copy} 'process_image_path_alias'
$copy=$policy.Clone();$copy.Sha256='b'*64;Rejected 'systemHashRejected' {Assert-ProcessImagePolicy @copy} 'process_image_hash_mismatch'
$copy=$policy.Clone();$copy.HasReparsePoint=$true;Rejected 'systemReparseRejected' {Assert-ProcessImagePolicy @copy} 'process_image_reparse_path'
$copy=$policy.Clone();$copy.Path='c:\windows\System32\conhost.exe';$copy.FinalPath='\\?\'+$copy.Path;$copy.OwnerSid='S-1-5-18';Rejected 'systemCaseCannotBypassOwner' {Assert-ProcessImagePolicy @copy} 'process_image_system_owner_rejected'
$copy=$policy.Clone();$copy.Path='C:\WindowsExtra\node.exe';$copy.FinalPath='\\?\'+$copy.Path;$copy.OwnerSid='S-1-5-18';Check 'systemSeparatorBoundary' (!(Assert-ProcessImagePolicy @copy))
foreach($bad in @('C:\Windows\System32\..\System32\conhost.exe','C:\Windows\System32\conhost.exe:stream','C:\Windows\System32\conhost.exe.','C:/Windows/System32/conhost.exe')){
 $copy=$policy.Clone();$copy.Path=$bad;Rejected ('canonicalRejected'+$result.Count) {Assert-ProcessImagePolicy @copy} 'process_image_noncanonical_path'
}
# Read-only check of a Windows-owned multi-link system image. No live process inspected.
$systemExe=Join-Path $env:SystemRoot 'System32\conhost.exe'
$systemHash=(Get-FileHash -LiteralPath $systemExe -Algorithm SHA256).Hash.ToLowerInvariant()
$pin=Assert-ProcessImageFile $systemExe $systemHash
try{Check 'realSystemImageAccepted' ($pin.is_system_image -and $pin.hardlink_count -ge 1);$result.realSystemHardlinkCount=[long]$pin.hardlink_count}finally{$pin.lease.Dispose()}
$synthetic=Join-Path $FixtureRoot 'synthetic-image.bin';[IO.File]::WriteAllText($synthetic,'synthetic image bytes')
$syntheticHash=(Get-FileHash -LiteralPath $synthetic -Algorithm SHA256).Hash.ToLowerInvariant()
$alias=Join-Path $FixtureRoot 'synthetic-image-link.bin';$null=New-Item -ItemType HardLink -Path $alias -Target $synthetic
$pin=Assert-ProcessImageFile $synthetic $syntheticHash
try{
 Check 'nonSystemHardlinkAccepted' (!$pin.is_system_image -and $pin.hardlink_count -eq 2)
 Rejected 'leaseBlocksWrite' {[IO.File]::Open($synthetic,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite).Dispose()} 'IOException'
 Rejected 'leaseBlocksAliasWrite' {[IO.File]::Open($alias,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite).Dispose()} 'IOException'
 Rejected 'leaseBlocksDelete' {[IO.File]::Delete($synthetic)} 'IOException'
}finally{$pin.lease.Dispose()}
Rejected 'wrongHashRejected' {Assert-ProcessImageFile $synthetic ('b'*64)} 'process_image_hash_mismatch'
$write=[IO.File]::Open($synthetic,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None);$write.Dispose();Check 'failedPinReleasesLease' $true
$realDirectory=Join-Path $FixtureRoot 'image-directory';$null=New-Item -ItemType Directory -Path $realDirectory
$junction=Join-Path $FixtureRoot 'image-directory-alias';$null=New-Item -ItemType Junction -Path $junction -Target $realDirectory
$realImage=Join-Path $realDirectory 'image.bin';[IO.File]::WriteAllText($realImage,'synthetic image bytes')
Rejected 'nativeJunctionRejected' {Assert-ProcessImageFile (Join-Path $junction 'image.bin') $syntheticHash} 'process_image_reparse_path'
$childPath=Join-Path $FixtureRoot 'synthetic-node.exe';Copy-Item -LiteralPath $NodePath -Destination $childPath
$childHash=(Get-FileHash -LiteralPath $childPath -Algorithm SHA256).Hash.ToLowerInvariant()
$child=$null
try{
 $child=Start-Process -FilePath $childPath -ArgumentList '-e','setTimeout(()=>{},60000)' -WindowStyle Hidden -PassThru
 $row=Get-CimInstance Win32_Process -Filter ('ProcessId='+$child.Id) -Property ProcessId,ParentProcessId,ExecutablePath,CreationDate
 $allowed=@{};$allowed[$childPath.ToLowerInvariant()]=$childHash
 $bound=Get-BoundProcessIdentity -Row $row -AllowedImages $allowed
 Check 'realSyntheticProcessBound' ($bound.pid -eq $child.Id -and $bound.path -ieq $childPath -and $bound.sha256 -ceq $childHash)
 $base=[DateTime]::new([long]$bound.started_ticks,[DateTimeKind]::Utc)
 $fake=[pscustomobject]@{ProcessId=$child.Id;ParentProcessId=$row.ParentProcessId;ExecutablePath=$row.ExecutablePath;CreationDate=$base.AddTicks(-9)}
 Check 'cimNineTicksAccepted' ((Get-BoundProcessIdentity $fake $allowed).pid -eq $child.Id)
 $fake.CreationDate=$base.AddTicks(9);Check 'cimPositiveNineTicksAccepted' ((Get-BoundProcessIdentity $fake $allowed).pid -eq $child.Id)
 $fake.CreationDate=$base.AddTicks(-10);Rejected 'cimTenTicksRejected' {Get-BoundProcessIdentity $fake $allowed} 'process_image_cim_creation_mismatch'
 $fake.CreationDate=$base.AddSeconds(-1);Rejected 'reusedPidCreationRejected' {Get-BoundProcessIdentity $fake $allowed} 'process_image_cim_creation_mismatch'
 $fake.CreationDate=$base;$fake.ExecutablePath=$systemExe;Rejected 'cimPathRejected' {Get-BoundProcessIdentity $fake $allowed} 'process_image_cim_path_mismatch'
 Rejected 'unapprovedProcessRejected' {Get-BoundProcessIdentity $row @{}} 'process_image_unapproved_image'
 $badAllowed=@{};$badAllowed[$childPath.ToLowerInvariant()]='b'*64;Rejected 'processHashRejected' {Get-BoundProcessIdentity $row $badAllowed} 'process_image_hash_mismatch'
 $held=[ProcessImageBindingNative]::Open($child.Id)
 try{$child.Kill();$child.WaitForExit();Rejected 'exitedHeldProcessRejected' {$held.Inspect()} 'process_image_process_exited'}finally{$held.Dispose()}
}finally{if($child){if(!$child.HasExited){$child.Kill();$child.WaitForExit()};$child.Dispose()}}
$result.tasksCreated=0;$result.passed=$true
$result|ConvertTo-Json -Compress


