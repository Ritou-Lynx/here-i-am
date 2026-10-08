param([Parameter(Mandatory=$true)][string]$Repository,[Parameter(Mandatory=$true)][string]$FixtureRoot)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
. (Join-Path $PSScriptRoot 'ordinary_fixture.ps1');Invoke-OrdinaryFixtureIfElevated $PSCommandPath $PSBoundParameters
$env:PSModulePath=Join-Path $PSHOME 'Modules'
. (Join-Path $Repository 'tools/i_core/maintenance/preflight_approval_checks.ps1')
$checks=0
function Check([bool]$Value,[string]$Code){if(!$Value){throw $Code};$script:checks++}
function Reject([scriptblock]$Action,[string]$Code){$caught=$false;try{& $Action}catch{$caught=$true};Check $caught $Code}
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function Json([string]$p,$v){[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))}
$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$sections=[Security.AccessControl.AccessControlSections]::Owner-bor [Security.AccessControl.AccessControlSections]::Access
function Protect([string]$p){$a=[Security.AccessControl.DirectorySecurity]::new();$a.SetSecurityDescriptorSddlForm((New-PrivateSddl $true),$sections);Set-Acl -LiteralPath $p -AclObject $a}
Protect $FixtureRoot
$release=Join-Path $FixtureRoot 'release';$target=Join-Path $FixtureRoot 'target';$settings=Join-Path $FixtureRoot 'settings';$output=Join-Path $FixtureRoot 'rehearsal';$mcpSource=Join-Path $FixtureRoot 'mcp-source';$maintenance=Join-Path $FixtureRoot 'maintenance';$windowId='synthetic-online-approval';$window=Join-Path $maintenance ('windows\'+$windowId)
foreach($p in @($release,$target,$settings,$output,$mcpSource,$maintenance)){$null=[IO.Directory]::CreateDirectory($p);Protect $p}
$state=Join-Path $target 'state';$control=Join-Path $target 'control';$syntheticHome=Join-Path $target 'home';$mcpState=Join-Path $target 'mcp-state'
foreach($p in @($state,$control,$syntheticHome,$mcpState)){$null=[IO.Directory]::CreateDirectory($p)}
$memory=Join-Path $target 'synthetic-memory.sqlite';$policy=Join-Path $target 'synthetic-policy.json'
[IO.File]::WriteAllText($memory,'not a real database');[IO.File]::WriteAllText($policy,'{}')
# Root + four directories + two inputs + 137 filler files = exact 144 ACL rows.
for($i=0;$i-lt 137;$i++){[IO.File]::WriteAllText((Join-Path $target ('synthetic-'+$i+'.txt')),'synthetic')}
$rows=@(foreach($p in @((Get-Item -LiteralPath $target))+@(Get-ChildItem -LiteralPath $target -Recurse -Force)){$a=Get-Acl -LiteralPath $p.FullName;[pscustomobject]@{path=$p.FullName;directory=[bool]$p.PSIsContainer;owner=$a.GetOwner([Security.Principal.SecurityIdentifier]).Value;sddl=$a.GetSecurityDescriptorSddlForm($sections)}})
$snapshot=Join-Path $settings 'snapshot.json';Json $snapshot $rows
$files=@()
foreach($r in @('tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1','tools/i_core/release_schema6/lifecycle/mcp_configuration.ps1','tools/i_core/release_schema6/lifecycle/login_schema6.ps1')){$dest=Join-Path $release $r;$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest));[IO.File]::Copy((Join-Path $Repository $r),$dest);$files+=@{path=$r;sha256=(Hash $dest)}}
$manifestPath=Join-Path $release 'manifest.json';Json $manifestPath @{source_commit=('a'*40);files=$files};$manifestHash=Hash $manifestPath
$core=Join-Path $settings 'core.json';Json $core @{}
$dummy=Join-Path $settings 'synthetic-not-executable.exe';[IO.File]::WriteAllText($dummy,'synthetic only - must never execute')
$entry=Join-Path $mcpSource 'synthetic.mjs';[IO.File]::WriteAllText($entry,'throw new Error("must never execute");')
$mcp=Join-Path $settings 'mcp.json'
Json $mcp @{format='schema6-mcp-v1';owner_sid=$owner;executable_path=$dummy;executable_sha256=(Hash $dummy);working_directory=$mcpSource;entrypoint='synthetic.mjs';source_files=@(@{path='synthetic.mjs';sha256=(Hash $entry)});arguments=@();environment=@{I_REMOTE_MCP_STATE_DIR=$mcpState;I_HOME=$syntheticHome;I_MEMORY_DB=$memory;I_MEMORY_POLICY=$policy};database_path=(Join-Path $state 'i-core.sqlite');listen_host='127.0.0.1';listen_port=15442;grace_ms=100}
$loginPath=Join-Path $settings 'login.json'
Json $loginPath @{format='schema6-login-v1';owner_sid=$owner;release_directory=$release;manifest_sha256=$manifestHash;state_directory=$state;control_root=$control;core_configuration_path=$core;core_configuration_sha256=(Hash $core);core_port=15441;backup_configuration_path=$null;backup_configuration_sha256=$null;backup_key_directory=$null;backup_interval_seconds=60;mcp_configuration_path=$mcp;mcp_configuration_sha256=(Hash $mcp)}
$aclConfigPath=Join-Path $settings 'acl-config.json'
$aclConfig=[pscustomobject]@{format='schema6-preflight-acl-inputs-v1';windowId=$windowId;candidateSourceCommit=('a'*40);candidateManifestSha256=$manifestHash;snapshotPath=$snapshot;snapshotSha256=(Hash $snapshot);ownerSid=$owner;roots=@($target);expectedCount=144;expectedForeignOwnerCount=0}
Json $aclConfigPath $aclConfig;$aclHash=Hash $aclConfigPath
# No task or listener reads from ACL audit are allowed.
function Get-ScheduledTask {throw 'unexpected_task_read'}
function Get-NetTCPConnection {throw 'unexpected_listener_read'}
$audit=Invoke-PreflightAclAudit $aclConfigPath $aclHash
Check ($audit.passed -and $audit.expectedCount-eq 144 -and !$audit.guardAcquired -and !$audit.aclApplied -and !$audit.receiptWritten) 'acl_audit_failed'
Check (!(Test-Path -LiteralPath (Join-Path $maintenance 'active-window.guard'))) 'audit_wrote_guard'
[IO.File]::WriteAllText((Join-Path $target 'synthetic-0.txt'),'changed bytes are not ACL drift')
Check ((Invoke-PreflightAclAudit $aclConfigPath $aclHash).passed) 'acl_audit_read_data_bytes'
$new=Join-Path $target 'unexpected.txt';[IO.File]::WriteAllText($new,'preserve')
Reject {Invoke-PreflightAclAudit $aclConfigPath $aclHash} 'extra_inventory_accepted';Check (Test-Path -LiteralPath $new) 'drift_deleted';Remove-Item -LiteralPath $new
$link=Join-Path $FixtureRoot 'synthetic-hardlink';$null=New-Item -ItemType HardLink -Path $link -Target $memory
try{Reject {Invoke-PreflightAclAudit $aclConfigPath $aclHash} 'hardlink_accepted'}finally{Remove-Item -LiteralPath $link}
$templateSource=Get-Content -LiteralPath (Join-Path $Repository 'tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1') -Raw
$template=Get-PreflightPrepareTemplate $templateSource
Reject {Get-PreflightPrepareTemplate ($templateSource.Replace('$document.Save($stream)','$document.Save($stream); Start-Process calc.exe'))} 'template_injection_accepted'
Reject {Get-PreflightPrepareTemplate ($templateSource.Replace('IgnoreNew','Parallel'))} 'template_setting_drift_accepted'
$approvedPath=Join-Path $settings 'approved.xml'
$ReleaseDirectory=$release;$ManifestSha256=$manifestHash;$LoginConfigurationPath=$loginPath;$LoginConfigurationSha256=Hash $loginPath;$verified=@{owner_sid=$owner};$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe';$login=Join-Path $release 'tools/i_core/release_schema6/lifecycle/login_schema6.ps1';$OutputXml=$approvedPath
& ([scriptblock]::Create($template))
$service=New-Object -ComObject Schedule.Service;$service.Connect();$parent=[string]$service.GetFolder('\').GetSecurityDescriptor(7)
$registration='O:'+$owner+'G:SYD:(A;;FA;;;'+$owner+')(A;;FA;;;SY)(A;;FA;;;BA)'
$expected=Get-TaskPolicyExpectedSecurity $registration $parent $owner
$c=[pscustomobject]@{format='schema6-maintenance-login-config-v2';windowId=$windowId;candidateSourceCommit=('a'*40);candidateManifestSha256=$manifestHash;releaseDirectory=$release;ownerSid=$owner;taskName='SyntheticNeverRegistered';registrationSddl=$registration;expectedRegisteredSddl=$expected;parentSddlSha256=(Get-TaskSecuritySha256 $parent);taskSecurityPolicyVersion='windows-file-oi-v1';inheritedReadOnlyPrincipals=(Get-TaskInheritedReadOnlyPrincipals $expected $owner);approvedXmlPath=$approvedPath;approvedXmlSha256=(Hash $approvedPath);loginConfigurationPath=$loginPath;loginConfigurationSha256=(Hash $loginPath);ownerApprovalPath=(Join-Path $settings 'approval.json');ownerApprovalSha256=''}
$approval=@{format='schema6-task-artifacts-approved-for-preflight-v1';formalEntryAuthorized=$false;windowId=$windowId;candidateSourceCommit=$c.candidateSourceCommit;candidateManifestSha256=$manifestHash;task_name=$c.taskName;owner_sid=$owner;registration_sddl=$registration;expected_registered_sddl=$expected;parent_sddl_sha256=$c.parentSddlSha256;task_security_policy_version=$c.taskSecurityPolicyVersion;inherited_read_only_principals=$c.inheritedReadOnlyPrincipals;xml_review_sha256=$c.approvedXmlSha256;login_sha256=$c.loginConfigurationSha256;require_fixed_prepare_identical=$true}
Json $c.ownerApprovalPath $approval;$c.ownerApprovalSha256=Hash $c.ownerApprovalPath
$approval.formalEntryAuthorized=$true;Json $c.ownerApprovalPath $approval;$c.ownerApprovalSha256=Hash $c.ownerApprovalPath
Reject {Invoke-PreflightTaskApproval $c} 'formal_entry_approval_accepted'
$approval.formalEntryAuthorized=$false;Json $c.ownerApprovalPath $approval;$c.ownerApprovalSha256=Hash $c.ownerApprovalPath
$task=Invoke-PreflightTaskApproval $c;Check ($task.passed -and $task.comMemoryRoundtrip -and !$task.registered -and !$task.started) 'com_roundtrip_failed'
$rendered=Join-Path $output 'prepared.xml';$report=Invoke-PreflightPrepareTemplate $c $aclConfigPath $aclHash $rendered
Check ($report.passed -and $report.prepareTemplateBytesEqual -and !$report.productionPrepareInvoked -and $report.productionPrepareStillRequiresAclApply) 'prepare_report_false_claim'
Check ((Hash $rendered)-ceq (Hash $approvedPath)) 'prepare_bytes_changed'
Reject {Invoke-PreflightPrepareTemplate $c $aclConfigPath $aclHash $rendered} 'overwrite_accepted'
$wrong=$c.parentSddlSha256;$c.parentSddlSha256='0'*64
try{Reject {Invoke-PreflightTaskApproval $c} 'parent_hash_drift_accepted'}finally{$c.parentSddlSha256=$wrong}
Check (!(Test-Path -LiteralPath $window)) 'formal_window_created'
$local=Join-Path $FixtureRoot 'synthetic-encrypted-local.bin';$usb=Join-Path $FixtureRoot 'synthetic-encrypted-usb.bin';[IO.File]::WriteAllBytes($local,(New-Object byte[] 2097152));[IO.File]::Copy($local,$usb)
$pairs=@([pscustomobject]@{localPath=$local;usbPath=$usb;sha256=(Hash $local)})
$b=Invoke-PreflightBackupArtifacts $pairs;Check ($b.passed -and $b.filesVerified-eq 2 -and $b.bytesVerified-eq 4194304 -and !$b.volumeIdentityVerified) 'backup_stream_pair_failed'
[IO.File]::AppendAllText($usb,'drift');Reject {Invoke-PreflightBackupArtifacts $pairs} 'backup_drift_accepted'
# The ordinary dispatcher captures PowerShell's success stream. Console.WriteLine
# bypasses that stream in the detached limited process and loses the report.
Write-Output (@{passed=$true;checks=$checks;aclCount=144;syntheticOnly=$true;comMemoryRoundtrip=$true;productionPrepareInvoked=$false;registered=$false;started=$false}|ConvertTo-Json -Compress)
