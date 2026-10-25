[CmdletBinding()]
param([string]$TaskName,[string[]]$Rotate=@())

# Read-only session discovery; importing does not access Task Scheduler.
. (Join-Path $PSScriptRoot 'stop-schema6-session.ps1') -TaskName $TaskName

function Write-Schema6FoodFile([string]$Path,[byte[]]$Bytes) {
 $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try {$stream.Write($Bytes,0,$Bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
}
function Invoke-Schema6FoodProvision([string]$TaskName,[string[]]$Rotate=@()) {
 if($PSVersionTable.PSVersion.Major-ne 5 -or $PSVersionTable.PSEdition-ne 'Desktop'){throw 'windows_powershell_51_required'}
 # -File passes "writer,phone" as one string; accept both that and separate values.
 $Rotate=@($Rotate|ForEach-Object {$_ -split ','})
 if(@($Rotate|Where-Object {$_ -cnotin @('writer','phone')}).Count -gt 0 -or @($Rotate|Select-Object -Unique).Count -ne $Rotate.Count){throw 'invalid_food_provision_request'}
 $binding=Get-Schema6LoginBinding $TaskName
 Assert-Schema6NoRecovery $binding
 $sessions=@(Get-Schema6LiveSessions $binding)
 try {
  if($sessions.Count -ne 1){throw 'food_single_live_session_required'}
  $session=$sessions[0]
  if($session.Window.manifest_sha256 -cne $binding.Login.manifest_sha256){throw 'food_session_manifest_mismatch'}
  . (Join-Path $binding.Login.release_directory 'tools\i_core\release_schema6\lifecycle\protected_paths.ps1')
  Assert-ProtectedPath $session.Directory -Root
  $live=@()
  foreach($directory in @(Get-ChildItem -LiteralPath $session.Directory -Directory -Filter 'control-*')){
   $readyPath=Join-Path $directory.FullName 'ready.json'
   if(-not (Test-Path -LiteralPath $readyPath) -or (Test-Path -LiteralPath (Join-Path $directory.FullName 'child.json'))){continue}
   Assert-ProtectedPath $directory.FullName -Root
   $launch=Read-Schema6Json (Join-Path $directory.FullName 'launch.json')
   $ready=Read-Schema6Json $readyPath
   if($launch.token -cnotmatch '^[a-f0-9]{64}$' -or $ready.token -cne $launch.token -or $launch.manifest_sha256 -cne $binding.Login.manifest_sha256 -or $ready.manifest_sha256 -cne $launch.manifest_sha256 -or $ready.configuration_sha256 -cne $binding.Login.core_configuration_sha256 -or $launch.configuration_file -cne $binding.Login.core_configuration_path -or $launch.state -cne $binding.Login.state_directory -or $launch.release -cne $binding.Login.release_directory -or $launch.owner_sid -cne $binding.Login.owner_sid -or $launch.mode -cnotin @('start','initialize-empty')){throw 'food_control_binding_mismatch'}
   $marker=Read-Schema6Json (Join-Path $binding.Login.state_directory 's6-lifecycle.json')
   if($marker.format -cne 'schema6-lifecycle-v1' -or $marker.phase -cne 'listening' -or $marker.token -cne $launch.token -or $marker.manifest_sha256 -cne $launch.manifest_sha256 -or $marker.configuration_sha256 -cne $ready.configuration_sha256 -or (Test-Path -LiteralPath (Join-Path $directory.FullName 'close')) -or (Test-Path -LiteralPath (Join-Path $directory.FullName 'stop'))){throw 'food_core_not_listening'}
   $process=$null
   try {
    $process=[Diagnostics.Process]::GetProcessById([int]$ready.pid)
    $image=Join-Path $binding.Login.release_directory 'runtime\node.exe'
    if($process.HasExited -or -not $process.MainModule.FileName.Equals($image,[StringComparison]::OrdinalIgnoreCase) -or $process.StartTime.ToUniversalTime().Ticks -gt (Get-Item -LiteralPath $readyPath).LastWriteTimeUtc.Ticks){throw 'food_core_process_not_live'}
   } catch {throw 'food_core_process_not_live'} finally {if($process){$process.Dispose()}}
   $live += [pscustomobject]@{Directory=$directory.FullName;Token=$launch.token;Manifest=$launch.manifest_sha256}
  }
  if($live.Count -ne 1){throw 'food_single_live_control_required'}
  $control=$live[0]
  $requestPath=Join-Path $control.Directory 'food.request'
  $pending=$requestPath+'.pending'
  foreach($p in @($requestPath,$pending)){
   $null=Assert-Schema6PlainPath $p
   if(Test-Path -LiteralPath $p){throw 'food_unhandled_request_exists'}
  }
  $keyPath=Join-Path $control.Directory 'stop.key';Assert-ProtectedPath $keyPath
  $key=[Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText($keyPath))
  $requestId=[Guid]::NewGuid().ToString('D')
  $expires=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+600000
  $hmac=New-Object Security.Cryptography.HMACSHA256
  try {
   $hmac.Key=$key
   $message=$control.Token+'|'+$control.Manifest+'|food|'+$requestId+'|'+(($Rotate|Sort-Object)-join ',')+'|'+$expires.ToString([Globalization.CultureInfo]::InvariantCulture)
   $authentication=([BitConverter]::ToString($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($message)))).Replace('-','').ToLowerInvariant()
  } finally {$hmac.Dispose();[Array]::Clear($key,0,$key.Length)}
  $json=@{request_id=$requestId;rotate=@($Rotate);expires_at_ms=$expires;hmac=$authentication}|ConvertTo-Json -Compress
  $reserved=$false
  try {
   Write-Schema6FoodFile $pending ([Text.Encoding]::UTF8.GetBytes($json));$reserved=$true
   [IO.File]::Move($pending,$requestPath)
  } finally {if($reserved -and (Test-Path -LiteralPath $pending)){[IO.File]::Delete($pending)}}
  $deadline=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+60000
  while([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -lt $deadline){
   foreach($file in @(Get-ChildItem -LiteralPath $control.Directory -File -Filter 'food-receipt-*.json')){
    Assert-ProtectedPath $file.FullName
    $receipt=Read-Schema6Json $file.FullName
    if($receipt.request_id -cne $requestId){continue}
    if($receipt.status -cne 'provisioned'){
     if($receipt.status -cnotmatch '^rejected_[a-z0-9_]{1,64}$'){throw 'food_invalid_receipt'}
     return @{status=$receipt.status}
    }
    $result=@{status='provisioned';registered=[bool]$receipt.registered;issued=@($receipt.issued)}
    if(@($receipt.issued).Count -gt 0){
     $tokensPath=Join-Path $control.Directory ('food-tokens-'+$requestId+'.json')
     Assert-ProtectedPath $tokensPath
     # Delete immediately after reading, before parsing or producing any output.
     try {$raw=[IO.File]::ReadAllText($tokensPath)} finally {[IO.File]::Delete($tokensPath)}
     $tokens=$raw|ConvertFrom-Json
     if($tokens.format -cne 'food-tokens-v1' -or $tokens.request_id -cne $requestId){throw 'food_invalid_tokens'}
     foreach($role in @($receipt.issued)){
      if($role -cnotin @('writer','phone')){throw 'food_invalid_receipt'}
      $value=$tokens.($role+'_token')
      if($value -cnotmatch '^[A-Za-z0-9_-]{43}$'){throw 'food_invalid_tokens'}
      $result[$role+'_token']=$value
     }
    }
    return $result
   }
   Start-Sleep -Milliseconds 25
  }
  throw 'food_receipt_timeout'
 } finally {foreach($session in $sessions){$session.Lease.Dispose()}}
}
function Invoke-Schema6FoodProvisionCli([string]$TaskName,[string[]]$Rotate=@()) {
 $ErrorActionPreference='Stop'
 try {
  $result=Invoke-Schema6FoodProvision -TaskName $TaskName -Rotate $Rotate
  [Console]::Out.WriteLine(($result|ConvertTo-Json -Compress -Depth 4))
  if($result.status -ceq 'provisioned'){exit 0};exit 2
 } catch {
  $code=$_.Exception.Message
  if($code -cnotmatch '^[a-z0-9_]{1,64}$'){$code='food_provision_failed'}
  [Console]::Out.WriteLine((@{status=('rejected_'+$code)}|ConvertTo-Json -Compress));exit 2
 }
}
if($MyInvocation.InvocationName -ne '.') {Invoke-Schema6FoodProvisionCli -TaskName $TaskName -Rotate $Rotate}
