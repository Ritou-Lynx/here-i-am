[CmdletBinding()]
param([string]$TaskName)

# Import only the existing, import-safe session locator. No task mutation or stop.
. (Join-Path $PSScriptRoot 'stop-schema6-session.ps1') -TaskName $TaskName

function Write-Schema6PairingFile([string]$Path,[byte[]]$Bytes) {
 $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try {$stream.Write($Bytes,0,$Bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
}
function Invoke-Schema6PairingWindow([string]$TaskName) {
 $binding=Get-Schema6LoginBinding $TaskName
 Assert-Schema6NoRecovery $binding
 $sessions=@(Get-Schema6LiveSessions $binding)
 try {
  if($sessions.Count -ne 1){throw 'pair_single_live_session_required'}
  $session=$sessions[0]
  if($session.Window.manifest_sha256 -cne $binding.Login.manifest_sha256){throw 'pair_session_manifest_mismatch'}
  . (Join-Path $binding.Login.release_directory 'tools\i_core\release_schema6\lifecycle\protected_paths.ps1')
  Assert-ProtectedPath $session.Directory -Root
  $live=@()
  foreach($directory in @(Get-ChildItem -LiteralPath $session.Directory -Directory -Filter 'control-*')){
   $readyPath=Join-Path $directory.FullName 'ready.json'
   if(-not (Test-Path -LiteralPath $readyPath) -or (Test-Path -LiteralPath (Join-Path $directory.FullName 'child.json'))){continue}
   Assert-ProtectedPath $directory.FullName -Root
   $launch=Read-Schema6Json (Join-Path $directory.FullName 'launch.json')
   $ready=Read-Schema6Json $readyPath
   if($launch.token -cnotmatch '^[a-f0-9]{64}$' -or $ready.token -cne $launch.token -or $launch.manifest_sha256 -cne $binding.Login.manifest_sha256 -or $ready.manifest_sha256 -cne $launch.manifest_sha256 -or $ready.configuration_sha256 -cne $binding.Login.core_configuration_sha256 -or $launch.configuration_file -cne $binding.Login.core_configuration_path -or $launch.state -cne $binding.Login.state_directory -or $launch.release -cne $binding.Login.release_directory -or $launch.owner_sid -cne $binding.Login.owner_sid -or $launch.mode -cnotin @('start','initialize-empty')){throw 'pair_control_binding_mismatch'}
   $marker=Read-Schema6Json (Join-Path $binding.Login.state_directory 's6-lifecycle.json')
   if($marker.format -cne 'schema6-lifecycle-v1' -or $marker.phase -cne 'listening' -or $marker.token -cne $launch.token -or $marker.manifest_sha256 -cne $launch.manifest_sha256 -or $marker.configuration_sha256 -cne $ready.configuration_sha256 -or (Test-Path -LiteralPath (Join-Path $directory.FullName 'close')) -or (Test-Path -LiteralPath (Join-Path $directory.FullName 'stop'))){throw 'pair_core_not_listening'}
   $process=$null
   try {
    $process=[Diagnostics.Process]::GetProcessById([int]$ready.pid)
    $image=Join-Path $binding.Login.release_directory 'runtime\node.exe'
    if($process.HasExited -or -not $process.MainModule.FileName.Equals($image,[StringComparison]::OrdinalIgnoreCase) -or $process.StartTime.ToUniversalTime().Ticks -gt (Get-Item -LiteralPath $readyPath).LastWriteTimeUtc.Ticks){throw 'pair_core_process_not_live'}
   } catch {throw 'pair_core_process_not_live'} finally {if($process){$process.Dispose()}}
   $live += [pscustomobject]@{Directory=$directory.FullName;Token=$launch.token;Manifest=$launch.manifest_sha256}
  }
  if($live.Count -ne 1){throw 'pair_single_live_control_required'}
  $control=$live[0]
  $codePath=Join-Path $control.Directory 'pair.code'
  $requestPath=Join-Path $control.Directory 'pair.request'
  $codePending=$codePath+'.pending';$requestPending=$requestPath+'.pending'
  foreach($p in @($codePath,$requestPath,$codePending,$requestPending)){
   $null=Assert-Schema6PlainPath $p
   if(Test-Path -LiteralPath $p){throw 'pair_unhandled_request_exists'}
  }
  $keyPath=Join-Path $control.Directory 'stop.key';Assert-ProtectedPath $keyPath
  $key=[Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText($keyPath))
  $random=New-Object byte[] 32;$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
  try {$rng.GetBytes($random)} finally {$rng.Dispose()}
  $code=([BitConverter]::ToString($random)).Replace('-','').ToLowerInvariant()
  $sha=[Security.Cryptography.SHA256]::Create()
  try {$codeHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($code)))).Replace('-','').ToLowerInvariant()} finally {$sha.Dispose()}
  $expires=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+600000
  $hmac=New-Object Security.Cryptography.HMACSHA256
  try {$hmac.Key=$key;$message=$control.Token+'|'+$control.Manifest+'|pair|'+$codeHash+'|'+$expires.ToString([Globalization.CultureInfo]::InvariantCulture);$authentication=([BitConverter]::ToString($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($message)))).Replace('-','').ToLowerInvariant()} finally {$hmac.Dispose();[Array]::Clear($key,0,$key.Length)}
  $json=@{hmac=$authentication;expires_at_ms=$expires}|ConvertTo-Json -Compress
  # Exclusive reservation also prevents the 25ms consumer from mistaking the
  # first rename for an abandoned code. Both published files are atomic/new.
  $requestStaging=Join-Path $control.Directory ('pair-request-'+[Guid]::NewGuid().ToString('N')+'.tmp')
  $reserved=$false;$publishedCode=$false
  try {
   # Publish a fully flushed reservation; consumers never see a partial write.
   Write-Schema6PairingFile $requestStaging ([Text.Encoding]::UTF8.GetBytes($json))
   [IO.File]::Move($requestStaging,$requestPending);$reserved=$true
   Write-Schema6PairingFile $codePending ([Text.Encoding]::UTF8.GetBytes($code))
   [IO.File]::Move($codePending,$codePath);$publishedCode=$true
   [IO.File]::Move($requestPending,$requestPath)
   return $code
  } catch {
   try{[IO.File]::Delete($requestStaging)}catch{}
   # Only this publisher's exclusive reservation and outputs may be removed.
   if($reserved){
    foreach($p in @($codePending)+$(if($publishedCode){@($codePath)}else{@()})){
     try{[IO.File]::Delete($p)}catch{}
    }
    try{[IO.File]::Delete($requestPending)}catch{}
   }
   throw
  }
 } finally {foreach($session in $sessions){$session.Lease.Dispose()}}
}
if($MyInvocation.InvocationName -ne '.') {
 $ErrorActionPreference='Stop'
 try {$code=Invoke-Schema6PairingWindow -TaskName $TaskName;[Console]::Out.WriteLine($code);exit 0}
 catch {
  $code=$_.Exception.Message
  if($code -cnotmatch '\A[a-z0-9_]{1,64}\z'){$code='pairing_window_rejected'}
  [Console]::Error.WriteLine('schema6_pairing_window_rejected:'+$code);exit 2
 }
}
