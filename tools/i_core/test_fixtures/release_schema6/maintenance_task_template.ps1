# Extract only the actual fixed template construction; never invoke its bootstrap.
param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$FixtureRoot)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
function Assert-Equal($Actual,$Expected,[string]$Code){if($Actual -cne $Expected){throw $Code}}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'template_parse_failed'}
$quote=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Quote-Argument'},$true))
if($quote.Count-ne 1){throw 'quote_function_not_unique'}
$body=$quote[0].Parent.Statements
$start=[Array]::IndexOf($body,$quote[0])
$end=@($body|Where-Object{$_ -is [Management.Automation.Language.TryStatementAst] -and $_.Extent.StartOffset-gt $quote[0].Extent.StartOffset -and $_.Extent.Text -match '\$document\.Save\(\$stream\)'})
if($start-lt 0 -or $end.Count-ne 1){throw 'template_block_not_unique'}
$last=[Array]::IndexOf($body,$end[0])
$construction=($body[$start..$last]|ForEach-Object{$_.Extent.Text}) -join "`n"
$block=[Management.Automation.Language.Parser]::ParseInput($construction,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'construction_parse_failed'}
# Fail closed if future edits put a launch, registration, or other command in this slice.
foreach($call in $block.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst]},$true)){
 if($call.GetCommandName() -cnotin @('New-Object','ForEach-Object','Quote-Argument')){throw 'construction_command_rejected'}
 if($call.GetCommandName() -ceq 'New-Object' -and $call.CommandElements[1].Extent.Text -cnotin @('Xml.XmlDocument','Xml.XmlNamespaceManager')){throw 'construction_object_rejected'}
}
foreach($call in $block.FindAll({param($n)$n -is [Management.Automation.Language.InvokeMemberExpressionAst]},$true)){
 if($call.Member.Extent.Text -cnotin @('Contains','EndsWith','LoadXml','AddNamespace','SelectNodes','SelectSingleNode','Open','Save','Flush','Dispose')){throw 'construction_method_rejected'}
}
if(-not [IO.Path]::IsPathRooted($FixtureRoot) -or -not [IO.Directory]::Exists($FixtureRoot)){throw 'synthetic_root_required'}
$ReleaseDirectory=Join-Path $FixtureRoot 'synthetic release & binding'
$LoginConfigurationPath=Join-Path $FixtureRoot 'synthetic config & binding.json'
$ManifestSha256='a'*64;$LoginConfigurationSha256='b'*64
$verified=@{owner_sid='S-1-5-21-111111111-222222222-333333333-1001'}
$ps=Join-Path $FixtureRoot 'synthetic powershell.exe'
$login=Join-Path $ReleaseDirectory 'tools/i_core/release_schema6/lifecycle/login_schema6.ps1'
$OutputXml=Join-Path $FixtureRoot 'prepared.xml'
if(Test-Path -LiteralPath $OutputXml){throw 'fresh_synthetic_output_required'}
Invoke-Expression $construction
$saved=New-Object Xml.XmlDocument;$saved.Load($OutputXml)
$ns=New-Object Xml.XmlNamespaceManager($saved.NameTable);$ns.AddNamespace('t',$saved.DocumentElement.NamespaceURI)
function Value([string]$XPath){$nodes=@($saved.SelectNodes($XPath,$ns));if($nodes.Count-ne 1){throw 'xml_node_not_unique'};return $nodes[0].InnerText}
$expectedSettings=[ordered]@{MultipleInstancesPolicy='IgnoreNew';DisallowStartIfOnBatteries='false';StopIfGoingOnBatteries='false';AllowHardTerminate='false';StartWhenAvailable='true';Enabled='true';Hidden='true';UseUnifiedSchedulingEngine='true';ExecutionTimeLimit='PT0S'}
Assert-Equal $saved.SelectSingleNode('/t:Task/t:Settings',$ns).ChildNodes.Count $expectedSettings.Count 'settings_count_changed'
foreach($key in $expectedSettings.Keys){Assert-Equal (Value ('/t:Task/t:Settings/t:'+$key)) $expectedSettings[$key] ('setting_changed_'+$key)}
Assert-Equal (Value '/t:Task/t:Principals/t:Principal/t:UserId') $verified.owner_sid 'owner_binding_changed'
Assert-Equal (Value '/t:Task/t:Principals/t:Principal/t:LogonType') 'InteractiveToken' 'logon_changed'
Assert-Equal (Value '/t:Task/t:Principals/t:Principal/t:RunLevel') 'LeastPrivilege' 'run_level_changed'
Assert-Equal (Value '/t:Task/t:Triggers/t:LogonTrigger/t:UserId') $verified.owner_sid 'trigger_owner_changed'
Assert-Equal (Value '/t:Task/t:Triggers/t:LogonTrigger/t:Enabled') 'true' 'trigger_enabled_changed'
Assert-Equal (Value '/t:Task/t:Actions/t:Exec/t:Command') $ps 'command_binding_changed'
# Independent expected argument serialization, not the production quote helper.
$expectedArguments='"-NoProfile" "-NonInteractive" "-WindowStyle" "Hidden" "-ExecutionPolicy" "Bypass" "-File" "'+$login+'" "-ReleaseDirectory" "'+$ReleaseDirectory+'" "-ManifestSha256" "'+$ManifestSha256+'" "-LoginConfigurationPath" "'+$LoginConfigurationPath+'" "-LoginConfigurationSha256" "'+$LoginConfigurationSha256+'"'
Assert-Equal (Value '/t:Task/t:Actions/t:Exec/t:Arguments') $expectedArguments 'argument_binding_changed'
# NewTask returns an in-memory definition. No folder/task discovery or persistence API.
$scheduler=$null;$definition=$null
try{
 $scheduler=New-Object -ComObject 'Schedule.Service';$scheduler.Connect()
 $definition=$scheduler.NewTask(0);$definition.XmlText=$saved.OuterXml
 Assert-Equal $definition.Settings.UseUnifiedSchedulingEngine $true 'com_unified_changed'
 Assert-Equal $definition.Settings.MultipleInstances 2 'com_instances_changed'
 foreach($name in @('DisallowStartIfOnBatteries','StopIfGoingOnBatteries','AllowHardTerminate')){Assert-Equal $definition.Settings.$name $false ('com_setting_changed_'+$name)}
 foreach($name in @('StartWhenAvailable','Enabled','Hidden')){Assert-Equal $definition.Settings.$name $true ('com_setting_changed_'+$name)}
 Assert-Equal $definition.Settings.ExecutionTimeLimit 'PT0S' 'com_time_limit_changed'
 Assert-Equal $definition.Principal.LogonType 3 'com_logon_changed'
 Assert-Equal $definition.Principal.RunLevel 0 'com_run_level_changed'
 Assert-Equal $definition.Principal.UserId $verified.owner_sid 'com_owner_changed'
 Assert-Equal $definition.Triggers.Count 1 'com_trigger_count_changed'
 Assert-Equal $definition.Triggers.Item(1).Type 9 'com_trigger_type_changed'
 Assert-Equal $definition.Triggers.Item(1).UserId $verified.owner_sid 'com_trigger_owner_changed'
 Assert-Equal $definition.Triggers.Item(1).Enabled $true 'com_trigger_enabled_changed'
 Assert-Equal $definition.Actions.Count 1 'com_action_count_changed'
 Assert-Equal $definition.Actions.Context 'Owner' 'com_action_context_changed'
 Assert-Equal $definition.Actions.Item(1).Type 0 'com_action_type_changed'
 Assert-Equal $definition.Actions.Item(1).Path $ps 'com_command_binding_changed'
 Assert-Equal $definition.Actions.Item(1).Arguments $expectedArguments 'com_argument_binding_changed'
 [ordered]@{passed=$true;actualTemplateExtracted=$true;savedXmlValidated=$true;comMemoryValidated=$true;settingsPreserved=$true;bindingsValidated=$true;taskCreates=0;taskStarts=0;taskDeletes=0;powerShellVersion=$PSVersionTable.PSVersion.ToString()}|ConvertTo-Json -Compress
}finally{
 if($null-ne $definition){$null=[Runtime.InteropServices.Marshal]::FinalReleaseComObject($definition)}
 if($null-ne $scheduler){$null=[Runtime.InteropServices.Marshal]::FinalReleaseComObject($scheduler)}
}
