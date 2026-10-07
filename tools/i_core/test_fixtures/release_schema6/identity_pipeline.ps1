param([Parameter(Mandatory=$true)][string]$Repository,[Parameter(Mandatory=$true)][string]$OutputReport)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
. (Join-Path $PSScriptRoot 'module_scope.ps1')
Assert-Schema6ModuleScopeHost
Add-Type -Path (Join-Path $PSScriptRoot 'identity_token.cs')
$report=[ordered]@{format='schema6-identity-pipeline-v1';passed=$false;writer=[Schema6IdentityToken]::Current();consumer=$null;aclCount=0;foreignOwnerCount=0;fixedPrepare=$false;registrationValidation=$false;syntheticRegistered=$false;comReadback=$false;deleted=$false;frozenTaskDeleted=$false;productionRegisterOuterExecuted=$false;expectedSecuritySource='independent-file-inheritance-before-create';syntheticOnly=$true}
$root=$null;$created=$false;$frozenCreated=$false;$folder=$null
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Json([string]$Path,$Value){Write-OwnedArtifactBytes $Path ([Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 20))) $owner}
function Protect-Setup([string]$Path){
 $item=Get-Item -LiteralPath $Path -Force
 $a=if($item.PSIsContainer){[Security.AccessControl.DirectorySecurity]::new()}else{[Security.AccessControl.FileSecurity]::new()}
 $flags=if($item.PSIsContainer){'OICI'}else{''}
 $a.SetSecurityDescriptorSddlForm(('O:'+$owner+'D:P(A;'+$flags+';FA;;;'+$owner+')(A;'+$flags+';FA;;;SY)(A;'+$flags+';FA;;;BA)'))
 Set-Acl -LiteralPath $Path -AclObject $a
}
try {
 if(!$report.writer.elevated -or !$report.writer.administrator -or $report.writer.owner-cne 'S-1-5-32-544' -or $report.writer.integritySid-cne 'S-1-16-12288'){throw 'real_elevated_admin_default_owner_required'}
 $owner=$report.writer.sid
 $node=(Get-Command node.exe -ErrorAction Stop).Source;$gitLauncher=(Get-Command git.exe -ErrorAction Stop).Source
 # Installed launchers may be hardlinks; use the existing core executable,
 # still subject to prepareRelease's canonical single-link checks.
 $gitCore=& $gitLauncher --exec-path;if($LASTEXITCODE-ne 0){throw 'git_core_discovery_failed'}
 $git=Join-Path ([IO.Path]::GetFullPath(($gitCore-join '').Replace('/','\'))) 'git.exe'
 $raw=& $node (Join-Path $PSScriptRoot 'identity_assemble.mjs') $Repository $git
 if($LASTEXITCODE-ne 0){throw 'real_candidate_assembly_failed'}
 $assembly=($raw-join '')|ConvertFrom-Json;$root=$assembly.root;$release=$assembly.release;$maintenance=$assembly.maintenance
 $report.sourceCommit=$assembly.source_commit;$report.candidateManifestSha256=$assembly.manifest_sha256
 if([IO.Path]::GetFileName($root)-cnotmatch '^schema6-identity-[A-Za-z0-9]+$' -or $assembly.files-ne 47){throw 'synthetic_root_or_inventory_rejected'}
 . (Join-Path $maintenance 'owned_artifacts.ps1')
 # Setup copies only. Never repair the ACL receipt or any actual writer output.
 Protect-Setup $root;foreach($p in Get-ChildItem -LiteralPath $root -Recurse -Force){Protect-Setup $p.FullName}
 . (Join-Path $maintenance 'acl-cutover-maintenance.ps1')
 . (Join-Path $maintenance 'preflight_approval_checks.ps1')
 . (Join-Path $maintenance 'register_task_primitives.ps1')
 . (Join-Path $maintenance 'task_security_policy.ps1')
 . (Join-Path $PSScriptRoot 'identity_task_oracle.ps1')
 $maint=Join-Path $root 'maintenance';$windowId='identity-'+[Guid]::NewGuid().ToString('N');$window=Join-Path $maint ('windows\'+$windowId)
 $target=Join-Path $root 'target';$settings=Join-Path $root 'settings';$source=Join-Path $root 'mcp-source'
 foreach($p in @($maint,(Join-Path $maint 'windows'),$window,$target,$settings,$source)){New-OwnedArtifactDirectory $p $owner}
 $state=Join-Path $target 'state';$control=Join-Path $target 'control';$homeDir=Join-Path $target 'home';$mcpState=Join-Path $target 'mcp-state'
 foreach($p in @($state,$control,$homeDir,$mcpState)){New-OwnedArtifactDirectory $p $owner}
 $memory=Join-Path $target 'synthetic-memory.sqlite';$policy=Join-Path $target 'synthetic-policy.json'
 Json $memory @{};Json $policy @{}
 for($i=0;$i-lt 137;$i++){Json (Join-Path $target ('synthetic-'+$i+'.json')) @{synthetic=$true}}
 Initialize-CutoverAclNative;$privilege=[CutoverAclNative+Privilege]::new()
 try{for($i=0;$i-lt 16;$i++){$p=Join-Path $target ('synthetic-'+$i+'.json');$h=[CutoverAclNative]::Open($p,$true);try{[CutoverAclNative]::SetOwnerDacl($h,('O:BAD:P(A;;FA;;;'+$owner+')(A;;FA;;;SY)(A;;FA;;;BA)'),$true)}finally{$h.Dispose()}}}finally{$privilege.Dispose()}
 $sections=[Security.AccessControl.AccessControlSections]::Owner-bor [Security.AccessControl.AccessControlSections]::Access
 $rows=@(foreach($p in @((Get-Item -LiteralPath $target))+@(Get-ChildItem -LiteralPath $target -Recurse -Force)){$acl=Get-Acl -LiteralPath $p.FullName;@{path=$p.FullName;directory=[bool]$p.PSIsContainer;owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value;sddl=$acl.GetSecurityDescriptorSddlForm($sections)}})
 if($rows.Count-ne 144 -or @($rows|Where-Object{$_.owner-cne $owner}).Count-ne 16){throw 'exact_inventory_required'}
 $snapshot=Join-Path $window 'snapshot.json';Json $snapshot $rows
 $core=Join-Path $settings 'core.json';Json $core @{}
 $entry=Join-Path $source 'synthetic.mjs';Write-OwnedArtifactBytes $entry ([Text.UTF8Encoding]::new($false).GetBytes('throw new Error("synthetic source must never run");')) $owner
 # Obtain two currently unused ephemeral ports without reserving production ports.
 $ports=@();for($i=0;$i-lt 2;$i++){$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$listener.Start();$ports+= $listener.LocalEndpoint.Port;$listener.Stop()}
 if($ports[0]-eq $ports[1]){throw 'distinct_ports_required'}
 $mcp=Join-Path $settings 'mcp.json'
 Json $mcp @{format='schema6-mcp-v1';owner_sid=$owner;executable_path=(Join-Path $release 'runtime\node.exe');executable_sha256=(Hash (Join-Path $release 'runtime\node.exe'));working_directory=$source;entrypoint='synthetic.mjs';source_files=@(@{path='synthetic.mjs';sha256=(Hash $entry)});arguments=@();environment=@{I_REMOTE_MCP_STATE_DIR=$mcpState;I_MEMORY_DB=$memory;I_MEMORY_POLICY=$policy;I_HOME=$homeDir};database_path=(Join-Path $state 'i-core.sqlite');listen_host='127.0.0.1';listen_port=$ports[1];grace_ms=100}
 $loginPath=Join-Path $window 'login.json'
 Json $loginPath @{format='schema6-login-v1';owner_sid=$owner;release_directory=$release;manifest_sha256=$assembly.manifest_sha256;state_directory=$state;control_root=$control;core_configuration_path=$core;core_configuration_sha256=(Hash $core);core_port=$ports[0];backup_configuration_path=$null;backup_configuration_sha256=$null;backup_key_directory=$null;backup_interval_seconds=60;mcp_configuration_path=$mcp;mcp_configuration_sha256=(Hash $mcp)}
 # Known, source-reviewed pure template is pinned independently of execution.
 $template=Get-PreflightPrepareTemplate (Get-Content -LiteralPath (Join-Path $release 'tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1') -Raw)
 $approved=Join-Path $window 'approved.xml';$ReleaseDirectory=$release;$ManifestSha256=$assembly.manifest_sha256;$LoginConfigurationPath=$loginPath;$LoginConfigurationSha256=Hash $loginPath;$verified=@{owner_sid=$owner};$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe';$login=Join-Path $release 'tools/i_core/release_schema6/lifecycle/login_schema6.ps1';$OutputXml=$approved
 & ([scriptblock]::Create($template));Protect-Setup $approved
 $service=New-Object -ComObject Schedule.Service;$service.Connect();$folder=$service.GetFolder('\');$parent=$folder.GetSecurityDescriptor(7)
 $registration='O:'+$owner+'G:'+$owner+'D:(A;;FA;;;'+$owner+')(A;;FA;;;SY)(A;;FA;;;BA)'
 $expected=Get-IdentityExpectedSddl $registration $parent $owner
 if((Convert-TaskSecurity $expected)-cne (Convert-TaskSecurity (Get-TaskPolicyExpectedSecurity $registration $parent $owner))){throw 'independent_security_oracle_mismatch'}
 $frozenName='HereIAm-Identity-'+[Guid]::NewGuid().ToString('N');$frozenNonce=[Guid]::NewGuid().ToString('N')
 $safe=New-IdentitySafeXml ([IO.File]::ReadAllText($approved)) $frozenNonce
 $null=New-ApprovedTask $service $folder $frozenName $safe $owner $registration;$frozenCreated=$true
 $frozenTask=$folder.GetTask($frozenName);$frozenDefinition=$service.NewTask(0);$frozenDefinition.XmlText=$safe;Assert-RegisteredTask $frozenTask $frozenDefinition $frozenName $expected
 $taskProof=Read-AclFrozenTaskState ([pscustomobject]@{name=$frozenName;taskPath='\'})
 $observed=[Diagnostics.Stopwatch]::StartNew();while($observed.ElapsedMilliseconds-lt 65000){Start-Sleep -Milliseconds 1000}
 Assert-AclFrozenTaskState $taskProof (Read-AclFrozenTaskState $taskProof)
 $frozenPath=Join-Path $window 'frozen.json';$rawPaths=@('','-wal','-shm','-journal')|ForEach-Object{(Join-Path $state 'i-core.sqlite')+$_}
 $externalPath=Join-Path $settings 'synthetic-approval.json';Json $externalPath @{}
 $start=[DateTime]::UtcNow.ToString('o');$end=[DateTime]::UtcNow.AddMinutes(30).ToString('o')
 $taskRow=@{};foreach($property in $taskProof.PSObject.Properties){$taskRow[$property.Name]=$property.Value};$taskRow.originalXmlSha256=$taskProof.frozenXmlSha256
 Json $frozenPath @{format='schema6-frozen-legacy-runtime-ready-v2';passed=$true;windowId=$windowId;windowDirectory=$window;candidateSourceCommit=$assembly.source_commit;candidateManifestSha256=$assembly.manifest_sha256;approvedXmlSha256=(Hash $approved);databaseReplaced=$false;aclApplied=$false;observationMs=$observed.ElapsedMilliseconds;createdUtc=$start;expiresUtc=$end;tasks=@($taskRow);portsFree=$ports;rawAfter=@($rawPaths|ForEach-Object{@{path=$_;exists=$false}});external=@{approvals=@{sha256=(Hash $externalPath);size=(Get-Item -LiteralPath $externalPath).Length}}}
 $aclPath=Join-Path $window 'acl-apply.json';$aclConfig=Join-Path $window 'acl-config.json'
 Json $aclConfig @{format='schema6-acl-config-v1';windowId=$windowId;candidateSourceCommit=$assembly.source_commit;candidateManifestSha256=$assembly.manifest_sha256;maintenanceRoot=$maint;baseDirectory=$window;snapshotPath=$snapshot;snapshotSha256=(Hash $snapshot);ownerSid=$owner;roots=@($target);expectedCount=144;expectedForeignOwnerCount=16;taskNames=@('\'+$frozenName);ports=$ports;frozenReceiptPath=$frozenPath;frozenReceiptSha256=(Hash $frozenPath);receiptPath=$aclPath}
 # Real writer, untouched elevated token with BA default owner, actual 144-item Apply.
 $apply=Invoke-AclMaintenance -ConfigPath $aclConfig -ExpectedConfigSha256 (Hash $aclConfig) -ExpectedOwnedArtifactsSha256 (Hash (Join-Path $maintenance 'owned_artifacts.ps1')) -Mode Apply -ConfirmFrozen
 if(!$apply.passed -or $apply.exitCode-ne 0){throw ('real_apply_failed:'+($apply.result|ConvertTo-Json -Depth 3 -Compress))}
 Assert-OwnedArtifact $aclPath $owner
 $report.aclCount=$apply.result.verified_count;$report.foreignOwnerCount=$apply.result.expected_foreign_owner_count
 $report.aclReceiptSha256=Hash $aclPath;$report.aclReceiptOwner=(Get-Acl -LiteralPath $aclPath).GetOwner([Security.Principal.SecurityIdentifier]).Value
 $name='HereIAm-Identity-'+[Guid]::NewGuid().ToString('N');$nonce=[Guid]::NewGuid().ToString('N')
 $c=[ordered]@{format='schema6-maintenance-login-config-v2';windowId=$windowId;candidateSourceCommit=$assembly.source_commit;candidateManifestSha256=$assembly.manifest_sha256;ownerSid=$owner;taskName=$name;releaseDirectory=$release;maintenanceRoot=$maint;registrationSddl=$registration;expectedRegisteredSddl=$expected;parentSddlSha256=(Get-TaskSecuritySha256 $parent);taskSecurityPolicyVersion='windows-file-oi-v1';inheritedReadOnlyPrincipals=@(Get-TaskInheritedReadOnlyPrincipals $expected $owner);approvedXmlPath=$approved;approvedXmlSha256=(Hash $approved);loginConfigurationPath=$loginPath;loginConfigurationSha256=(Hash $loginPath);frozenReceiptPath=$frozenPath;frozenReceiptSha256=(Hash $frozenPath);aclReceiptPath=$aclPath;aclReceiptSha256=(Hash $aclPath);frozenTaskNames=@($frozenName);frozenPorts=$ports;rawPaths=$rawPaths;externalFiles=@{approvals=@($externalPath)};outputXmlPath=(Join-Path $window 'prepared.xml');preparedReceiptPath=(Join-Path $window 'prepared.json');registrationReceiptPath=(Join-Path $window 'registered.json');ownerApprovalPath=(Join-Path $window 'owner.json');aclExpected=@{windowId=$windowId;candidateSourceCommit=$assembly.source_commit;candidateManifestSha256=$assembly.manifest_sha256;configSha256=(Hash $aclConfig);freezeSha256=(Hash $frozenPath);snapshot_sha256=(Hash $snapshot);paths=@($rows|ForEach-Object{$_.path});expectedForeignOwnerCount=16;notBeforeUtc=$start;notAfterUtc=$end};maintenanceFiles=@()}
 foreach($p in Get-ChildItem -LiteralPath $maintenance -File){$c.maintenanceFiles+=@{path=$p.FullName;sha256=(Hash $p.FullName)}}
 $package=Join-Path (Split-Path -Parent $maintenance) 'release_schema6\package.mjs';$c.maintenanceFiles+=@{path=$package;sha256=(Hash $package)}
 Json $c.ownerApprovalPath @{format='schema6-owner-gates-approved-v2';windowId=$windowId;candidateSourceCommit=$c.candidateSourceCommit;candidateManifestSha256=$c.candidateManifestSha256;task_name=$name;owner_sid=$owner;registration_sddl=$registration;expected_registered_sddl=$expected;parent_sddl_sha256=$c.parentSddlSha256;task_security_policy_version=$c.taskSecurityPolicyVersion;inherited_read_only_principals=$c.inheritedReadOnlyPrincipals;xml_review_sha256=$c.approvedXmlSha256;login_sha256=$c.loginConfigurationSha256;require_fixed_prepare_identical=$true}
 $c.ownerApprovalSha256=Hash $c.ownerApprovalPath;$configPath=Join-Path $window 'prepare-config.json';Json $configPath $c
 Json (Join-Path $root 'consumer-plan.json') @{ownerSid=$owner;maintenance=$maintenance;release=$release;aclReceiptPath=$aclPath;configPath=$configPath;configSha256=(Hash $configPath)}
 $consumer=Join-Path $PSScriptRoot 'identity_consumer.ps1';$token=Join-Path $PSScriptRoot 'identity_token.cs'
 $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$consumer+'" -FixtureRoot "'+$root+'" -TokenSource "'+$token+'"'
 $consumerExit=[Schema6IdentityToken]::RunLimited($ps,$arguments,$root)
 $answer=Get-Content -LiteralPath (Join-Path $root 'consumer-result.json') -Raw|ConvertFrom-Json;$report.consumer=$answer.identity
 if($consumerExit-ne 0 -or !$answer.passed){throw ('limited_consumer_failed:'+($answer|ConvertTo-Json -Depth 5 -Compress))}
 $report.fixedPrepare=$answer.fixedPrepare;$report.registrationValidation=$answer.registrationValidation
 if((Hash $c.outputXmlPath)-cne $c.approvedXmlSha256){throw 'approved_fixed_prepare_bytes_changed'}
 $report.approvedXmlSha256=$c.approvedXmlSha256;$report.fixedPrepareXmlSha256=Hash $c.outputXmlPath
 $report.maintenancePins=@($c.maintenanceFiles|ForEach-Object{@{name=[IO.Path]::GetFileName($_.path);sha256=$_.sha256}})
 $safe=New-IdentitySafeXml ([IO.File]::ReadAllText($c.outputXmlPath)) $nonce
 if($folder.GetSecurityDescriptor(7)-cne $parent){throw 'task_parent_changed'}
 $expectedDefinition=$service.NewTask(0);$expectedDefinition.XmlText=$safe
 if($expectedDefinition.Settings.Enabled -or $expectedDefinition.Triggers.Count-ne 0){throw 'synthetic_safety_rejected'}
 $null=New-ApprovedTask $service $folder $name $safe $owner $registration;$created=$true;$report.syntheticRegistered=$true
 Assert-RegisteredTask ($folder.GetTask($name)) $expectedDefinition $name $expected;$report.comReadback=$true
 if($folder.GetSecurityDescriptor(7)-cne $parent){throw 'task_parent_changed'}
 $report.passed=$true
} catch {$report.error=[string]$_.Exception.Message;$report.passed=$false}
finally {
 try{if($created){Remove-IdentityTask $folder $name $nonce $owner;$report.deleted=$true};if($frozenCreated){Remove-IdentityTask $folder $frozenName $frozenNonce $owner;$report.frozenTaskDeleted=$true}}
 catch{$report.passed=$false;$report.cleanupError=[string]$_.Exception.Message}
 # Keep only synthetic evidence on failures for diagnosis; never broaden cleanup scope.
 if($report.passed -and $root){$resolved=(Resolve-Path -LiteralPath $root).Path;if($resolved-cne $root -or [IO.Path]::GetFileName($resolved)-cnotmatch '^schema6-identity-[A-Za-z0-9]+$'){throw 'cleanup_root_rejected'};Remove-Item -LiteralPath $resolved -Recurse -Force}
 [IO.File]::WriteAllText($OutputReport,($report|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
}
if(!$report.passed){Write-Error ($report.error);exit 1}
