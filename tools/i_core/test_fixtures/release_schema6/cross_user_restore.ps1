[CmdletBinding()]
param([string]$ProductionRoot='',[string]$NodePath='',[string]$OutputReport='',[switch]$GuardOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'cross_user_restore_common.ps1')
# No account, service, directory, pipe, or process action precedes this gate.
try { Assert-CrossUserCI -Parent } catch { [Console]::Error.WriteLine('cross_user_restore_rejected:hosted_runner_required');exit 2 }
if($GuardOnly){[Console]::Out.WriteLine('{"hostedGuardPassed":true}');exit 0}
if(-not $ProductionRoot){$ProductionRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))}
$account=$null;$createdSid=$null;$child=$null;$job=$null;$pipe=$null;$secret=$null;$credentialSecret=$null;$previousTokenOwner=$null
$serviceStarted=$false;$cleanupOk=$true;$passed=$false;$childStarted=$false;$childAssigned=$false;$phase='setup';$result=$null;$failureDiagnostic=$null;$clock=[Diagnostics.Stopwatch]::StartNew()
try {
 if(-not $OutputReport -or (Test-Path -LiteralPath $OutputReport)){throw 'fresh_report_required'}
 if(-not $NodePath){$NodePath=(Get-Command node.exe -ErrorAction Stop).Source}
 $NodePath=[IO.Path]::GetFullPath($NodePath)
 Initialize-CrossUserNative
 $originSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 # CI-only process-token default owner; inherited factory children create files
 # as runneradmin, not Administrators. Original token owner is restored below.
 $previousTokenOwner=[CrossUserTokenOwner]::Set($originSid)
 $root=Join-Path $env:ProgramData ('s6-cross-user-'+[Guid]::NewGuid().ToString('N'))
 [IO.Directory]::CreateDirectory($root)|Out-Null;Set-CrossUserDirectoryAcl $root $originSid
 $factory=Join-Path $root 'factory';[IO.Directory]::CreateDirectory($factory)|Out-Null;Set-CrossUserDirectoryAcl $factory $originSid
 $secret=New-Object byte[] 48;$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
 try{$rng.GetBytes($secret)}finally{$rng.Dispose()};for($i=0;$i -lt $secret.Length;$i++){$secret[$i]=33+($secret[$i]%90)}
 $phase='factory'
 $factoryReport=Invoke-CrossUserNode $NodePath (Join-Path $PSScriptRoot 'cross_user_restore.mjs') 'factory' $ProductionRoot $factory $secret
 if($factoryReport.factoryVerified -ne $true){throw 'factory_unverified'}
 $transfer=Join-Path $factory 'transfer'
 $transport=Get-Content -LiteralPath (Join-Path $transfer 'transport.json') -Raw|ConvertFrom-Json
 foreach($name in @('cross_user_restore.mjs','cross_user_restore_common.ps1','cross_user_restore_child.ps1')) {
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $transfer
  $transport.files+=@{name=$name;sha256=(Get-FileHash -LiteralPath (Join-Path $transfer $name) -Algorithm SHA256).Hash.ToLowerInvariant()}
 }
 [IO.File]::WriteAllText((Join-Path $transfer 'transport.json'),($transport|ConvertTo-Json -Depth 6 -Compress),[Text.UTF8Encoding]::new($false))
 $transportHash=(Get-FileHash -LiteralPath (Join-Path $transfer 'transport.json') -Algorithm SHA256).Hash.ToLowerInvariant()
 $phase='temporary_account_prepare'
 $account='s6cu_'+[Guid]::NewGuid().ToString('N').Substring(0,12)
 if(Get-LocalUser -Name $account -ErrorAction SilentlyContinue){throw 'account_collision'}
 $credentialSecret=New-Object Security.SecureString
 foreach($c in 'Ci9!'.ToCharArray()){$credentialSecret.AppendChar($c)}
 $random=New-Object byte[] 40;$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
 try{$rng.GetBytes($random);foreach($b in $random){$credentialSecret.AppendChar([char](33+($b%90)))}}finally{[Array]::Clear($random,0,$random.Length);$rng.Dispose()}
 $credentialSecret.MakeReadOnly()
 $phase='temporary_account_create'
 $created=New-LocalUser -Name $account -Password $credentialSecret -Description 'Disposable schema6 hosted CI synthetic restore' -AccountExpires (Get-Date).AddHours(1)
 $createdSid=$created.SID.Value
 $phase='temporary_account_users_group'
 Add-LocalGroupMember -SID ([Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')) -Member $created
 # The child asserts its actual token has neither Administrators SID nor role.
 # Do not enumerate unrelated hosted-machine group members/name mappings.
 # Only the transfer subtree is readable by the new user. Sources and original
 # backup keys are never sent; no DPAPI key directory is created or consulted.
 $phase='acl_root_read'
 Set-CrossUserDirectoryAcl $root $originSid $createdSid
 $phase='acl_factory_read'
 Set-CrossUserDirectoryAcl $factory $originSid $createdSid
 $phase='acl_source_private'
 Set-CrossUserDirectoryAcl (Join-Path $factory 'source') $originSid
 $phase='acl_archive_private'
 Set-CrossUserDirectoryAcl (Join-Path $factory 'archive') $originSid
 $phase='acl_transfer_read'
 Set-CrossUserDirectoryAcl $transfer $originSid $createdSid
 # Delegate only an empty CI sandbox; the standard user creates its own private
 # child directory. Avoid depending on assigning a foreign owner from admin.
 $phase='acl_child_parent_create'
 $childParent=Join-Path $root 'second-user';[IO.Directory]::CreateDirectory($childParent)|Out-Null;Set-CrossUserDirectoryAcl $childParent $originSid
 $phase='acl_child_delegate'
 $childAcl=Get-Acl -LiteralPath $childParent
 $childAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($createdSid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
 Set-Acl -LiteralPath $childParent -AclObject $childAcl
 $workspace=Join-Path $childParent 'private'
 $phase='secondary_logon_query'
 $service=Get-Service -Name seclogon
 if($service.Status -ne 'Running'){$phase='secondary_logon_start';Start-Service -Name seclogon;$serviceStarted=$true}
 $phase='cross_user_pipe_setup'
 $pipeName='s6-cross-user-'+[Guid]::NewGuid().ToString('N')
 $security=New-Object IO.Pipes.PipeSecurity;$security.SetAccessRuleProtection($true,$false)
 foreach($sid in @($originSid,$createdSid)){$security.AddAccessRule([IO.Pipes.PipeAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),[IO.Pipes.PipeAccessRights]::ReadWrite,[Security.AccessControl.AccessControlType]::Allow))}
 $pipe=[IO.Pipes.NamedPipeServerStream]::new($pipeName,[IO.Pipes.PipeDirection]::InOut,1,[IO.Pipes.PipeTransmissionMode]::Byte,[IO.Pipes.PipeOptions]::Asynchronous,4096,4096,$security)
 $connected=$pipe.WaitForConnectionAsync();$job=New-Object CrossUserJob
 $ps=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
 $launchArgs=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $transfer 'cross_user_restore_child.ps1'),'-Transfer',$transfer,'-Workspace',$workspace,'-PipeName',$pipeName,'-ServerPid',"$PID",'-OriginalSid',$originSid,'-ExpectedSid',$createdSid,'-TransportSha256',$transportHash)
 $quoted=($launchArgs|ForEach-Object{if($_.Contains('"') -or $_.EndsWith('\')){throw 'ci_argument_rejected'};'"'+$_+'"'}) -join ' '
 # Explicit environment block for the alternate-credential process. Do not
 # inherit runner tokens or rely on the credential logon environment defaults.
 $startInfo=[Diagnostics.ProcessStartInfo]::new()
 $startInfo.FileName=$ps;$startInfo.Arguments=$quoted;$startInfo.WorkingDirectory=$childParent
 $startInfo.UseShellExecute=$false;$startInfo.CreateNoWindow=$true;$startInfo.WindowStyle='Hidden'
 $startInfo.UserName=$account;$startInfo.Domain=$env:COMPUTERNAME;$startInfo.Password=$credentialSecret;$startInfo.LoadUserProfile=$true
 $startInfo.EnvironmentVariables.Clear()
 foreach($key in @('OS','GITHUB_ACTIONS','RUNNER_ENVIRONMENT','RUNNER_OS','SystemRoot','WINDIR')){$startInfo.EnvironmentVariables[$key]=[Environment]::GetEnvironmentVariable($key)}
 $startInfo.EnvironmentVariables['TEMP']=$childParent;$startInfo.EnvironmentVariables['TMP']=$childParent
 $child=[Diagnostics.Process]::new();$child.StartInfo=$startInfo
 $phase='cross_user_process_start'
 if(-not $child.Start()){throw 'ci_process_start_failed'};$childStarted=$true
 # The child waits for our frame. Assign before transmitting any password or
 # permitting it to start Node; all descendants inherit kill-on-close ownership.
 $phase='cross_user_job_assign'
 $job.Add($child);$childAssigned=$true
 $phase='cross_user_pipe_connect'
 if(-not $connected.Wait(60000)){throw 'ci_pipe_timeout'}
 $phase='cross_user_pipe_identity'
 [uint32]$clientPid=0
 if(-not [CrossUserJob]::GetNamedPipeClientProcessId($pipe.SafePipeHandle,[ref]$clientPid) -or $clientPid -ne $child.Id){throw 'ci_pipe_client_mismatch'}
 $phase='cross_user_secret_frame'
 $writer=[IO.BinaryWriter]::new($pipe,[Text.Encoding]::UTF8,$true);$writer.Write([int]$secret.Length);$writer.Write($secret);$writer.Flush()
 function Read-FrameBytes([int]$Length) {
  $buffer=New-Object byte[] $Length;$offset=0
  while($offset -lt $Length){$read=$pipe.ReadAsync($buffer,$offset,$Length-$offset);if(-not $read.Wait(180000)){throw 'ci_report_timeout'};$count=$read.Result;if($count -le 0){throw 'ci_report_truncated'};$offset+=$count}
  return ,$buffer
 }
 $phase='cross_user_restore_report'
 $header=Read-FrameBytes 4;$length=[BitConverter]::ToInt32($header,0);if($length -le 0 -or $length -gt 65536){throw 'ci_report_size'}
 $result=[Text.Encoding]::UTF8.GetString((Read-FrameBytes $length))|ConvertFrom-Json
 $phase='cross_user_process_exit'
 if(-not $child.WaitForExit(30000) -or $child.ExitCode -ne 0 -or -not $job.Empty()){throw 'ci_process_close_unconfirmed'}
 $phase='cross_user_evidence'
 if($result.standardUserToken -ne $true){throw 'standard_user_required'}
 if($result.distinctWindowsSid -ne $true -or $result.sourceSidSha256 -ne (Get-CrossUserHash $originSid) -or $result.restoreSidSha256 -ne (Get-CrossUserHash $createdSid) -or $result.sourceSidSha256 -eq $result.restoreSidSha256 -or $result.passwordOnly -ne $true -or $result.dpapiUsed -ne $false -or $result.realCoreVerified -ne $true -or $result.deniedRouteCount -ne 5 -or $result.databaseBytesUnchanged -ne $true -or $result.databaseFingerprintSha256 -ne $factoryReport.databaseFingerprintSha256){throw 'ci_evidence_rejected'}
 $passed=$true
} catch { $passed=$false;$failureDiagnostic=Get-CrossUserSafeError $_ }
finally {
 if($pipe){$pipe.Dispose()}
 if($childStarted -and -not $childAssigned){try{if(-not [CrossUserJob]::StopUnassigned($child)){$cleanupOk=$false}}catch{$cleanupOk=$false}}
 if($job){try{if(-not $job.Stop()){$cleanupOk=$false}}catch{$cleanupOk=$false};$job.Dispose()}
 if($child){if($childStarted){try{if(-not $child.WaitForExit(15000)){$cleanupOk=$false}}catch{$cleanupOk=$false}};$child.Dispose()}
 if($createdSid){
  try {
   $current=Get-LocalUser -Name $account -ErrorAction Stop
   if($current.SID.Value -ne $createdSid -or $account -notmatch '^s6cu_[a-f0-9]{12}$' -or -not $cleanupOk){throw 'ci_cleanup_identity_or_process_unconfirmed'}
   Remove-LocalUser -SID ([Security.Principal.SecurityIdentifier]::new($createdSid))
   if(Get-LocalUser -SID ([Security.Principal.SecurityIdentifier]::new($createdSid)) -ErrorAction SilentlyContinue){throw 'ci_account_delete_unconfirmed'}
  } catch {$cleanupOk=$false}
 }
 if($serviceStarted){try{Stop-Service -Name seclogon -ErrorAction Stop}catch{$cleanupOk=$false}}
 if($secret){[Array]::Clear($secret,0,$secret.Length)};if($credentialSecret){$credentialSecret.Dispose()}
 if($previousTokenOwner){try{[void][CrossUserTokenOwner]::Set($previousTokenOwner)}catch{$cleanupOk=$false}}
}
$safe=@{passed=($passed -and $cleanupOk);cleanupConfirmed=$cleanupOk;accountCreated=($null -ne $createdSid);crossMachineTested=$false;elapsedMilliseconds=$clock.ElapsedMilliseconds;failurePhase=$(if($passed -and $cleanupOk){'none'}else{$phase})}
if($failureDiagnostic){$safe.failureDiagnostic=$failureDiagnostic}
if($passed){foreach($p in $result.PSObject.Properties){$safe[$p.Name]=$p.Value}}
try {
 if(-not $OutputReport -or (Test-Path -LiteralPath $OutputReport)){throw 'fresh_report_required'}
 $parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($OutputReport));[IO.Directory]::CreateDirectory($parent)|Out-Null
 $out=[IO.File]::Open($OutputReport,'CreateNew','Write','None');try{$bytes=[Text.Encoding]::UTF8.GetBytes(($safe|ConvertTo-Json -Depth 5 -Compress));$out.Write($bytes,0,$bytes.Length);$out.Flush($true)}finally{$out.Dispose()}
 [Console]::Out.WriteLine(($safe|ConvertTo-Json -Depth 5 -Compress))
}catch{[Console]::Error.WriteLine('cross_user_report_failed');exit 2}
if(-not $safe.passed){exit 1}
