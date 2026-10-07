param([string]$OutputReport=(Join-Path $PSScriptRoot '../../../../build/ci/schema6-identity-startup.json'))
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
. (Join-Path $PSScriptRoot 'module_scope.ps1');Assert-Schema6ModuleScopeHost
Add-Type -Path (Join-Path $PSScriptRoot 'identity_token.cs')
$parent=[Schema6IdentityToken]::Current()
if(!$parent.elevated -or !$parent.administrator -or $parent.owner-cne 'S-1-5-32-544' -or $parent.integritySid-cne 'S-1-16-12288'){throw 'diagnostic_real_elevated_admin_default_owner_required'}
# These programs only exit. No application/store/task operation, no child tree.
$programs=@(
 @{name='cmd';path=(Join-Path $env:SystemRoot 'System32/cmd.exe');arguments='/d /c exit 0'},
 @{name='node';path=(Get-Command node.exe -ErrorAction Stop).Source;arguments='-e "process.exit(0)"'},
 @{name='powershell';path=(Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe');arguments='-NoProfile -NonInteractive -Command "exit 0"'}
)
$variants=@(
 @{name='inherited-baseline';desktop=$false;kernel=$false;defaultDacl=$false;tokenObject=$false},
 @{name='private-desktop-only';desktop=$true;kernel=$false;defaultDacl=$false;tokenObject=$false},
 @{name='private-desktop-kernel';desktop=$true;kernel=$true;defaultDacl=$false;tokenObject=$false},
 @{name='private-desktop-default-dacl';desktop=$true;kernel=$false;defaultDacl=$true;tokenObject=$false},
 @{name='fixed-candidate';desktop=$true;kernel=$true;defaultDacl=$true;tokenObject=$false},
 @{name='candidate-token-object-dacl';desktop=$true;kernel=$true;defaultDacl=$true;tokenObject=$true}
)
$report=[ordered]@{format='schema6-identity-startup-diagnostics-v1';diagnosticOnly=$true;pipelinePassed=$false;completed=$false;parent=$parent;timeoutMsPerChild=15000;cases=@()}
$OutputReport=[IO.Path]::GetFullPath($OutputReport)
$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($OutputReport))
try{
 foreach($variant in $variants){foreach($program in $programs){
  $watch=[Diagnostics.Stopwatch]::StartNew()
  $case=[ordered]@{variant=$variant.name;program=$program.name;exitCode=$null;error=$null;elapsedMs=0;launch=$null;desktop=$null}
  try{$case.exitCode=[Schema6IdentityToken]::RunVariant($program.path,$program.arguments,$env:SystemRoot,$variant.desktop,$variant.kernel,$variant.defaultDacl,$variant.tokenObject)}
  catch{$case.error=[string]$_.Exception.Message}
  finally{$watch.Stop();$case.elapsedMs=$watch.ElapsedMilliseconds;$case.launch=[Schema6IdentityToken]::LastLaunch;$case.desktop=[Schema6IdentityToken]::LastDesktop;$report.cases+=,$case}
  Write-Host ('diagnostic '+$case.variant+'/'+$case.program+' exit='+$case.exitCode+' stage='+$case.launch.stage+' elapsedMs='+$case.elapsedMs+' error='+$case.error)
  # Stop on uncertain cleanup; never carry on while a fixture child/object may live.
  if($case.error -match 'cleanup_failed|restore_failed'){throw 'diagnostic_cleanup_not_confirmed'}
 }}
 $report.completed=($report.cases.Count-eq 18)
}finally{[IO.File]::WriteAllText($OutputReport,($report|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
if(!$report.completed){throw 'diagnostic_matrix_incomplete'}
# Measured startup failures are observations, not test passes. This never selects
# a launcher or gates the fixed candidate; the separate real pipeline must pass.
