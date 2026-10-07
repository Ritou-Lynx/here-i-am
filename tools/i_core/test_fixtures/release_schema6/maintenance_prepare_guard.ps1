param([Parameter(Mandatory=$true)][string]$Repository,[Parameter(Mandatory=$true)][string]$NodePath,[Parameter(Mandatory=$true)][string]$FixtureParent)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
$root=Join-Path $FixtureParent ('maintenance-prepare-'+[Guid]::NewGuid().ToString('N'));$null=[IO.Directory]::CreateDirectory($root)
$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User
function Protect([string]$P,[switch]$Directory){
 $acl=if($Directory){New-Object Security.AccessControl.DirectorySecurity}else{New-Object Security.AccessControl.FileSecurity}
 $acl.SetOwner($owner);$acl.SetAccessRuleProtection($true,$false)
 foreach($sid in @($owner,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'),[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))){
  $rule=if($Directory){[Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')}else{[Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','Allow')};$acl.AddAccessRule($rule)
 };Set-Acl -LiteralPath $P -AclObject $acl
}
function Invoke-Child([string]$Program,[string[]]$Arguments){
 $quoted=@($Arguments|ForEach-Object{if($_.Contains('"') -or $_.EndsWith('\')){throw 'fixture_argument_rejected'};'"'+$_+'"'})
 $info=New-Object Diagnostics.ProcessStartInfo;$info.FileName=$Program;$info.Arguments=$quoted -join ' ';$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process;$p.StartInfo=$info
 try{$null=$p.Start();$o=$p.StandardOutput.ReadToEndAsync();$e=$p.StandardError.ReadToEndAsync();if(!$p.WaitForExit(20000)){$p.Kill();throw 'fixture_child_timeout'};$stdout=$o.GetAwaiter().GetResult();$stderr=$e.GetAwaiter().GetResult();if(!$stdout){throw ('fixture_output_missing:'+ $stderr)};return @{exit=$p.ExitCode;result=($stdout|ConvertFrom-Json)}}finally{$p.Dispose()}
}
$guard=$null
try{
 Protect $root -Directory
 $maintenance=Join-Path $root 'tools\i_core\maintenance';$package=Join-Path $root 'tools\i_core\release_schema6';$null=[IO.Directory]::CreateDirectory($maintenance);$null=[IO.Directory]::CreateDirectory($package)
 $files=@('prepare-production-login.ps1','prepare-production-login.mjs','prepare_live_guard.ps1','maintenance_window.ps1','maintenance_outputs.mjs','acl_receipt.mjs','register-approved-login.ps1','register_task_primitives.ps1','task_security_policy.ps1')
 $pins=@();foreach($name in $files){$p=Join-Path $maintenance $name;Copy-Item -LiteralPath (Join-Path $Repository ('tools\i_core\maintenance\'+$name)) -Destination $p;Protect $p;$pins+=@{path=$p;sha256=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}}
 $p=Join-Path $package 'package.mjs';Copy-Item -LiteralPath (Join-Path $Repository 'tools\i_core\release_schema6\package.mjs') -Destination $p;Protect $p;$pins+=@{path=$p;sha256=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
 $private=Join-Path $root 'private';$null=[IO.Directory]::CreateDirectory($private);Protect $private -Directory
 $configPath=Join-Path $private 'config.json'
 # The deliberately invalid next-stage hash proves the second process gets
 # beyond guard acquisition, without reading any production-like inputs.
 $config=@{format='schema6-maintenance-login-config-v2';ownerSid=$owner.Value;windowId='synthetic-prepare';maintenanceRoot=$private;maintenanceFiles=$pins;frozenReceiptPath=(Join-Path $private 'never-read.json');frozenReceiptSha256='invalid'}
 foreach($key in @('ownerApproval','aclReceipt','approvedXml','loginConfiguration')){$config[$key+'Path']=Join-Path $private ($key+'.never');$config[$key+'Sha256']='invalid'}
 [IO.File]::WriteAllText($configPath,($config|ConvertTo-Json -Depth 10));Protect $configPath;$configHash=(Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash.ToLowerInvariant()
 . (Join-Path $maintenance 'maintenance_window.ps1')
 $guardPath=Join-Path $private 'active-window.guard';[IO.File]::WriteAllText($guardPath,'preserved');Protect $guardPath
 $guard=Acquire-MaintenanceGuard $private
 $first=Invoke-Child $NodePath @((Join-Path $maintenance 'prepare-production-login.mjs'),'--config',$configPath,'--config-sha256',$configHash)
 if($first.exit-ne 2 -or $first.result.passed-ne $false){throw 'standalone_cli_accepted_concurrent_guard'}
 $guard.Dispose();$guard=$null
 $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $second=Invoke-Child $ps @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $maintenance 'prepare-production-login.ps1'),'-ConfigPath',$configPath,'-ExpectedConfigSha256',$configHash)
 if($second.exit-ne 2 -or $second.result.code-cne 'prepare_hash_required'){throw ('standalone_cli_not_released:'+ $second.result.code)}
 if([IO.File]::ReadAllText($guardPath)-cne 'preserved' -or (Test-Path -LiteralPath $config.frozenReceiptPath)){throw 'fixture_evidence_changed'}
 @{passed=$true;standaloneCliContentionRejected=$true;releasedGuardReachedNextGate=$true;guardBytesPreserved=$true;noReceiptWritten=$true;tasksCreated=0}|ConvertTo-Json -Compress
}finally{
 if($guard){$guard.Dispose()}
 $resolved=[IO.Path]::GetFullPath($root);$temp=[IO.Path]::GetFullPath($FixtureParent).TrimEnd('\')+'\'
 if($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('maintenance-prepare-')){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
