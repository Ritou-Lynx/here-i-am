param([Parameter(Mandatory=$true)][string]$Transfer,[Parameter(Mandatory=$true)][string]$Workspace,[Parameter(Mandatory=$true)][string]$PipeName,[Parameter(Mandatory=$true)][int]$ServerPid,[Parameter(Mandatory=$true)][string]$OriginalSid,[Parameter(Mandatory=$true)][string]$ExpectedSid,[Parameter(Mandatory=$true)][string]$TransportSha256)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'cross_user_restore_common.ps1')
$pipe=$null;$passwordBytes=$null;$exitCode=2;$phase='child_hosted_guard'
try {
 Assert-CrossUserCI
 $phase='child_identity'
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 $sid=$identity.User.Value
 if($sid -ne $ExpectedSid -or $sid -eq $OriginalSid){throw 'ci_identity_mismatch'}
 $phase='child_standard_token'
 # Check actual token groups, including deny-only Administrators membership.
 if(@($identity.Groups|ForEach-Object{$_.Value}) -contains 'S-1-5-32-544' -or ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'standard_user_required'}
 # Set compiler TEMP before Add-Type; credentials may inherit runneradmin TEMP.
 $phase='child_workspace_create'
 if(Test-Path -LiteralPath $Workspace){throw 'ci_fresh_output_required'}
 [IO.Directory]::CreateDirectory($Workspace)|Out-Null
 $phase='child_workspace_owner'
 if((Get-Acl -LiteralPath $Workspace).GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid){throw 'ci_output_owner_mismatch'}
 $phase='child_workspace_acl'
 Set-CrossUserDirectoryAcl $Workspace $sid
 $env:TEMP=$Workspace;$env:TMP=$Workspace
 $phase='child_pipe_connect'
 $pipe=[IO.Pipes.NamedPipeClientStream]::new('.',$PipeName,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
 $pipe.Connect(60000)
 $phase='child_secret_frame'
 $reader=[IO.BinaryReader]::new($pipe,[Text.Encoding]::UTF8,$true)
 $size=$reader.ReadInt32();if($size -ne 48){throw 'ci_secret_frame_rejected'}
 $passwordBytes=$reader.ReadBytes($size);if($passwordBytes.Length -ne $size){throw 'ci_secret_frame_truncated'}
 # Parent sends the frame only after Job assignment. No compiler/Node child is
 # created before this gate, so assignment failure can reap this exact process.
 $phase='child_native_initialize'
 Initialize-CrossUserNative
 $phase='child_pipe_server_identity'
 [uint32]$actualServer=0
 if(-not [CrossUserJob]::GetNamedPipeServerProcessId($pipe.SafePipeHandle,[ref]$actualServer) -or $actualServer -ne $ServerPid){throw 'ci_pipe_server_mismatch'}
 # The standard user itself owns the private directory and all copies.
 $phase='child_transport_anchor'
 if((Get-FileHash -LiteralPath (Join-Path $Transfer 'transport.json') -Algorithm SHA256).Hash -ne $TransportSha256){throw 'ci_transport_anchor_mismatch'}
 $phase='child_copy'
 Copy-Item -LiteralPath (Join-Path $Transfer 'runtime') -Destination $Workspace -Recurse
 Copy-Item -LiteralPath (Join-Path $Transfer 'payload') -Destination $Workspace -Recurse
 Copy-Item -LiteralPath (Join-Path $Transfer 'transport.json') -Destination $Workspace
 foreach($name in @('cross_user_restore.mjs','cross_user_restore_common.ps1','cross_user_restore_child.ps1')){Copy-Item -LiteralPath (Join-Path $Transfer $name) -Destination $Workspace}
 # Copy creates current-user-owned files; source-account DPAPI paths are absent.
 $phase='child_copied_owner'
 foreach($item in Get-ChildItem -LiteralPath $Workspace -Recurse -Force){if((Get-Acl -LiteralPath $item.FullName).GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $sid){throw 'ci_copied_owner_mismatch'}}
 $phase='child_restore_inspection'
 $report=Invoke-CrossUserNode (Join-Path $Workspace 'runtime/runtime/node.exe') (Join-Path $Workspace 'cross_user_restore.mjs') 'restore' (Join-Path $Workspace 'runtime') $Workspace $passwordBytes
 $report|Add-Member -NotePropertyName distinctWindowsSid -NotePropertyValue $true
 $report|Add-Member -NotePropertyName standardUserToken -NotePropertyValue $true
 $report|Add-Member -NotePropertyName sourceSidSha256 -NotePropertyValue (Get-CrossUserHash $OriginalSid)
 $report|Add-Member -NotePropertyName restoreSidSha256 -NotePropertyValue (Get-CrossUserHash $sid)
 $phase='child_report_frame'
 $bytes=[Text.Encoding]::UTF8.GetBytes(($report|ConvertTo-Json -Compress))
 $writer=[IO.BinaryWriter]::new($pipe,[Text.Encoding]::UTF8,$true);$writer.Write([int]$bytes.Length);$writer.Write($bytes);$writer.Flush()
 $exitCode=0
} catch { [Console]::Error.WriteLine((@{childRejected=$true;failurePhase=$phase;failureDiagnostic=(Get-CrossUserSafeError $_)}|ConvertTo-Json -Depth 4 -Compress)) }
finally {if($passwordBytes){[Array]::Clear($passwordBytes,0,$passwordBytes.Length)};if($pipe){$pipe.Dispose()}}
exit $exitCode
