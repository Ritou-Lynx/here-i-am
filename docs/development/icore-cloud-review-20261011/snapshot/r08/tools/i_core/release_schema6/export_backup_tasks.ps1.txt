param([switch]$Execute)
if(!$Execute){[Console]::Out.WriteLine('{"mode":"Plan","ioPerformed":false,"productionAuthorized":false}');return}
$ErrorActionPreference='Stop'
$env:PSModulePath=Join-Path $PSHOME 'Modules'
function Keys($v,[string]$names){if($null-eq$v-or$v-is[string]-or$v-is[array]-or((@($v.PSObject.Properties.Name|Sort-Object)-join',')-cne(@($names.Split(' ')|Sort-Object)-join','))){throw 'task_export_schema'}}
function Hash([byte[]]$bytes){$h=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($h.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}}
try{
 if($PSVersionTable.PSEdition-cne'Desktop'-or$PSVersionTable.PSVersion.Major-ne5-or[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName-cne'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'){throw 'task_export_runtime'}
 $raw=[Console]::In.ReadToEnd();if($raw.Length-gt4096){throw 'task_export_input'}
 $request=$raw|ConvertFrom-Json;Keys $request 'format requestNonce tasks'
 if($request.format-cne'i-core-backup-task-export-request-v1'-or$request.requestNonce-cnotmatch'^[a-f0-9-]{36}$'-or$request.tasks-isnot[array]-or$request.tasks.Count-ne2){throw 'task_export_request'}
 $names=@('HereIAm-iCoreSchema6-cleanclose-20261008-2c01de5b','HereIAm-iCoreSchema6-chatgpt-20261009-f90058f2')
 for($i=0;$i-lt2;$i++){Keys $request.tasks[$i] 'taskPath taskName';if($request.tasks[$i].taskPath-cne'\'-or$request.tasks[$i].taskName-cne$names[$i]){throw 'task_export_scope'}}
 $service=New-Object -ComObject Schedule.Service;$service.Connect();$folder=$service.GetFolder('\')
 $utf8=[Text.UTF8Encoding]::new($false,$true);$items=@()
 for($i=0;$i-lt2;$i++){
  $task=$folder.GetTask($names[$i]);if([string]$task.Path-cne('\'+$names[$i])-or[string]$task.Name-cne$names[$i]){throw 'task_export_identity'}
  $values=[ordered]@{raw=[string]$task.Xml;definition=[string]$task.Definition.XmlText;taskSddl=[string]$task.GetSecurityDescriptor(7);parentSddl=[string]$folder.GetSecurityDescriptor(7);cmdlet=[string](Export-ScheduledTask -TaskPath '\' -TaskName $names[$i])}
  $files=[ordered]@{};foreach($key in @('raw','definition','taskSddl','parentSddl','cmdlet')){
   $text=$values[$key];if($text.Length-lt1-or$text.Length-gt1048576){throw 'task_export_limit'}
   $bytes=$utf8.GetBytes($text);if($bytes.Length-gt1048576){throw 'task_export_limit'}
   $files[$key]=[ordered]@{bytes=$bytes.Length;sha256=Hash $bytes;base64=[Convert]::ToBase64String($bytes)}
  }
  if($files.raw.sha256-cne$files.cmdlet.sha256){throw 'task_export_disagrees'}
  $items+=[ordered]@{taskPath='\';taskName=$names[$i];actualPath=[string]$task.Path;files=$files}
 }
 $result=[ordered]@{format='i-core-backup-task-export-v1';requestNonce=$request.requestNonce;capturedUtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();tasks=$items}
 [Console]::Out.Write(($result|ConvertTo-Json -Depth 12 -Compress));exit 0
}catch{[Console]::Error.Write('{"code":"task_export_rejected"}');exit 2}
