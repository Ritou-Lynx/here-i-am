#requires -Version 5.1
# Import-safe online approval checks. Never acquire the maintenance guard or
# produce freeze/ACL Apply/production Prepare receipts. All native target handles
# request READ_CONTROL only. XML output is a separate CreateNew rehearsal file.
. (Join-Path $PSScriptRoot 'owned_artifacts.ps1')
. (Join-Path $PSScriptRoot 'acl-cutover-maintenance.ps1')
. (Join-Path $PSScriptRoot 'register_task_primitives.ps1')
. (Join-Path $PSScriptRoot 'task_security_policy.ps1')

function Read-PreflightAnchoredBytes([string]$Path,[string]$Sha256) {
 if($Sha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'preflight_hash_required'}
 Assert-Plain $Path;Initialize-CutoverAclNative
 $identity=[CutoverAclNative]::Open($Path,$false)
 $stream=$null
 try {
  $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  $memory=[IO.MemoryStream]::new();try{$stream.CopyTo($memory);$bytes=$memory.ToArray()}finally{$memory.Dispose()}
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  if($hash-cne $Sha256){throw 'preflight_hash_changed'}
  return ,$bytes
 }finally{if($stream){$stream.Dispose()};$identity.Dispose()}
}
function Read-PreflightAnchoredJson([string]$Path,[string]$Sha256) {
 return ([Text.Encoding]::UTF8.GetString((Read-PreflightAnchoredBytes $Path $Sha256))|ConvertFrom-Json)
}
function Assert-PreflightFields($Value,[string[]]$Names) {
 if(@(Compare-Object @($Names|Sort-Object) @($Value.PSObject.Properties.Name|Sort-Object)).Count){throw 'preflight_fields_rejected'}
}
function Invoke-PreflightAclAudit {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][string]$ConfigPath,[Parameter(Mandatory=$true)][string]$ExpectedConfigSha256)
 $ErrorActionPreference='Stop'
 # The production Audit writer creates a guard and receipt. Reuse only its
 # read-only inventory, native identity, and owner/DACL comparison primitives.
 $config=Read-PreflightAnchoredJson $ConfigPath $ExpectedConfigSha256
 Assert-PreflightFields $config @('format','windowId','candidateSourceCommit','candidateManifestSha256','ownerSid','roots','expectedCount','expectedForeignOwnerCount','snapshotPath','snapshotSha256')
 if($config.format-cne 'schema6-preflight-acl-inputs-v1' -or $config.windowId-cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]{7,79}$' -or $config.candidateSourceCommit-cnotmatch '^[a-f0-9]{40}$' -or $config.candidateManifestSha256-cnotmatch '^[a-f0-9]{64}$'){throw 'preflight_acl_config_rejected'}
 if($config.expectedCount-isnot [int] -or $config.expectedCount-lt 1 -or $config.expectedForeignOwnerCount-isnot [int] -or $config.expectedForeignOwnerCount-lt 0 -or $config.expectedForeignOwnerCount-gt $config.expectedCount -or $config.roots-isnot [array] -or $config.roots.Count-lt 1){throw 'preflight_acl_scope_rejected'}
 $null=[Security.Principal.SecurityIdentifier]::new([string]$config.ownerSid)
 $seenRoots=@{}
 foreach($r in $config.roots){
  Assert-Plain $r
  if(!(Get-Item -LiteralPath $r -Force).PSIsContainer -or $r.TrimEnd('\')-eq [IO.Path]::GetPathRoot($r).TrimEnd('\') -or $seenRoots.ContainsKey($r)){throw 'preflight_acl_root_rejected'}
  foreach($other in $config.roots){if($r-cne $other -and $r.StartsWith($other+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'preflight_acl_roots_overlap'}}
  foreach($input in @($ConfigPath,$config.snapshotPath)){if($input.Equals($r,[StringComparison]::OrdinalIgnoreCase) -or $input.StartsWith($r+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'preflight_acl_input_inside_target'}}
  $seenRoots[$r]=$true
 }
 $null=Read-PreflightAnchoredBytes $ConfigPath $ExpectedConfigSha256
 $rows=@(Read-PreflightAnchoredJson $config.snapshotPath $config.snapshotSha256)
 $owner=[string]$config.ownerSid;$roots=@($config.roots)
 $sections=[Security.AccessControl.AccessControlSections]::Owner-bor [Security.AccessControl.AccessControlSections]::Access
 $held=@{};$targetHandles=@{};$seen=@{}
 Initialize-CutoverAclNative
 try {
  if($rows.Count-ne $config.expectedCount){throw 'snapshot_count_mismatch'}
  foreach($r in $rows){
   Assert-PreflightFields $r @('directory','owner','path','sddl')
   if($r.path-isnot [string] -or $r.directory-isnot [bool] -or !(Test-InScope $r.path) -or $seen.ContainsKey($r.path)){throw 'snapshot_scope_invalid'}
   Assert-Plain $r.path;$sd=[Security.AccessControl.RawSecurityDescriptor]::new([string]$r.sddl)
   if($sd.Owner.Value-cne $r.owner){throw 'snapshot_owner_mismatch'}
   $null=Owner-Dacl $r.sddl;$seen[$r.path]=$true
  }
  if(@($rows|Where-Object{$_.owner-cne $owner}).Count-ne $config.expectedForeignOwnerCount){throw 'snapshot_foreign_owner_count_mismatch'}
  foreach($r in $roots){if(!$seen.ContainsKey($r)){throw 'snapshot_root_missing'}}
  Assert-Inventory
  foreach($r in $rows){Hold-Path $r.path $false;if((Owner-Dacl (Read-OwnerDacl $r.path))-cne (Owner-Dacl $r.sddl)){throw 'baseline_acl_drift'}}
  Assert-Inventory
  # Recheck ACLs while names remain pinned. Online data size/mtime is deliberately
  # not an ACL invariant; the independent online DB/WAL observer covers bytes.
  foreach($r in $rows){if((Owner-Dacl (Read-OwnerDacl $r.path))-cne (Owner-Dacl $r.sddl)){throw 'baseline_acl_drift'}}
  return [pscustomobject]@{format='schema6-online-acl-audit-v1';passed=$true;inventoryExact=$true;ownerDaclExact=$true;expectedCount=$rows.Count;foreignOwnerCount=$config.expectedForeignOwnerCount;snapshotSha256=$config.snapshotSha256;configSha256=$ExpectedConfigSha256;targetContentsRead=$false;aclApplied=$false;guardAcquired=$false;receiptWritten=$false}
 }finally{foreach($h in $targetHandles.Values){$h.Dispose()};foreach($h in $held.Values){$h.Dispose()}}
}
function Assert-PreflightApprovalBindings($Config) {
 $approval=Read-PreflightAnchoredJson $Config.ownerApprovalPath $Config.ownerApprovalSha256
 if($approval.format-cne 'schema6-task-artifacts-approved-for-preflight-v1' -or $approval.formalEntryAuthorized-isnot [bool] -or $approval.formalEntryAuthorized -or $approval.PSObject.Properties.Name-contains 'approved_sddl'){throw 'preflight_approval_format_rejected'}
 $mapping=@{windowId='windowId';candidateSourceCommit='candidateSourceCommit';candidateManifestSha256='candidateManifestSha256';task_name='taskName';owner_sid='ownerSid';registration_sddl='registrationSddl';expected_registered_sddl='expectedRegisteredSddl';parent_sddl_sha256='parentSddlSha256';task_security_policy_version='taskSecurityPolicyVersion';xml_review_sha256='approvedXmlSha256';login_sha256='loginConfigurationSha256'}
 foreach($key in $mapping.Keys){if([string]$approval.$key-cne [string]$Config.($mapping[$key])){throw 'preflight_approval_binding_changed'}}
 if($approval.require_fixed_prepare_identical-isnot [bool] -or !$approval.require_fixed_prepare_identical){throw 'preflight_exact_prepare_required'}
 if(($approval.inherited_read_only_principals|ConvertTo-Json -Depth 6 -Compress)-cne ($Config.inheritedReadOnlyPrincipals|ConvertTo-Json -Depth 6 -Compress)){throw 'preflight_disclosure_changed'}
 $null=Read-PreflightAnchoredBytes $Config.loginConfigurationPath $Config.loginConfigurationSha256
 $xml=Read-PreflightAnchoredBytes $Config.approvedXmlPath $Config.approvedXmlSha256
 return ,$xml
}
function Invoke-PreflightTaskApproval {
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Config)
 $ErrorActionPreference='Stop'
 $bytes=Assert-PreflightApprovalBindings $Config
 $service=New-Object -ComObject Schedule.Service;$service.Connect()
 $parent=[string]$service.GetFolder('\').GetSecurityDescriptor(7)
 $policy=Assert-TaskSecurityPolicy $Config $parent
 $xml=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xfeff)
 $null=Read-ApprovedTaskXml $xml
 $expected=$service.NewTask(0);$expected.XmlText=$xml
 if($expected.Principal.LogonType-ne 3 -or $expected.Principal.RunLevel-ne 0 -or (Convert-TaskSid $expected.Principal.UserId)-cne $Config.ownerSid){throw 'preflight_principal_rejected'}
 $roundtrip=$service.NewTask(0);$roundtrip.XmlText=$expected.XmlText
 Assert-TaskDefinition $roundtrip $expected
 if((Get-TaskSecuritySha256 ([string]$service.GetFolder('\').GetSecurityDescriptor(7)))-cne $Config.parentSddlSha256){throw 'task_policy_parent_changed'}
 return [pscustomobject]@{format='schema6-online-task-approval-v1';passed=$true;approvedXmlSha256=$Config.approvedXmlSha256;registrationSddlSha256=$policy.registrationSddlSha256;expectedRegisteredSddlSha256=$policy.expectedRegisteredSddlSha256;parentSddlSha256=$policy.parentSddlSha256;comMemoryRoundtrip=$true;registered=$false;started=$false}
}
function Assert-PreflightPlannedProtectedPath([string]$Path,$Rows,[string]$OwnerSid,[switch]$Root) {
 Assert-Plain $Path;Initialize-CutoverAclNative
 if($Root -and !(Get-Item -LiteralPath $Path -Force).PSIsContainer){throw 'planned_root_directory_required'}
 $h=[CutoverAclNative]::Open($Path,$false);$h.Dispose()
 $matches=@($Rows|Where-Object{$_.path-ceq $Path})
 if($matches.Count-eq 1){
  if($Root -and !$matches[0].directory){throw 'planned_root_directory_required'}
  $owner=$OwnerSid;$sections=[Security.AccessControl.AccessControlSections]::Owner-bor [Security.AccessControl.AccessControlSections]::Access
  $planned=New-PrivateSddl ([bool]$matches[0].directory)
  if(([Security.AccessControl.RawSecurityDescriptor]::new($planned)).Owner.Value-cne $OwnerSid){throw 'planned_owner_rejected'}
  return
 }
 # Paths outside the pending ACL scope must already satisfy the production rule.
 $acl=Get-Acl -LiteralPath $Path
 if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value-cne $OwnerSid -or ($Root -and !$acl.AreAccessRulesProtected)){throw 'preflight_protected_owner_or_root_rejected'}
 $own=$false
 foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
  if($rule.AccessControlType-eq 'Allow'){
   if($rule.IdentityReference.Value-notin @($OwnerSid,'S-1-5-18','S-1-5-32-544')){throw 'preflight_protected_acl_rejected'}
   if($rule.IdentityReference.Value-ceq $OwnerSid -and ($rule.FileSystemRights-band [Security.AccessControl.FileSystemRights]::FullControl)-eq [Security.AccessControl.FileSystemRights]::FullControl){$own=$true}
  }
 }
 if(!$own){throw 'preflight_protected_control_required'}
}
function Get-PreflightPrepareTemplate([string]$Source) {
 # The hash is of the reviewed pure template, normalized only for checkout EOL.
 # It includes Quote-Argument and every statement through CreateNew XML Save.
 # No arbitrary candidate code runs even when its manifest is self-consistent.
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($Source,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw 'prepare_template_parse_rejected'}
 $functions=@($ast.FindAll({param($n)$n-is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name-ceq 'Quote-Argument'},$true))
 if($functions.Count-ne 1){throw 'prepare_template_function_rejected'}
 $start=$functions[0].Extent.StartOffset;$end=$Source.IndexOf('@{prepared=',$start)
 if($end-le $start){throw 'prepare_template_boundary_rejected'}
 $template=$Source.Substring($start,$end-$start).Replace("`r`n","`n").Trim()
 if((Get-TaskSecuritySha256 $template)-cne 'b93ceba2f804ef97b5a48e608f636552f56245605cbd8f116150d32efa78a489'){throw 'prepare_template_source_changed'}
 $ta=[Management.Automation.Language.Parser]::ParseInput($template,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw 'prepare_template_parse_rejected'}
 foreach($command in $ta.FindAll({param($n)$n-is [Management.Automation.Language.CommandAst]},$true)){
  if($command.GetCommandName()-cnotin @('Quote-Argument','ForEach-Object','New-Object')){throw 'prepare_template_command_rejected'}
  if($command.GetCommandName()-ceq 'New-Object' -and $command.CommandElements[1].Extent.Text-cnotin @('Xml.XmlDocument','Xml.XmlNamespaceManager')){throw 'prepare_template_object_rejected'}
 }
 foreach($call in $ta.FindAll({param($n)$n-is [Management.Automation.Language.InvokeMemberExpressionAst]},$true)){
  if($call.Member.Extent.Text-cnotin @('Contains','EndsWith','LoadXml','AddNamespace','SelectNodes','SelectSingleNode','Open','Save','Flush','Dispose')){throw 'prepare_template_method_rejected'}
 }
 return $template
}
function Invoke-PreflightPrepareTemplate {
 [CmdletBinding()]param([Parameter(Mandatory=$true)]$Config,[Parameter(Mandatory=$true)][string]$AclConfigPath,[Parameter(Mandatory=$true)][string]$AclConfigSha256,[Parameter(Mandatory=$true)][string]$OutputXml)
 $ErrorActionPreference='Stop'
 $null=Invoke-PreflightAclAudit $AclConfigPath $AclConfigSha256
 $acl=Read-PreflightAnchoredJson $AclConfigPath $AclConfigSha256
 foreach($key in @('windowId','candidateSourceCommit','candidateManifestSha256','ownerSid')){if($acl.$key-cne $Config.$key){throw 'preflight_acl_binding_changed'}}
 $rows=@(Read-PreflightAnchoredJson $acl.snapshotPath $acl.snapshotSha256)
 $approved=Assert-PreflightApprovalBindings $Config
 $loginConfig=Read-PreflightAnchoredJson $Config.loginConfigurationPath $Config.loginConfigurationSha256
 $fields=@('format','owner_sid','release_directory','manifest_sha256','state_directory','control_root','core_configuration_path','core_configuration_sha256','core_port','backup_configuration_path','backup_configuration_sha256','backup_key_directory','backup_interval_seconds','mcp_configuration_path','mcp_configuration_sha256')
 Assert-PreflightFields $loginConfig $fields
 if($loginConfig.format-cne 'schema6-login-v1' -or $loginConfig.owner_sid-cne $Config.ownerSid -or $loginConfig.release_directory-cne $Config.releaseDirectory -or $loginConfig.manifest_sha256-cne $Config.candidateManifestSha256){throw 'preflight_login_binding_changed'}
 if($loginConfig.core_port-isnot [int] -or $loginConfig.core_port-lt 1 -or $loginConfig.core_port-gt 65535 -or $loginConfig.backup_interval_seconds-isnot [int] -or $loginConfig.backup_interval_seconds-lt 10 -or $loginConfig.backup_interval_seconds-gt 86400){throw 'preflight_login_numeric_rejected'}
 if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value-cne $Config.ownerSid){throw 'preflight_owner_identity_changed'}
 foreach($p in @($loginConfig.state_directory,$loginConfig.control_root)){Assert-PreflightPlannedProtectedPath $p $rows $Config.ownerSid -Root}
 if($loginConfig.state_directory-ieq $loginConfig.control_root -or $loginConfig.state_directory.StartsWith($loginConfig.control_root+'\',[StringComparison]::OrdinalIgnoreCase) -or $loginConfig.control_root.StartsWith($loginConfig.state_directory+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'preflight_control_overlap'}
 foreach($pair in @(@($Config.loginConfigurationPath,$Config.loginConfigurationSha256),@($loginConfig.core_configuration_path,$loginConfig.core_configuration_sha256),@($loginConfig.mcp_configuration_path,$loginConfig.mcp_configuration_sha256))){Assert-PreflightPlannedProtectedPath $pair[0] $rows $Config.ownerSid;$null=Read-PreflightAnchoredJson $pair[0] $pair[1]}
 Assert-PreflightPlannedProtectedPath ([IO.Path]::GetDirectoryName($Config.loginConfigurationPath)) $rows $Config.ownerSid -Root
 if($loginConfig.backup_configuration_path){Assert-PreflightPlannedProtectedPath $loginConfig.backup_configuration_path $rows $Config.ownerSid;$null=Read-PreflightAnchoredJson $loginConfig.backup_configuration_path $loginConfig.backup_configuration_sha256;Assert-PreflightPlannedProtectedPath $loginConfig.backup_key_directory $rows $Config.ownerSid -Root}
 elseif($null-ne $loginConfig.backup_configuration_sha256 -or $null-ne $loginConfig.backup_key_directory){throw 'preflight_partial_backup_configuration'}
 # Reuse the fixed MCP declarative validator with local read-only planned-ACL
 # adapters. Its production implementation and production calls are unchanged.
 $manifest=Read-PreflightAnchoredJson (Join-Path $Config.releaseDirectory 'manifest.json') $Config.candidateManifestSha256
 if($manifest.source_commit-cne $Config.candidateSourceCommit){throw 'preflight_manifest_commit_changed'}
 Assert-PreflightPlannedProtectedPath $Config.releaseDirectory $rows $Config.ownerSid -Root
 $listed=@{}
 foreach($entry in $manifest.files){
  if($entry.path-isnot [string] -or $entry.path-cnotmatch '^[A-Za-z0-9_./-]+$' -or $entry.path.Contains('..') -or $entry.path.StartsWith('/') -or $entry.path.EndsWith('/') -or $listed.ContainsKey($entry.path)){throw 'preflight_release_inventory_rejected'}
  $listed[$entry.path]=$true;$target=Join-Path $Config.releaseDirectory $entry.path
  Assert-PreflightPlannedProtectedPath $target $rows $Config.ownerSid
  $null=Read-PreflightAnchoredBytes $target $entry.sha256
 }
 $actual=@()
 foreach($item in Get-ChildItem -LiteralPath $Config.releaseDirectory -Recurse -Force){
  Assert-PreflightPlannedProtectedPath $item.FullName $rows $Config.ownerSid
  if(!$item.PSIsContainer -and $item.FullName-cne (Join-Path $Config.releaseDirectory 'manifest.json')){$actual+= $item.FullName.Substring($Config.releaseDirectory.Length+1).Replace('\','/')}
 }
 if(@(Compare-Object @($listed.Keys|Sort-Object) @($actual|Sort-Object)).Count){throw 'preflight_release_inventory_changed'}
 $texts=@{}
 foreach($relative in @('tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1','tools/i_core/release_schema6/lifecycle/mcp_configuration.ps1')){
  $entry=@($manifest.files|Where-Object{$_.path-ceq $relative});if($entry.Count-ne 1){throw 'preflight_manifest_entry_required'}
  $texts[$relative]=[Text.Encoding]::UTF8.GetString((Read-PreflightAnchoredBytes (Join-Path $Config.releaseDirectory $relative) $entry[0].sha256))
 }
 $template=Get-PreflightPrepareTemplate $texts['tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1']
 # This validator is independently pinned to the reviewed maintenance source.
 if((Get-TaskSecuritySha256 ($texts['tools/i_core/release_schema6/lifecycle/mcp_configuration.ps1'].Replace("`r`n","`n")))-cne 'ebb412b25ef8e31a5523951e2a5feeeec8680eb164b70e51a64d92e02c9a48a3'){throw 'preflight_mcp_validator_changed'}
 function Assert-ProtectedPath([string]$Target,[switch]$Root){Assert-PreflightPlannedProtectedPath $Target $rows $Config.ownerSid -Root:$Root}
 function Open-BootstrapFile([string]$Target){Assert-ProtectedPath $Target;return [IO.File]::Open($Target,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)}
 . ([scriptblock]::Create($texts['tools/i_core/release_schema6/lifecycle/mcp_configuration.ps1']))
 $locks=@()
 try{$mcp=Read-Schema6McpConfiguration $loginConfig ([ref]$locks);if(!$mcp){throw 'preflight_managed_mcp_required'}}finally{foreach($h in $locks){$h.Dispose()}}
 if($OutputXml-cne [IO.Path]::GetFullPath($OutputXml) -or $OutputXml.Substring(2).Contains(':') -or (Test-Path -LiteralPath $OutputXml)){throw 'preflight_fresh_output_required'}
 $outParent=[IO.Path]::GetDirectoryName($OutputXml);Assert-PreflightPlannedProtectedPath $outParent @() $Config.ownerSid -Root
 foreach($root in @($acl.roots)+@($Config.releaseDirectory,[IO.Path]::GetDirectoryName($Config.loginConfigurationPath),[IO.Path]::GetDirectoryName($Config.approvedXmlPath))){if($OutputXml.Equals($root,[StringComparison]::OrdinalIgnoreCase) -or $OutputXml.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'preflight_output_scope_rejected'}}
 $ReleaseDirectory=$Config.releaseDirectory;$ManifestSha256=$Config.candidateManifestSha256;$LoginConfigurationPath=$Config.loginConfigurationPath;$LoginConfigurationSha256=$Config.loginConfigurationSha256
 $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe';$login=Join-Path $ReleaseDirectory 'tools/i_core/release_schema6/lifecycle/login_schema6.ps1'
 $verified=[pscustomobject]@{owner_sid=$loginConfig.owner_sid}
 # Exact reviewed template only: no ValidateOnly, no fixed Prepare process, no
 # registration, no production configuration writes, and no invented receipt.
 Assert-OwnedArtifactUnelevatedProcess $Config.ownerSid
 & ([scriptblock]::Create($template))
 $rendered=Read-PreflightAnchoredBytes $OutputXml $Config.approvedXmlSha256
 if([Convert]::ToBase64String($rendered)-cne [Convert]::ToBase64String($approved)){throw 'preflight_prepare_bytes_changed'}
 $task=Invoke-PreflightTaskApproval $Config
 return [pscustomobject]@{format='schema6-online-prepare-template-v1';passed=$true;productionPrepareInvoked=$false;productionPrepareStillRequiresAclApply=$true;prepareTemplateBytesEqual=$true;comMemoryRoundtrip=$task.comMemoryRoundtrip;registered=$false;started=$false;outputXmlSha256=$Config.approvedXmlSha256}
}

function Invoke-PreflightBackupArtifacts {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][object[]]$Artifacts)
 $ErrorActionPreference='Stop'
 if($Artifacts.Count-lt 1){throw 'preflight_backup_inventory_required'}
 Initialize-CutoverAclNative;$seen=@{};$total=0L
 foreach($item in $Artifacts){
  Assert-PreflightFields $item @('localPath','usbPath','sha256')
  if($item.sha256-cnotmatch '^[a-f0-9]{64}$' -or $item.localPath-ieq $item.usbPath){throw 'preflight_backup_pair_rejected'}
  foreach($p in @($item.localPath,$item.usbPath)){
   if($seen.ContainsKey($p)){throw 'preflight_backup_duplicate'};$seen[$p]=$true
   Assert-Plain $p;$native=[CutoverAclNative]::Open($p,$false);$stream=$null;$sha=$null
   try{
    $stream=[IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $sha=[Security.Cryptography.SHA256]::Create()
    $hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()
    if($hash-cne $item.sha256){throw 'preflight_backup_hash_changed'}
    $total+=$stream.Length
   }finally{if($sha){$sha.Dispose()};if($stream){$stream.Dispose()};$native.Dispose()}
  }
 }
 return [pscustomobject]@{format='schema6-online-backup-artifacts-v1';passed=$true;artifactPairs=$Artifacts.Count;filesVerified=$seen.Count;bytesVerified=$total;backupCreated=$false;restorationInvoked=$false;volumeIdentityVerified=$false}
}