# Existing synthetic fixtures also exercise ordinary-only production gates on CI.
# This dispatcher changes only a child token, with native identity verification.
function Invoke-OrdinaryFixtureIfElevated([string]$ScriptPath,$Parameters) {
 if(!([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){return}
 . (Join-Path $PSScriptRoot 'module_scope.ps1');Assert-Schema6ModuleScopeHost
 Add-Type -Path (Join-Path $PSScriptRoot 'identity_token.cs')
 $folder=Join-Path ([IO.Path]::GetTempPath()) ('schema6-ordinary-'+[Guid]::NewGuid().ToString('N'))
 $null=[IO.Directory]::CreateDirectory($folder)
 $output=Join-Path $folder 'output.txt';$identityPath=Join-Path $folder 'identity.json';$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $errorsPath=Join-Path $folder 'errors.txt'
 function Q([string]$s){"'"+$s.Replace("'","''")+"'"}
 $arguments=@(foreach($key in $Parameters.Keys){'-'+$key+' '+(Q ([string]$Parameters[$key]))})-join ' '
 $tokenSource=Join-Path $PSScriptRoot 'identity_token.cs'
 $body='$ErrorActionPreference=''Stop'';Add-Type -Path '+(Q $tokenSource)+';$i=[Schema6IdentityToken]::Current();[IO.File]::WriteAllText('+(Q $identityPath)+',($i|ConvertTo-Json -Compress));if($i.elevated -or $i.administrator -or $i.integritySid-cne ''S-1-16-8192''){throw ''ordinary_fixture_token_rejected''};& '+(Q $ScriptPath)+' '+$arguments+' 1> '+(Q $output)+' 2> '+(Q $errorsPath)+';if(!$?){exit 1}'
 try{
  $code=[Schema6IdentityToken]::RunLimited($ps,('-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))),[IO.Path]::GetDirectoryName($ScriptPath))
  if(!(Test-Path -LiteralPath $identityPath)){throw ('ordinary_fixture_identity_missing_exit_'+$code)}
  $childIdentity=Get-Content -LiteralPath $identityPath -Raw|ConvertFrom-Json;$desktop=[Schema6IdentityToken]::LastDesktop
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  if(!$desktop.parentThreadDesktopRestored){throw 'ordinary_fixture_thread_desktop_restore_rejected'}
  if($childIdentity.sid-cne $sid -or $childIdentity.owner-cne $sid -or $childIdentity.elevated -or $childIdentity.administrator -or $childIdentity.integritySid-cne 'S-1-16-8192' -or $childIdentity.windowStation-cne $desktop.windowStation -or $childIdentity.desktop-cne $desktop.desktop -or !$desktop.parentStationRestored -or !$desktop.desktopClosed -or !$desktop.stationClosed -or !$desktop.stationSecurityVerified -or !$desktop.desktopSecurityVerified){throw 'ordinary_fixture_identity_or_desktop_rejected'}
  if(Test-Path -LiteralPath $output){[Console]::Out.Write([IO.File]::ReadAllText($output))}
  if(Test-Path -LiteralPath $errorsPath){[Console]::Error.Write([IO.File]::ReadAllText($errorsPath))}
  exit $code
 }finally{
  $resolved=(Resolve-Path -LiteralPath $folder).Path
  if([IO.Path]::GetFileName($resolved)-cnotmatch '^schema6-ordinary-[a-f0-9]{32}$'){throw 'fixture_cleanup_scope_rejected'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
 }
}
