#requires -Version 5.1
# Dormant exact two-slot evaluator. No top-level IO, task API or observed-input derivation.
function Assert-TaskTemplateKeys($Value,[string]$Keys){
 $actual=if($Value-is[Collections.IDictionary]){@($Value.Keys)}else{@($Value.PSObject.Properties.Name)}
 if((@($actual|Sort-Object)-join',')-cne(@($Keys.Split(' ')|Sort-Object)-join',')){throw 'task_template_schema'}
}
function Assert-TaskTemplateInteger($Value){
 if(($Value-isnot[int]-and$Value-isnot[long])-or$Value-lt0-or$Value-gt32768){throw 'task_template_integer'}
}
function Get-TaskTemplateHash([byte[]]$Bytes){
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Expand-TaskExactTwoSlots {
 param([Parameter(Mandatory=$true)]$Rule,[Parameter(Mandatory=$true)][byte[]]$Template,[Parameter(Mandatory=$true)][string]$BindingSha256,[Parameter(Mandatory=$true)][string]$ApprovalSha256)
 $ErrorActionPreference='Stop'
 Assert-TaskTemplateKeys $Rule 'id templateSha256 byteLength slots'
 if($BindingSha256-cnotmatch'^[a-f0-9]{64}$'-or$ApprovalSha256-cnotmatch'^[a-f0-9]{64}$'){throw 'task_template_pin'}
 Assert-TaskTemplateInteger $Rule.byteLength
 if($Template.Length-eq0-or$Template.Length-gt32768-or$Template.Length-ne$Rule.byteLength-or$Rule.templateSha256-cnotmatch'^[a-f0-9]{64}$'-or(Get-TaskTemplateHash $Template)-cne$Rule.templateSha256){throw 'task_template_bytes'}
 $utf8=[Text.UTF8Encoding]::new($false,$true);$whole=$utf8.GetString($Template)
 if($whole.StartsWith([string][char]0xfeff,[StringComparison]::Ordinal)-or$whole.Contains([string][char]0)-or[Convert]::ToBase64String($utf8.GetBytes($whole))-cne[Convert]::ToBase64String($Template)){throw 'task_template_encoding'}
 if(@($Rule.slots).Count-ne2){throw 'task_template_slots'}
 $priorEnd=-1
 for($n=0;$n-lt2;$n++){
  $s=$Rule.slots[$n]
  Assert-TaskTemplateKeys $s 'id argumentSwitch offset length placeholder prefixOffset prefixBase64 suffixBase64'
  foreach($v in @($s.offset,$s.length,$s.prefixOffset)){Assert-TaskTemplateInteger $v}
  $id=if($n-eq0){'binding'}else{'approval'}
  $switch=if($n-eq0){'-EvidenceBindingSha256'}else{'-ExpectedApprovalSha256'}
  $placeholder=if($n-eq0){'1'*64}else{'2'*64}
  if($s.id-cne$id-or$s.argumentSwitch-cne$switch-or$s.placeholder-cne$placeholder-or$s.length-ne64-or$s.offset-lt$priorEnd-or$s.offset+64-gt$Template.Length){throw 'task_template_slot_contract'}
  if($s.prefixOffset-ne[Math]::Max(0,$s.offset-40)-or$utf8.GetString($Template,$s.offset,64)-cne$placeholder){throw 'task_template_slot_position'}
  $prefix=[Convert]::FromBase64String($s.prefixBase64);$suffix=[Convert]::FromBase64String($s.suffixBase64)
  if($prefix.Length-ne($s.offset-$s.prefixOffset)-or$suffix.Length-ne[Math]::Min(40,$Template.Length-$s.offset-64)-or[Convert]::ToBase64String($Template,$s.prefixOffset,$prefix.Length)-cne$s.prefixBase64-or[Convert]::ToBase64String($Template,$s.offset+64,$suffix.Length)-cne$s.suffixBase64){throw 'task_template_context'}
  $needle='"'+$switch+'" "'+$placeholder+'"'
  if([regex]::Matches($whole,[regex]::Escape($needle)).Count-ne1-or[regex]::Matches($whole,[regex]::Escape($switch)).Count-ne1-or[regex]::Matches($whole,[regex]::Escape($placeholder)).Count-ne1){throw 'task_template_ambiguity'}
  $charOffset=$whole.IndexOf($needle,[StringComparison]::Ordinal)+$switch.Length+4
  if($utf8.GetByteCount($whole.Substring(0,$charOffset))-ne$s.offset){throw 'task_template_semantic_offset'}
  $priorEnd=$s.offset+64
 }
 $copy=[byte[]]$Template.Clone()
 [Array]::Copy($utf8.GetBytes($BindingSha256),0,$copy,[int]$Rule.slots[0].offset,64)
 [Array]::Copy($utf8.GetBytes($ApprovalSha256),0,$copy,[int]$Rule.slots[1].offset,64)
 return ,$copy
}
function Get-TaskTemplateLockedBytes {
 param($Lease,[string]$Id,[string]$Hash)
 $allowed=@('task_template_evaluator','task_template_rules','task_template_action','task_template_disabled_raw','task_template_enabled_raw','task_template_disabled_definition','task_template_enabled_definition','new_task_sddl','parent_sddl')
 if($Id-cnotin$allowed-or$Hash-cnotmatch'^[a-f0-9]{64}$'){throw 'task_template_role'}
 $record=Get-P4LeaseRecord $Lease
 $artifact=@($record.Binding.artifacts|Where-Object{$_.id-ceq$Id})
 if($artifact.Count-ne1-or$artifact[0].role-cne'source'-or$artifact[0].private-isnot[bool]-or!$artifact[0].private-or$artifact[0].sha256-cne$Hash-or$Lease.Hash($Id)-cne$Hash){throw 'task_template_locked_artifact'}
 $bytes=$Lease.Bytes($Id)
 if((Get-TaskTemplateHash $bytes)-cne$Hash){throw 'task_template_locked_hash'}
 return ,$bytes
}
function Get-ReviewedActivationTaskTargets {
 param([Parameter(Mandatory=$true)]$Lease)
 $record=Get-P4LeaseRecord $Lease
 $policy=$Lease.ReadJson('activation_policy')
 if($policy.format-cne'i-core-continuous-activation-policy-v2'-or$policy.evidenceMode-cne$Lease.Mode){throw 'task_template_policy'}
 Assert-TaskTemplateKeys $policy.taskDerivation 'format evaluatorSha256 rulesSha256'
 if($policy.taskDerivation.format-cne'i-core-task-exact-two-slot-v1'){throw 'task_template_protocol'}
 foreach($field in @('expectedActionArguments','expectedEnabledRawXmlSha256','expectedEnabledDefinitionSha256','expectedDisabledRawXmlSha256','expectedDisabledDefinitionSha256')){
  if($null-ne$policy.PSObject.Properties[$field]-and$null-ne$policy.$field){throw 'task_template_cycle_input'}
 }
 if($Lease.BindingSha256-cnotmatch'^[a-f0-9]{64}$'-or$Lease.ApprovalSha256-cnotmatch'^[a-f0-9]{64}$'){throw 'task_template_authority_pin'}
 $null=Get-TaskTemplateLockedBytes $Lease 'task_template_evaluator' $policy.taskDerivation.evaluatorSha256
 $rules=Read-P4StrictJson (Get-TaskTemplateLockedBytes $Lease 'task_template_rules' $policy.taskDerivation.rulesSha256)
 Assert-TaskTemplateKeys $rules 'format encoding files'
 if($rules.format-cne'i-core-task-two-slot-rules-v1'-or$rules.encoding-cne'UTF8-no-BOM'-or@($rules.files).Count-ne5){throw 'task_template_rules'}
 $ids=@('task_template_action','task_template_disabled_raw','task_template_enabled_raw','task_template_disabled_definition','task_template_enabled_definition')
 $names=@('action','disabledRaw','enabledRaw','disabledDefinition','enabledDefinition')
 $values=@{};$hashes=@{};$sources=@()
 for($n=0;$n-lt5;$n++){
  $rule=$rules.files[$n]
  if($rule.id-cne$ids[$n]){throw 'task_template_file_order'}
  $template=Get-TaskTemplateLockedBytes $Lease $ids[$n] $rule.templateSha256
  $bytes=Expand-TaskExactTwoSlots $rule $template $Lease.BindingSha256 $Lease.ApprovalSha256
  $values[$names[$n]]=$bytes;$hashes[$names[$n]]=Get-TaskTemplateHash $bytes
  $sources+=,[ordered]@{id=$ids[$n];templateSha256=$rule.templateSha256;instantiatedSha256=$hashes[$names[$n]];bytes=$bytes.Length}
 }
 $utf8=[Text.UTF8Encoding]::new($false,$true);$text=@{}
 foreach($name in $names){$text[$name]=$utf8.GetString($values[$name])}
 $line='    <Enabled>false</Enabled>'+[char]13+[char]10
 if($utf8.GetByteCount($line)-ne30-or[regex]::Matches($text.disabledRaw,[regex]::Escape($line)).Count-ne1-or$text.disabledRaw.Replace($line,'')-cne$text.enabledRaw){throw 'task_template_enabled_raw_delta'}
 if([regex]::Matches($text.disabledDefinition,'<Enabled>false</Enabled>').Count-ne1-or$text.disabledDefinition.Replace('<Enabled>false</Enabled>','<Enabled>true</Enabled>')-cne$text.enabledDefinition){throw 'task_template_enabled_definition_delta'}
 foreach($name in @('disabledRaw','enabledRaw')){if($text[$name].Contains('<Hidden>')){throw 'task_template_raw_hidden'}}
 foreach($name in @('disabledDefinition','enabledDefinition')){if([regex]::Matches($text[$name],'<Hidden>false</Hidden>').Count-ne1){throw 'task_template_definition_hidden'}}
 $arguments='<Arguments>'+$text.action.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;')+'</Arguments>'
 foreach($name in @('disabledRaw','enabledRaw','disabledDefinition','enabledDefinition')){if([regex]::Matches($text[$name],[regex]::Escape($arguments)).Count-ne1){throw 'task_template_action_disagreement'}}
 foreach($pair in @(@('taskSddl','new_task_sddl','taskSddlSha256'),@('parentSddl','parent_sddl','parentSddlSha256'))){
  $values[$pair[0]]=Get-TaskTemplateLockedBytes $Lease $pair[1] $policy.($pair[2])
  $hashes[$pair[0]]=Get-TaskTemplateHash $values[$pair[0]]
 }
 $derived=Read-P4StrictJson ($utf8.GetBytes(($policy|ConvertTo-Json -Depth 40 -Compress)))
 foreach($pair in @(@('expectedActionArguments',$text.action),@('expectedDisabledRawXmlSha256',$hashes.disabledRaw),@('expectedDisabledDefinitionSha256',$hashes.disabledDefinition),@('expectedEnabledRawXmlSha256',$hashes.enabledRaw),@('expectedEnabledDefinitionSha256',$hashes.enabledDefinition))){$derived|Add-Member NoteProperty $pair[0] $pair[1] -Force}
 $receipt=[ordered]@{format='i-core-task-two-slot-derivation-v1';evidenceMode=$Lease.Mode;bindingSha256=$Lease.BindingSha256;approvalSha256=$Lease.ApprovalSha256;activationPolicySha256=$Lease.Hash('activation_policy');rulesSha256=$policy.taskDerivation.rulesSha256;evaluatorSha256=$policy.taskDerivation.evaluatorSha256;derivedExpectedOnly=$true;actualObservation=$false;files=$sources;taskSddlSha256=$hashes.taskSddl;parentSddlSha256=$hashes.parentSddl}
 return @{Policy=$derived;Bytes=$values;Hashes=$hashes;Receipt=$receipt}
}
function Get-ReviewedActivationTaskPolicy {
 param([Parameter(Mandatory=$true)]$Lease)
 $policy=$Lease.ReadJson('activation_policy')
 if($policy.format-ceq'i-core-continuous-activation-policy-v1'){return $policy}
 return (Get-ReviewedActivationTaskTargets $Lease).Policy
}
