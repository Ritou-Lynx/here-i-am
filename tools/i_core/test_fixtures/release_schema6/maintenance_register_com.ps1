# Real COM acceptance fixture; one disabled, triggerless, uniquely named task.
param([Parameter(Mandatory=$true)][string]$PrimitivesPath,[string]$OutputReport)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
. $PrimitivesPath
$s=New-Object -ComObject 'Schedule.Service';$s.Connect();$folder=$s.GetFolder('\')
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$name='HereIAm-Synthetic-'+[Guid]::NewGuid().ToString('N');$nonce=[Guid]::NewGuid().ToString('N')
$sddl='O:'+ $sid +'G:'+ $sid +'D:(A;;FA;;;'+ $sid +')(A;;FA;;;SY)(A;;FA;;;BA)'
$doc=Read-ApprovedTaskXml '<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><RegistrationInfo><Source /></RegistrationInfo><Triggers /><Principals><Principal id="Owner"><UserId /><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals><Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>false</AllowHardTerminate><StartWhenAvailable>false</StartWhenAvailable><Enabled>false</Enabled><Hidden>true</Hidden><UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine><ExecutionTimeLimit>PT1M</ExecutionTimeLimit></Settings><Actions Context="Owner"><Exec><Command /><Arguments>/d /c exit 0</Arguments></Exec></Actions></Task>'
$ns=New-Object Xml.XmlNamespaceManager($doc.NameTable);$ns.AddNamespace('t',$doc.DocumentElement.NamespaceURI)
$doc.SelectSingleNode('//t:UserId',$ns).InnerText=$sid
$doc.SelectSingleNode('//t:Command',$ns).InnerText=Join-Path $env:SystemRoot 'System32\cmd.exe'
$doc.SelectSingleNode('//t:Source',$ns).InnerText=$nonce
function Get-SyntheticSecurityShape([string]$Text){
 $sd=[Security.AccessControl.RawSecurityDescriptor]::new($Text)
 function Alias([Security.Principal.SecurityIdentifier]$Value){if($null-eq $Value){return 'NONE'};switch($Value.Value){$sid{return 'OWNER'} 'S-1-5-18'{return 'SYSTEM'} 'S-1-5-32-544'{return 'ADMIN'} default{return 'OTHER'}}}
 $aces=@($sd.DiscretionaryAcl|ForEach-Object{@{principal=(Alias $_.SecurityIdentifier);type=[string]$_.AceType;flags=[int]$_.AceFlags;mask=('{0:X8}'-f $_.AccessMask)}})
 return @{owner=(Alias $sd.Owner);group=(Alias $sd.Group);protected=[bool]($sd.ControlFlags-band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected);autoInherited=[bool]($sd.ControlFlags-band [Security.AccessControl.ControlFlags]::DiscretionaryAclAutoInherited);autoInheritRequired=[bool]($sd.ControlFlags-band [Security.AccessControl.ControlFlags]::DiscretionaryAclAutoInheritRequired);aces=$aces}
}
$xml=$doc.OuterXml;$expected=$s.NewTask(0);$expected.XmlText=$xml
$created=$null;$result=[ordered]@{format='schema6-synthetic-register-test-v1';created=$false;readback=$false;existingRejected=$false;xmlDifferenceRejected=$false;deleted=$false;noInstances=$false;disabled=$true;triggers=0;taskPrefix='HereIAm-Synthetic-';startedUtc=[DateTime]::UtcNow.ToString('o')}
try {
 $created=New-ApprovedTask $s $folder $name $xml $sid $sddl;$result.created=$true
 $live=$folder.GetTask($name)
 # Anonymous diagnostics are evidence only; never replace the pre-CREATE expectation.
 $result.expectedSecurity=Get-SyntheticSecurityShape $sddl
 $result.actualSecurity=Get-SyntheticSecurityShape $live.GetSecurityDescriptor(7)
 Assert-RegisteredTask $live $expected $name $sddl;$result.readback=$true
 $result.noInstances=($live.GetInstances(0).Count-eq 0)
 if($live.Enabled -or $live.Definition.Triggers.Count-ne 0){throw 'synthetic_safety_failed'}
 try{$null=New-ApprovedTask $s $folder $name $xml $sid $sddl;throw 'existing_task_was_accepted'}catch{if($_.Exception.Message-cne 'existing_task_rejected'){throw};$result.existingRejected=$true}
 $changed=$s.NewTask(0);$changed.XmlText=$xml;$changed.Actions.Item(1).Arguments='/d /c exit 1'
 try{Assert-TaskDefinition $live.Definition $changed;throw 'xml_difference_was_accepted'}catch{if($_.Exception.Message-notmatch '^registered_(actions|action)_changed$'){throw};$result.xmlDifferenceRejected=$true}
} finally {
 if($null-ne $created){
  $bound=$folder.GetTask($name)
  # No deletion on unconfirmed creation or binding drift. A replacement task is
  # left alone; cleanup failure is visible, never promoted to a passing receipt.
  if($name-notmatch '^HereIAm-Synthetic-[a-f0-9]{32}$' -or $bound.Definition.RegistrationInfo.Source-cne $nonce -or $bound.Enabled -or $bound.GetInstances(0).Count-ne 0){throw 'synthetic_cleanup_binding_rejected'}
  # Cleanup binding is intentionally independent of the assertion under test:
  # an OS readback discrepancy must not strand our safe synthetic task.
  if($bound.Path-cne ('\'+$name) -or $bound.Definition.Triggers.Count-ne 0 -or $bound.Definition.Actions.Count-ne 1 -or (Convert-TaskSid $bound.Definition.Principal.UserId)-cne $sid){throw 'synthetic_cleanup_shape_rejected'}
  $action=$bound.Definition.Actions.Item(1)
  if($action.Type-ne 0 -or $action.Path-cne (Join-Path $env:SystemRoot 'System32\cmd.exe') -or $action.Arguments-cne '/d /c exit 0' -or $action.WorkingDirectory){throw 'synthetic_cleanup_action_rejected'}
  $folder.DeleteTask($name,0);Assert-TaskAbsent $folder $name;$result.deleted=$true
 }
 $result.completedUtc=[DateTime]::UtcNow.ToString('o')
 $encoded=$result|ConvertTo-Json -Depth 8 -Compress
 if($OutputReport){$bytes=[Text.UTF8Encoding]::new($false).GetBytes($encoded+"`n");$h=[IO.File]::Open($OutputReport,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$h.Write($bytes,0,$bytes.Length);$h.Flush($true)}finally{$h.Dispose()}}
 [Console]::Out.WriteLine($encoded)
}
