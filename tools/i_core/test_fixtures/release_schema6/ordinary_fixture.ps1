# Existing synthetic fixtures also exercise ordinary-only production gates on CI.
# This dispatcher changes only a child token, with native identity verification.
function Invoke-OrdinaryFixtureIfElevated([string]$ScriptPath,$Parameters) {
 if(!([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){return}
 . (Join-Path $PSScriptRoot 'module_scope.ps1');Assert-Schema6ModuleScopeHost
 Add-Type -Path (Join-Path $PSScriptRoot 'identity_token.cs')
 $folder=Join-Path ([IO.Path]::GetTempPath()) ('schema6-ordinary-'+[Guid]::NewGuid().ToString('N'))
 $null=[IO.Directory]::CreateDirectory($folder)
 $output=Join-Path $folder 'output.txt';$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 function Q([string]$s){"'"+$s.Replace("'","''")+"'"}
 $arguments=@(foreach($key in $Parameters.Keys){'-'+$key+' '+(Q ([string]$Parameters[$key]))})-join ' '
 $tokenSource=Join-Path $PSScriptRoot 'identity_token.cs'
 $body='$ErrorActionPreference=''Stop'';Add-Type -Path '+(Q $tokenSource)+';$i=[Schema6IdentityToken]::Current();if($i.elevated -or $i.administrator -or $i.integritySid-cne ''S-1-16-8192''){throw ''ordinary_fixture_token_rejected''};& '+(Q $ScriptPath)+' '+$arguments+' *> '+(Q $output)+';if(!$?){exit 1}'
 try{
  $code=[Schema6IdentityToken]::RunLimited($ps,('-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))),[IO.Path]::GetDirectoryName($ScriptPath))
  if(Test-Path -LiteralPath $output){[Console]::Out.Write([IO.File]::ReadAllText($output))}
  exit $code
 }finally{
  $resolved=(Resolve-Path -LiteralPath $folder).Path
  if([IO.Path]::GetFileName($resolved)-cnotmatch '^schema6-ordinary-[a-f0-9]{32}$'){throw 'fixture_cleanup_scope_rejected'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
 }
}
