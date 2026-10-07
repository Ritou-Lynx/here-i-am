# Authorized local diagnostic: at most four disabled, triggerless synthetic tasks.
# Does not stop services, change production tasks, or approve production XML/SDDL.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$ApprovedXmlPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ApprovedXmlSha256,
 [Parameter(Mandatory=$true)][string]$PrimitivesPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$PrimitivesSha256,
 [Parameter(Mandatory=$true)][string]$FixturePath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$FixtureSha256,
 [Parameter(Mandatory=$true)][string]$OutputDirectory,
 [switch]$ExecuteFourSyntheticTasks
)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
$leases=New-Object 'System.Collections.Generic.List[System.IDisposable]'
$report=[ordered]@{format='schema6-local-compatibility-matrix-v1';approvedXmlSha256=$ApprovedXmlSha256;startedUtc=[DateTime]::UtcNow.ToString('o');maximumCreates=4;createAttempts=0;cases=@();productionTasksChanged=$false;servicesChanged=$false;productionApproved=$false;completed=$false}
function Assert-ProbePlainPath([string]$Path){
 if($Path-notmatch '^[A-Za-z]:\\' -or $Path.Substring(2).Contains(':') -or [IO.Path]::GetFullPath($Path)-cne $Path){throw 'probe_path_rejected'}
 for($q=$Path;$q;$q=[IO.Path]::GetDirectoryName($q)){
  $item=Get-Item -LiteralPath $q -Force -ErrorAction Stop
  if($item.Attributes-band [IO.FileAttributes]::ReparsePoint){throw 'probe_link_rejected'}
 }
}
function Open-ProbePin([string]$Path,[string]$Expected){
 Assert-ProbePlainPath $Path
 $h=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$hash=([BitConverter]::ToString($sha.ComputeHash($h))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  if($hash-cne $Expected){throw 'probe_input_hash_changed'}
  $h.Position=0;$leases.Add($h)
  $reader=New-Object IO.StreamReader($h,[Text.Encoding]::UTF8,$true,4096,$true)
  try{return $reader.ReadToEnd()}finally{$reader.Dispose()}
 }catch{$h.Dispose();throw}
}
function Get-ProbeError($ErrorRecord){
 $v=[string]$ErrorRecord.Exception.Message
 if($v-cmatch '^[a-z][a-z0-9_]{0,100}$'){return $v}
 return 'probe_operation_rejected'
}
function Get-CompatibilityCaseXml([string]$Text,[ValidateSet('omitted','explicit_false')][string]$Mode,[string]$Nonce,[string]$OwnerSid,[string]$SafeCommand){
 $d=Read-ApprovedTaskXml $Text
 $ns=New-Object Xml.XmlNamespaceManager($d.NameTable);$ns.AddNamespace('t',$d.DocumentElement.NamespaceURI)
 $triggers=$d.SelectSingleNode('/t:Task/t:Triggers',$ns)
 $settings=$d.SelectSingleNode('/t:Task/t:Settings',$ns)
 $actions=$d.SelectSingleNode('/t:Task/t:Actions',$ns)
 if($null-eq $triggers -or $null-eq $settings -or $null-eq $actions){throw 'probe_approved_shape_rejected'}
 $triggers.RemoveAll()
 $enabled=$settings.SelectSingleNode('t:Enabled',$ns)
 if($null-eq $enabled){throw 'probe_enabled_missing'};$enabled.InnerText='false'
 $unified=$settings.SelectSingleNode('t:UseUnifiedSchedulingEngine',$ns)
 if($null-ne $unified){$null=$settings.RemoveChild($unified)}
 if($Mode-ceq 'explicit_false'){$u=$d.CreateElement('UseUnifiedSchedulingEngine',$d.DocumentElement.NamespaceURI);$u.InnerText='false';$null=$settings.AppendChild($u)}
 $actions.RemoveAll();$actions.SetAttribute('Context','Owner')
 $exec=$d.CreateElement('Exec',$d.DocumentElement.NamespaceURI)
 $command=$d.CreateElement('Command',$d.DocumentElement.NamespaceURI);$command.InnerText=$SafeCommand;$null=$exec.AppendChild($command)
 $args=$d.CreateElement('Arguments',$d.DocumentElement.NamespaceURI);$args.InnerText='/d /c exit 0';$null=$exec.AppendChild($args);$null=$actions.AppendChild($exec)
 $principal=$d.SelectSingleNode('/t:Task/t:Principals/t:Principal',$ns)
 if($null-eq $principal){throw 'probe_principal_missing'}
 $principal.SetAttribute('id','Owner')
 $principal.SelectSingleNode('t:UserId',$ns).InnerText=$OwnerSid
 $registration=$d.SelectSingleNode('/t:Task/t:RegistrationInfo',$ns)
 if($null-eq $registration){$registration=$d.CreateElement('RegistrationInfo',$d.DocumentElement.NamespaceURI);$null=$d.DocumentElement.InsertBefore($registration,$d.DocumentElement.FirstChild)}
 $source=$registration.SelectSingleNode('t:Source',$ns)
 if($null-eq $source){$source=$d.CreateElement('Source',$d.DocumentElement.NamespaceURI);$null=$registration.AppendChild($source)}
 $source.InnerText=$Nonce
 return $d.OuterXml
}
function Assert-ProbeSafeDefinition($Definition,[string]$OwnerSid,[string]$SafeCommand,[string]$Nonce){
 if($Definition.Settings.Enabled -or $Definition.Triggers.Count-ne 0 -or $Definition.Actions.Count-ne 1){throw 'probe_safety_shape_rejected'}
 if($Definition.Principal.LogonType-ne 3 -or $Definition.Principal.RunLevel-ne 0 -or (Convert-TaskSid $Definition.Principal.UserId)-cne $OwnerSid){throw 'probe_safety_owner_rejected'}
 if([string]$Definition.RegistrationInfo.Source-cne $Nonce){throw 'probe_safety_nonce_rejected'}
 $a=$Definition.Actions.Item(1)
 if($a.Type-ne 0 -or [string]$a.Path-cne $SafeCommand -or [string]$a.Arguments-cne '/d /c exit 0' -or [string]$a.WorkingDirectory){throw 'probe_safety_action_rejected'}
}
function Get-LegacyProbeSnapshot($Folder){
 $snap=[ordered]@{}
 foreach($name in @('HereIAm-iCore','HereIAm-iRemoteMCP')){
  $t=$Folder.GetTask($name)
  $snap[$name]=@{xml=[string]$t.Xml;sddl=[string]$t.GetSecurityDescriptor(7);enabled=[bool]$t.Enabled;state=[int]$t.State;instances=@($t.GetInstances(0)).Count}
 }
 return ($snap|ConvertTo-Json -Depth 6 -Compress)
}
$exitCode=2;$fatal=$false;$outputPath=$null
try{
 if(!$ExecuteFourSyntheticTasks){throw 'probe_explicit_execution_required'}
 Assert-ProbePlainPath $OutputDirectory
 if(@(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count-ne 0){throw 'probe_fresh_output_required'}
 $outputPath=Join-Path $OutputDirectory 'compatibility-matrix.json'
 $xml=Open-ProbePin $ApprovedXmlPath $ApprovedXmlSha256
 $null=Open-ProbePin $PrimitivesPath $PrimitivesSha256
 $fixture=Open-ProbePin $FixturePath $FixtureSha256
 . $PrimitivesPath
 $tokens=$null;$parseErrors=$null
 $ast=[Management.Automation.Language.Parser]::ParseInput($fixture,[ref]$tokens,[ref]$parseErrors)
 if($parseErrors.Count){throw 'probe_fixture_parse_rejected'}
 foreach($name in @('Get-SyntheticInheritedSecurity','Get-SyntheticSecurityShape')){
  $nodes=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name-ceq $name},$true))
  if($nodes.Count-ne 1){throw 'probe_fixture_function_rejected'}
  . ([scriptblock]::Create($nodes[0].Extent.Text))
 }
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $safeCommand=Join-Path $env:SystemRoot 'System32\cmd.exe'
 $service=New-Object -ComObject Schedule.Service;$service.Connect();$folder=$service.GetFolder('\')
 $legacyBefore=Get-LegacyProbeSnapshot $folder
 $parentSddl=[string]$folder.GetSecurityDescriptor(7)
 $matrix=@()
 # Prepare every input/expected result before the first CREATE. No actual readback oracle.
 foreach($mode in @('omitted','explicit_false')){
  foreach($protected in @($true,$false)){
   $nonce=[Guid]::NewGuid().ToString('N');$name='HereIAm-Synthetic-Compat-'+[Guid]::NewGuid().ToString('N')
   $caseXml=Get-CompatibilityCaseXml $xml $mode $nonce $sid $safeCommand
   $definition=$service.NewTask(0);$definition.XmlText=$caseXml
   Assert-ProbeSafeDefinition $definition $sid $safeCommand $nonce
   $dacl=if($protected){'D:P'}else{'D:'}
   $inputSddl='O:'+$sid+'G:'+$sid+$dacl+'(A;;FA;;;'+$sid+')(A;;FA;;;SY)(A;;FA;;;BA)'
   $expectedSddl=if($protected){$inputSddl}else{Get-SyntheticInheritedSecurity $inputSddl $parentSddl $sid $sid}
   $null=Convert-TaskSecurity $expectedSddl
   $matrix+=@{name=$name;nonce=$nonce;mode=$mode;protected=$protected;xml=$caseXml;definition=$definition;inputSddl=$inputSddl;expectedSddl=$expectedSddl}
  }
 }
 foreach($case in $matrix){
  $r=[ordered]@{mode=$case.mode;protectedInput=$case.protected;taskName=$case.name;created=$false;deleted=$false;safeReadback=$false;definitionMatches=$false;securityMatches=$false;expectedUnified=[bool]$case.definition.Settings.UseUnifiedSchedulingEngine;actualUnified=$null;inputSecurity=(Get-SyntheticSecurityShape $case.inputSddl);expectedSecurity=(Get-SyntheticSecurityShape $case.expectedSddl);actualSecurity=$null;error=$null;cleanupError=$null;outcomeUnconfirmed=$false;parentStable=$false}
  $created=$null
  try{
   if([string]$folder.GetSecurityDescriptor(7)-cne $parentSddl){throw 'probe_parent_security_changed'}
   Assert-TaskAbsent $folder $case.name
   if($report.createAttempts-ge 4){throw 'probe_create_limit'}
   $report.createAttempts++
   $created=New-ApprovedTask $service $folder $case.name $case.xml $sid $case.inputSddl
   $r.created=$true
   $live=$folder.GetTask($case.name)
   if([string]$live.Path-cne ('\'+$case.name) -or @($live.GetInstances(0)).Count-ne 0){throw 'probe_live_path_or_instances_rejected'}
   Assert-ProbeSafeDefinition $live.Definition $sid $safeCommand $case.nonce
   if($live.Enabled){throw 'probe_live_enabled_rejected'};$r.safeReadback=$true
   $r.actualUnified=[bool]$live.Definition.Settings.UseUnifiedSchedulingEngine
   $actualSddl=[string]$live.GetSecurityDescriptor(7);$r.actualSecurity=Get-SyntheticSecurityShape $actualSddl
   try{Assert-TaskDefinition $live.Definition $case.definition;$r.definitionMatches=$true}catch{$r.definitionError=Get-ProbeError $_}
   try{$r.securityMatches=((Convert-TaskSecurity $actualSddl)-ceq (Convert-TaskSecurity $case.expectedSddl))}catch{$r.securityError=Get-ProbeError $_}
   if([string]$folder.GetSecurityDescriptor(7)-cne $parentSddl){throw 'probe_parent_security_changed'};$r.parentStable=$true
  }catch{
   $r.error=Get-ProbeError $_
   if($null-eq $created -and $report.createAttempts-gt @($report.cases).Count){$r.outcomeUnconfirmed=$true}
   $fatal=$true
  }finally{
   if($null-ne $created){
    try{
     $bound=$folder.GetTask($case.name)
     if($case.name-cnotmatch '^HereIAm-Synthetic-Compat-[a-f0-9]{32}$' -or [string]$bound.Path-cne ('\'+$case.name) -or $bound.Enabled -or @($bound.GetInstances(0)).Count-ne 0){throw 'probe_cleanup_binding_rejected'}
     Assert-ProbeSafeDefinition $bound.Definition $sid $safeCommand $case.nonce
     # Cleanup does not depend on Unified, P flag, or the assertion under test.
     $folder.DeleteTask($case.name,0)
     Assert-TaskAbsent $folder $case.name;$r.deleted=$true
    }catch{$r.cleanupError=Get-ProbeError $_;$fatal=$true}
   }
   $report.cases+=,$r
  }
  if($fatal){break}
 }
 $legacyAfter=Get-LegacyProbeSnapshot $folder
 $report.legacySnapshotUnchanged=($legacyBefore-ceq $legacyAfter)
 $report.parentStable=([string]$folder.GetSecurityDescriptor(7)-ceq $parentSddl)
 if(!$report.legacySnapshotUnchanged -or !$report.parentStable){throw 'probe_external_state_changed'}
 $report.completed=(!$fatal -and $report.createAttempts-eq 4 -and @($report.cases|Where-Object{!$_.created -or !$_.deleted -or !$_.safeReadback}).Count-eq 0)
 if($report.completed){$exitCode=0}
}catch{$report.error=Get-ProbeError $_}
finally{
 $report.completedUtc=[DateTime]::UtcNow.ToString('o')
 $encoded=$report|ConvertTo-Json -Depth 12 -Compress
 if($outputPath){
  $h=$null
  try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes($encoded+[Environment]::NewLine);$h=[IO.File]::Open($outputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$h.Write($bytes,0,$bytes.Length);$h.Flush($true)}
  catch{$exitCode=2;[Console]::Error.WriteLine('probe_report_write_rejected')}
  finally{if($h){$h.Dispose()}}
 }
 foreach($h in $leases){$h.Dispose()}
 [Console]::Out.WriteLine($encoded)
}
exit $exitCode
