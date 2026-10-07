# Independent pre-CREATE FILE inheritance oracle; never learns expectation from task readback.
function Get-IdentityExpectedSddl([string]$Registration,[string]$Parent,[string]$Owner) {
 $child=[Security.AccessControl.RawSecurityDescriptor]::new($Registration)
 $parentSd=[Security.AccessControl.RawSecurityDescriptor]::new($Parent)
 foreach($ace in $parentSd.DiscretionaryAcl){
  if(([int]$ace.AceFlags-band 1)-eq 0){continue}
  if($ace -isnot [Security.AccessControl.CommonAce] -or $ace.IsCallback -or $ace.AceQualifier-ne [Security.AccessControl.AceQualifier]::AccessAllowed){throw 'oracle_parent_shape_rejected'}
  $sid=$ace.SecurityIdentifier
  if($sid.Value-in @('S-1-3-0','S-1-3-1')){$sid=[Security.Principal.SecurityIdentifier]::new($Owner)}
  $mask=[long]$ace.AccessMask-band 0xffffffffL;$specific=$mask-band 0x0fffffffL
  foreach($pair in @(@(0x80000000L,0x00120089L),@(0x40000000L,0x00120116L),@(0x20000000L,0x001200a0L),@(0x10000000L,0x001f01ffL))){if($mask-band $pair[0]){$specific=$specific-bor $pair[1]}}
  $child.DiscretionaryAcl.InsertAce($child.DiscretionaryAcl.Count,[Security.AccessControl.CommonAce]::new([Security.AccessControl.AceFlags]::Inherited,[Security.AccessControl.AceQualifier]::AccessAllowed,[int]$specific,$sid,$false,$null))
 }
 return $child.GetSddlForm([Security.AccessControl.AccessControlSections]::All)
}
function New-IdentitySafeXml([string]$Original,[string]$Nonce) {
 $doc=Read-ApprovedTaskXml $Original;$ns=[Xml.XmlNamespaceManager]::new($doc.NameTable);$ns.AddNamespace('t',$doc.DocumentElement.NamespaceURI)
 $doc.SelectSingleNode('/t:Task/t:Triggers',$ns).RemoveAll()
 $doc.SelectSingleNode('/t:Task/t:Settings/t:Enabled',$ns).InnerText='false'
 $doc.SelectSingleNode('/t:Task/t:Actions/t:Exec/t:Command',$ns).InnerText=Join-Path $env:SystemRoot 'System32\cmd.exe'
 $doc.SelectSingleNode('/t:Task/t:Actions/t:Exec/t:Arguments',$ns).InnerText='/d /c exit 0'
 $registration=$doc.CreateElement('RegistrationInfo',$doc.DocumentElement.NamespaceURI)
 $source=$doc.CreateElement('Source',$doc.DocumentElement.NamespaceURI);$source.InnerText=$Nonce;$null=$registration.AppendChild($source);$null=$doc.DocumentElement.PrependChild($registration)
 # Undo exactly the documented safe edits and demand the four sections match.
 $roundtrip=$doc.Clone();$roundtrip.SelectSingleNode('/t:Task/t:Settings/t:Enabled',$ns).InnerText='true'
 $originalDoc=Read-ApprovedTaskXml $Original
 foreach($section in @('Actions','Triggers')){$target=$roundtrip.SelectSingleNode('/t:Task/t:'+$section,$ns);$null=$target.ParentNode.ReplaceChild($roundtrip.ImportNode($originalDoc.SelectSingleNode('/t:Task/t:'+$section,$ns),$true),$target)}
 $before=Get-TaskSections $Original;$after=Get-TaskSections $roundtrip.OuterXml
 foreach($section in @('Actions','Principals','Triggers','Settings')){if($before[$section]-cne $after[$section]){throw 'safe_derivation_extra_change'}}
 return $doc.OuterXml
}
function Remove-IdentityTask($Folder,[string]$Name,[string]$Nonce,[string]$Owner) {
 if($Name-cnotmatch '^HereIAm-Identity-[a-f0-9]{32}$'){throw 'cleanup_name_rejected'}
 $task=$Folder.GetTask($Name);$d=$task.Definition
 if($task.Path-cne ('\'+$Name) -or $d.RegistrationInfo.Source-cne $Nonce -or $task.Enabled -or $task.GetInstances(0).Count-ne 0 -or $d.Triggers.Count-ne 0 -or $d.Actions.Count-ne 1 -or (Convert-TaskSid $d.Principal.UserId)-cne $Owner){throw 'cleanup_binding_rejected'}
 $a=$d.Actions.Item(1)
 if($a.Type-ne 0 -or $a.Path-cne (Join-Path $env:SystemRoot 'System32\cmd.exe') -or $a.Arguments-cne '/d /c exit 0' -or $a.WorkingDirectory){throw 'cleanup_action_rejected'}
 $Folder.DeleteTask($Name,0);Assert-TaskAbsent $Folder $Name
}
