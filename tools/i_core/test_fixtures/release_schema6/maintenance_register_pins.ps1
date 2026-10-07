param([string]$SourcePath,[string]$FixtureParent,[ValidateSet('suite','contender')][string]$Mode='suite')
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
$candidateRoot=Join-Path $FixtureParent 'synthetic-release'
$manifestPath=Join-Path $candidateRoot 'manifest.json'
$candidateScript=Join-Path $candidateRoot 'protected_paths.ps1'
if($Mode-ceq 'contender'){
 $writes=0;$replacements=0
 foreach($target in @($manifestPath,$candidateScript)){
  try{[IO.File]::WriteAllText($target,'unexpected-write');throw 'candidate_write_was_allowed'}catch{
   $cause=$_.Exception;while($cause.InnerException){$cause=$cause.InnerException};if(($cause.HResult-band 0xffff)-ne 32){throw};$writes++
  }
  $replacement=$target+'.replacement';[IO.File]::WriteAllText($replacement,'unexpected-replacement')
  try{
   try{[IO.File]::Replace($replacement,$target,[NullString]::Value);throw 'candidate_replace_was_allowed'}catch{
    $cause=$_.Exception;while($cause.InnerException){$cause=$cause.InnerException};if(($cause.HResult-band 0xffff)-ne 32){throw};$replacements++
   }
  }finally{if([IO.File]::Exists($replacement)){[IO.File]::Delete($replacement)}}
 }
 @{writesRejected=$writes;replacementsRejected=$replacements}|ConvertTo-Json -Compress;exit 0
}
$errors=$null;$tokens=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors);if($errors.Count){throw 'source_parse_failed'}
$command=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName()-eq 'Add-Type'},$true))[0]
Add-Type -TypeDefinition $command.CommandElements[2].Value
foreach($name in @('Pin-File','Assert-Private','Pin-ReleaseInventory')){
 $f=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name-ceq $name},$true));if($f.Count-ne 1){throw 'fixture_function_not_unique'};Invoke-Expression $f[0].Extent.Text
}
$locks=New-Object 'System.Collections.Generic.List[System.IDisposable]'
$file=Join-Path $FixtureParent 'synthetic-pin.txt';[IO.File]::WriteAllText($file,'synthetic-pin',[Text.UTF8Encoding]::new($false))
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
$acl=New-Object Security.AccessControl.FileSecurity;$acl.SetOwner($sid);$acl.SetAccessRuleProtection($true,$false)
foreach($id in @($sid,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'),[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))){$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($id,'FullControl','Allow'))}
$privateSddl=$acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::All)
function Protect-SyntheticFile([string]$Path){$fresh=New-Object Security.AccessControl.FileSecurity;$fresh.SetSecurityDescriptorSddlForm($privateSddl,([Security.AccessControl.AccessControlSections]::Owner-bor [Security.AccessControl.AccessControlSections]::Access));[IO.File]::SetAccessControl($Path,$fresh)}
Protect-SyntheticFile $file
try{
 foreach($hash in @('','short')){try{Pin-File $file $hash;throw 'empty_anchor_accepted'}catch{if($_.Exception.Message-cne 'sha256_anchor_required'){throw}}}
 $hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant();Pin-File $file $hash
 try{Pin-File $file ('0'*64);throw 'wrong_anchor_accepted'}catch{if($_.Exception.Message-cne 'file_hash_changed'){throw}}
 try{Pin-File $file $hash -ReceiptWithoutExternalHash;throw 'ambiguous_receipt_exception_accepted'}catch{if($_.Exception.Message-cne 'receipt_pin_shape_rejected'){throw}}
 Pin-File $file '' -ReceiptWithoutExternalHash
 $null=[IO.Directory]::CreateDirectory($candidateRoot)
 $candidateData=Join-Path $candidateRoot 'candidate-data.txt'
 [IO.File]::WriteAllText($candidateScript,'# synthetic, never executed',[Text.UTF8Encoding]::new($false))
 [IO.File]::WriteAllText($candidateData,'synthetic-candidate',[Text.UTF8Encoding]::new($false))
 foreach($p in @($candidateScript,$candidateData)){Protect-SyntheticFile $p}
 $entries=@(@($candidateScript,$candidateData)|ForEach-Object{@{path=[IO.Path]::GetFileName($_);sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant();bytes=([IO.FileInfo]::new($_)).Length}})
 function Write-SyntheticManifest {
  [IO.File]::WriteAllText($manifestPath,(@{files=$entries}|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false));Protect-SyntheticFile $manifestPath
  return (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
 }
 function Close-SyntheticPins {foreach($h in $locks){$h.Dispose()};$locks.Clear()}
 $manifestHash=Write-SyntheticManifest
 $original=@{};foreach($p in @($manifestPath,$candidateScript,$candidateData)){$original[$p]=[Convert]::ToBase64String([IO.File]::ReadAllBytes($p))}
 Pin-ReleaseInventory $candidateRoot $manifestHash
 $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $info=New-Object Diagnostics.ProcessStartInfo;$info.FileName=$ps;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.Arguments=(@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-FixtureParent',$FixtureParent,'-Mode','contender')|ForEach-Object{'"'+$_+'"'})-join ' '
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $child=New-Object Diagnostics.Process;$child.StartInfo=$info
 try{
  $null=$child.Start();$stdout=$child.StandardOutput.ReadToEndAsync();$stderr=$child.StandardError.ReadToEndAsync()
  if(!$child.WaitForExit(15000)){$child.Kill();throw 'candidate_contender_timeout'}
  $errorText=$stderr.GetAwaiter().GetResult();if($child.ExitCode-ne 0){throw ('candidate_contender_failed: '+$errorText)}
  $result=$stdout.GetAwaiter().GetResult()|ConvertFrom-Json
  if($result.writesRejected-ne 2 -or $result.replacementsRejected-ne 2){throw 'candidate_contention_not_verified'}
 }finally{$child.Dispose()}
 foreach($p in $original.Keys){if([Convert]::ToBase64String([IO.File]::ReadAllBytes($p))-cne $original[$p]){throw 'candidate_bytes_changed'}}
 Close-SyntheticPins
 foreach($p in @($manifestPath,$candidateScript,$candidateData)){
  [IO.File]::WriteAllText($p,'released-write');if([IO.File]::ReadAllText($p)-cne 'released-write'){throw 'candidate_release_write_failed'}
  [IO.File]::WriteAllBytes($p,[Convert]::FromBase64String($original[$p]))
 }
 function Reject-SyntheticInventory([string]$Code){
  $anchor=Write-SyntheticManifest
  try{Pin-ReleaseInventory $candidateRoot $anchor;throw 'candidate_invalid_inventory_accepted'}catch{if($_.Exception.Message-cne $Code){throw}}finally{Close-SyntheticPins}
 }
 $goodHash=$entries[0].sha256;$goodSize=$entries[0].bytes;$goodPath=$entries[0].path
 $entries[0].sha256='0'*64;Reject-SyntheticInventory 'file_hash_changed';$entries[0].sha256=$goodHash
 $entries[0].bytes=$goodSize+1;Reject-SyntheticInventory 'file_size_changed';$entries[0].bytes=$goodSize
 foreach($bad in @('','short')){$entries[0].sha256=$bad;Reject-SyntheticInventory 'sha256_anchor_required'};$entries[0].sha256=$goodHash
 foreach($bad in @(-1,'1')){$entries[0].bytes=$bad;Reject-SyntheticInventory 'candidate_size_rejected'};$entries[0].bytes=$goodSize
 foreach($bad in @('../outside.ps1','/rooted.ps1','dir//file.ps1','dir/./file.ps1','C:\absolute.ps1',$entries[1].path.ToUpperInvariant())){$entries[0].path=$bad;Reject-SyntheticInventory 'candidate_relative_path_rejected'};$entries[0].path=$goodPath
 $null=Write-SyntheticManifest
 [Console]::WriteLine('{"passed":true,"emptyAndMalformedRejected":true,"correctHashPinned":true,"wrongHashRejected":true,"receiptExceptionExplicit":true,"candidateInventoryPinned":true,"crossProcessWriteRejected":true,"crossProcessReplaceRejected":true,"candidateBytesPreserved":true,"releaseAllowsWrites":true,"candidateHashMismatchRejected":true,"candidateSizeMismatchRejected":true,"candidateShapeRejected":true}')
}finally{foreach($h in $locks){$h.Dispose()}}
