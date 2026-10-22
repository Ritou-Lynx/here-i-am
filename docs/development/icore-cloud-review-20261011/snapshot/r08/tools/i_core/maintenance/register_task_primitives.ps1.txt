# Shared, source-reviewed Task Scheduler primitives. No registration on import.
Set-StrictMode -Version 2
function Read-ApprovedTaskXml([string]$Text) {
 $settings=New-Object Xml.XmlReaderSettings; $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit; $settings.XmlResolver=$null
 $sr=New-Object IO.StringReader($Text); $reader=[Xml.XmlReader]::Create($sr,$settings)
 try {$doc=New-Object Xml.XmlDocument; $doc.XmlResolver=$null; $doc.Load($reader)
  if($doc.DocumentElement.LocalName-cne 'Task' -or $doc.DocumentElement.NamespaceURI-cne 'http://schemas.microsoft.com/windows/2004/02/mit/task'){throw 'task_xml_root_rejected'}
  return ,$doc
 } finally {$reader.Dispose();$sr.Dispose()}
}
function Convert-TaskSid([string]$Value) {
 if($Value -match '^S-1-'){return ([Security.Principal.SecurityIdentifier]::new($Value)).Value}
 return ([Security.Principal.NTAccount]::new($Value)).Translate([Security.Principal.SecurityIdentifier]).Value
}
function Convert-TaskNode($Node) {
 # Namespace-qualified names prevent foreign namespace elements from comparing equal.
 $attrs=@($Node.Attributes|Where-Object {$_.NamespaceURI-ne 'http://www.w3.org/2000/xmlns/'}|ForEach-Object {$_.NamespaceURI+'|'+$_.LocalName+'='+$_.Value}|Sort-Object)
 $children=@($Node.ChildNodes|Where-Object {$_.NodeType-eq [Xml.XmlNodeType]::Element})
 if($children.Count){$content=@($children|ForEach-Object {Convert-TaskNode $_})}
 else {$v=[string]$Node.InnerText
  if($Node.LocalName-ceq 'UserId'){$v=Convert-TaskSid $v}
  elseif($Node.LocalName-in @('ExecutionTimeLimit','DeleteExpiredTaskAfter','Duration','WaitTimeout','Interval','Delay') -and $v){$v=([Xml.XmlConvert]::ToTimeSpan($v)).Ticks.ToString()}
  $content=@($v)
 }
 return ([ordered]@{name=$Node.NamespaceURI+'|'+$Node.LocalName;attributes=$attrs;content=$content}|ConvertTo-Json -Depth 40 -Compress)
}
function Get-TaskSections([string]$Text) {
 $doc=Read-ApprovedTaskXml $Text; $ns=New-Object Xml.XmlNamespaceManager($doc.NameTable);$ns.AddNamespace('t',$doc.DocumentElement.NamespaceURI)
 $result=[ordered]@{}
 foreach($name in @('Actions','Principals','Triggers','Settings')) {
  $nodes=$doc.SelectNodes('/t:Task/t:'+$name,$ns);if($nodes.Count-ne 1){throw 'task_xml_cardinality'}
  $result[$name]=Convert-TaskNode $nodes[0]
 }
 return $result
}
function Assert-TaskDefinition($Actual,$Expected) {
 # Both sides have passed through NewTask/registered Definition; COM materializes
 # default values. Never compare raw approved XML to normalized Scheduler XML.
  $normalizer=New-Object -ComObject 'Schedule.Service';$normalizer.Connect()
 $normalized=$normalizer.NewTask(0);$normalized.XmlText=$Actual.XmlText
 $a=Get-TaskSections $normalized.XmlText; $e=Get-TaskSections $Expected.XmlText
 foreach($section in @('Actions','Principals','Triggers','Settings')){if($a[$section]-cne $e[$section]){throw ('registered_'+$section.ToLowerInvariant()+'_changed')}}
 if($Actual.Actions.Count-ne $Expected.Actions.Count -or $Actual.Triggers.Count-ne $Expected.Triggers.Count){throw 'registered_cardinality_changed'}
 for($i=1;$i-le $Expected.Actions.Count;$i++){
  $aa=$Actual.Actions.Item($i);$ee=$Expected.Actions.Item($i)
  if($aa.Type-ne 0 -or $ee.Type-ne 0){throw 'exec_action_required'}
  foreach($p in @('Path','Arguments','WorkingDirectory')){if([string]$aa.$p-cne [string]$ee.$p){throw 'registered_action_changed'}}
 }
 foreach($p in @('LogonType','RunLevel','Id','DisplayName')){if([string]$Actual.Principal.$p-cne [string]$Expected.Principal.$p){throw 'registered_principal_changed'}}
 if((Convert-TaskSid $Actual.Principal.UserId)-cne (Convert-TaskSid $Expected.Principal.UserId)){throw 'registered_owner_changed'}
 foreach($p in @('AllowDemandStart','AllowHardTerminate','Compatibility','DeleteExpiredTaskAfter','DisallowStartIfOnBatteries','Enabled','ExecutionTimeLimit','Hidden','MultipleInstances','Priority','RestartCount','RestartInterval','RunOnlyIfIdle','RunOnlyIfNetworkAvailable','StartWhenAvailable','StopIfGoingOnBatteries','WakeToRun','UseUnifiedSchedulingEngine','DisallowStartOnRemoteAppSession')){
  if([string]$Actual.Settings.$p-cne [string]$Expected.Settings.$p){throw 'registered_settings_changed'}
 }
 foreach($p in @('IdleDuration','WaitTimeout','StopOnIdleEnd','RestartOnIdle')){if([string]$Actual.Settings.IdleSettings.$p-cne [string]$Expected.Settings.IdleSettings.$p){throw 'registered_idle_changed'}}
}
function Convert-TaskSecurity([string]$Sddl) {
 $sd=[Security.AccessControl.RawSecurityDescriptor]::new($Sddl)
 if($null-eq $sd.Owner -or $null-eq $sd.Group -or $null-eq $sd.DiscretionaryAcl -or $null-ne $sd.SystemAcl){throw 'task_security_shape_rejected'}
 # Scheduler may add an owner read ACE even when owner already has full control.
 # Collapse only allow ACEs with equal SID/flags; reject deny/object/callback ACEs.
 $rights=@{}
 foreach($ace in $sd.DiscretionaryAcl){
  if($ace -isnot [Security.AccessControl.CommonAce] -or $ace.AceQualifier-ne [Security.AccessControl.AceQualifier]::AccessAllowed -or $ace.IsCallback){throw 'task_security_ace_rejected'}
  $key=$ace.SecurityIdentifier.Value+'|'+[int]$ace.AceFlags
  if(!$rights.ContainsKey($key)){$rights[$key]=0};$rights[$key]=$rights[$key] -bor $ace.AccessMask
 }
 $aces=@($rights.Keys|Sort-Object|ForEach-Object {$_+'|'+$rights[$_]})
 return ([ordered]@{owner=$sd.Owner.Value;group=$sd.Group.Value;protected=[bool]($sd.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected);aces=$aces}|ConvertTo-Json -Compress)
}
function Assert-TaskAbsent($Folder,[string]$Name) {
 if($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}$'){throw 'task_name_rejected'}
 # Include hidden tasks; failure to enumerate never proves absence.
 $all=$Folder.GetTasks(1)
 for($i=1;$i-le $all.Count;$i++){if([string]$all.Item($i).Name-ieq $Name){throw 'existing_task_rejected'}}
}
function Assert-RegisteredTask($Task,$Expected,[string]$Name,[string]$Sddl) {
 if([string]$Task.Path-cne ('\'+$Name)){throw 'registered_path_changed'}
 Assert-TaskDefinition $Task.Definition $Expected
 if((Convert-TaskSecurity $Task.GetSecurityDescriptor(7))-cne (Convert-TaskSecurity $Sddl)){throw 'registered_sddl_changed'}
 if($Task.Enabled-ne $Expected.Settings.Enabled -or $Task.GetInstances(0).Count-ne 0){throw 'registered_state_changed'}
}
function New-ApprovedTask($Service,$Folder,[string]$Name,[string]$Xml,[string]$OwnerSid,[string]$Sddl) {
 Assert-TaskAbsent $Folder $Name
 $expected=$Service.NewTask(0);$expected.XmlText=$Xml
 if($expected.Principal.LogonType-ne 3 -or $expected.Principal.RunLevel-ne 0 -or (Convert-TaskSid $expected.Principal.UserId)-cne $OwnerSid){throw 'approved_principal_rejected'}
 $null=Convert-TaskSecurity $Sddl
 # TASK_CREATE only. A race with a competing creator fails without updating it.
 return $Folder.RegisterTask($Name,$Xml,2,$OwnerSid,$null,3,$Sddl)
}
