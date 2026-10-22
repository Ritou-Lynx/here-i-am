# Isolated boundary harness. Parse production helpers/catch/output; never load
# the registration body, Scheduler, runtime, or any production configuration.
param([Parameter(Mandatory=$true)][string]$Entry,[Parameter(Mandatory=$true)][string]$InputPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
$inputData=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($Entry,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'entry_parse_rejected'}
foreach($name in @('Assert-Private','Assert-BackupPrivateAcl','Invoke-SwitchRegistrationValidator','Write-SwitchRegistrationReceipt')){
 $fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]-and $n.Name-ceq $name},$false)
 if(!$fn){throw 'entry_helper_missing'}
 . ([ScriptBlock]::Create($fn.Extent.Text))
}
# Replace only the receipt storage primitive, retaining production serialization.
function Write-OwnedArtifactBytes([string]$Path,[byte[]]$Bytes,[string]$OwnerSid){[IO.File]::WriteAllBytes($Path,$Bytes)}
$locks=New-Object 'System.Collections.Generic.List[System.IDisposable]'
$created=$false;$registered=$null;$outputReady=$true;$exitCode=2
$report=[ordered]@{passed=$false;registered=$false;started=$false}
$config=[pscustomobject]@{registrationReceiptPath=$inputData.receipt;ownerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
$ConfigurationPath=$InputPath;$ExpectedConfigurationSha256='a'*64
$main=@($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.TryStatementAst]})
if($main.Count-ne 1-or $main[0].CatchClauses.Count-ne 1){throw 'entry_main_shape_rejected'}
$body=@'
try{
 switch($inputData.mode){
  'backup' {Assert-BackupPrivateAcl $inputData.backup}
  'validator' {$null=Invoke-SwitchRegistrationValidator $inputData.node $inputData.validator}
  'throw' {throw $inputData.message}
  'success' {$report.passed=$true;$report.registered=$true;Write-SwitchRegistrationReceipt;$exitCode=0}
  default {throw 'fixture_mode_rejected'}
 }
}
'@
$tail=$ast.Extent.Text.Substring($main[0].Extent.EndOffset)
# Catch and final public output run verbatim from the selected entry.
. ([ScriptBlock]::Create($body+$main[0].CatchClauses[0].Extent.Text+'finally{foreach($h in $locks){$h.Dispose()}}'+$tail))
