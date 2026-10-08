param([string]$Source)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($Source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'parse_failed'}
foreach($name in @('Fail','Hash','Plain','Pin','Assert-PreflightUsbBackup','Private','New-MaintenanceArtifactDirectory')){$fn=$ast.Find({param($a)$a-is [Management.Automation.Language.FunctionDefinitionAst]-and $a.Name-ceq $name},$true);. ([scriptblock]::Create($fn.Extent.Text))}
$native=$ast.Find({param($a)$a-is [Management.Automation.Language.CommandAst]-and $a.GetCommandName()-ceq 'Add-Type'},$true);& ([scriptblock]::Create($native.Extent.Text))
$script:drift=$false;$script:leases=@();$script:proofFiles=@();$script:mutations=0
$root=Join-Path ([IO.Path]::GetTempPath()) ('maintenance-preflight-dispatch-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($root)
function Check($Ok,[string]$Code){if(!$Ok){throw $Code}}
function Invoke-OnlineCopyValidation{if($script:copyFail){throw 'synthetic_copy_rejected'}}
function Receipt{}
function VerifyPins{}
function CoreHealth{return $true}
function Invoke-PreflightAclAudit{return @{passed=$true}}
function Invoke-PreflightTaskApproval{return @{passed=$true}}
function WriteNew([string]$Path,$Value){$script:result=$Value}
try{
 foreach($role in @('data','configuration')){
  $file=Join-Path $root ($role+'.json');$link=Join-Path $root ($role+'-link.json');[IO.File]::WriteAllText($file,'synthetic')
  $null=New-Item -ItemType HardLink -Path $link -Target $file
  $rejected=$false;try{Pin $file (Hash $file)}catch{if($_.Exception.Message-match 'file_identity_rejected'){$rejected=$true}}
  Check $rejected ($role+'_double_link_accepted')
 }
 Check ($script:leases.Count-eq 2) 'ordinary_pin_not_retained'
 # Exercise the production artifact initializer with a REAL nonempty window
 # and the unchanged fixed protected-path helper. This reproduces the first
 # live read-only rejection without any real task/process/database.
 . (Join-Path ([IO.Path]::GetDirectoryName($Source)) 'maintenance_window.ps1')
 . ([IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($Source)) '..\release_schema6\lifecycle\protected_paths.ps1')))
 $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $windowRoot=Join-Path $root 'artifact-window';$null=[IO.Directory]::CreateDirectory($windowRoot);Protect-NewDirectory $windowRoot
 $window=Open-MaintenanceWindow $windowRoot 'readonly-artifacts-synthetic'
 try{
  $parent=$window.Directory;$before=(Get-Acl -LiteralPath $parent).Sddl
  $rejected=$false;try{Protect-NewDirectory $parent}catch{if($_.Exception.Message-ceq 'new_empty_directory_required'){$rejected=$true}}
  Check $rejected 'nonempty_window_no_longer_rejected'
  $copy=New-MaintenanceArtifactDirectory $parent 'copy-validation'
  $template=New-MaintenanceArtifactDirectory $parent 'prepare-template'
  Assert-ProtectedPath $copy -Root;Assert-ProtectedPath $template -Root
  Check ((Get-Acl -LiteralPath $parent).Sddl-ceq $before) 'existing_window_acl_changed'
  $sentinel=Join-Path $template 'sentinel';[IO.File]::WriteAllText($sentinel,'preserve')
  $rejected=$false;try{$null=New-MaintenanceArtifactDirectory $parent 'prepare-template'}catch{$rejected=$true}
  Check $rejected 'existing_artifact_directory_reused';Check ([IO.File]::ReadAllText($sentinel)-ceq 'preserve') 'artifact_evidence_changed'
 }finally{Close-MaintenanceWindow $window}
 # USB/backup predicates run with deterministic read-only providers; the backup
 # hash helper has separate real-file tests. Any failed identity must stop here.
 $script:filesystem='NTFS';$script:volumeId='synthetic-volume';$script:serial='synthetic-serial'
 $Inputs=[pscustomobject]@{mirrorRoot=$root;expectedVolumeId='synthetic-volume';usbSerialNumber='synthetic-serial';usbFriendlyName='synthetic-usb';backupReceiptPath='synthetic-receipt';backupArtifacts=@([pscustomobject]@{localPath='local-cipher';usbPath=($root+'\cipher');sha256=('f'*64)})}
 $script:backupReceipt=[pscustomobject]@{format='schema6-cutover-current-backup-v1';passed=$true;backup=[pscustomobject]@{verified=$true;mirrored=$true;mirrorPending=$false;files=116;artifactSha256=('f'*64)};restore=[pscustomobject]@{restored=$true;verified=$true;inspectionOnly=$true;databaseBytesUnchanged=$true;sidecarsAbsent=$true;files=116;artifactSha256=('f'*64)};inputRoles=[pscustomobject]@{database=1;release=10;configuration=80;task=2;credentials=8;domain_policy=3;transcript_grants=1;replay_approvals=1;recovery_custody=8};artifactPath='local-cipher';mirrorArtifactPath=($root+'\cipher')}
 function Private{}
 function Get-Volume{return [pscustomobject]@{FileSystem=$script:filesystem}}
 function Get-CimInstance{return [pscustomobject]@{DeviceID=$script:volumeId}}
 function Get-Partition{return [pscustomobject]@{DiskNumber=1}}
 function Get-Disk{return [pscustomobject]@{BusType='USB';SerialNumber=$script:serial;FriendlyName='synthetic-usb'}}
 function ReadJson{return $script:backupReceipt}
 function Invoke-PreflightBackupArtifacts{return @{passed=$true}}
 # Use a rooted canonical path on this test drive; no USB commands actually run.
 $null=Assert-PreflightUsbBackup $Inputs
 foreach($field in @('filesystem','volumeId','serial')){
  $before=Get-Variable -Name $field -Scope Script -ValueOnly;Set-Variable -Name $field -Scope Script -Value 'wrong'
  $rejected=$false;try{$null=Assert-PreflightUsbBackup $Inputs}catch{$rejected=$true};Check $rejected ('usb_'+$field+'_accepted')
  Set-Variable -Name $field -Scope Script -Value $before
 }
 $script:backupReceipt.inputRoles.replay_approvals=0;$rejected=$false;try{$null=Assert-PreflightUsbBackup $Inputs}catch{$rejected=$true};Check $rejected 'missing_backup_role_accepted';$script:backupReceipt.inputRoles.replay_approvals=1
 $script:backupReceipt.restore.restored=$false;$rejected=$false;try{$null=Assert-PreflightUsbBackup $Inputs}catch{$rejected=$true};Check $rejected 'hash_only_restore_accepted'
 $sourceText=[IO.File]::ReadAllText($Source)
 Check ($sourceText.Contains("Join-Path `$config.maintenanceRoot 'rehearsals'")) 'independent_rehearsal_root_missing'
 Check ($sourceText.Contains("if(`$WindowId-ceq `$config.formalWindowId){Fail 'rehearsal_must_not_use_formal_id'}")) 'formal_id_not_reserved'
 $branch=$ast.Find({param($a)$a-is [Management.Automation.Language.IfStatementAst]-and $a.Extent.Text.StartsWith('if($PreflightOnly){')-and $a.Extent.Text.Contains('preflight-only-receipt.json')},$true)
 Check ($null-ne $branch) 'readonly_branch_missing'
 # Execute the actual production branch and immediately follow it by a mutation
 # trap. Its return must prevent that trap; throwing must also bypass it.
 $body=$branch.Extent.Text+"`n`$script:mutations++;throw 'live_mutation_reached'"
 $PreflightOnly=$true;$taskOrder=@();$config=[pscustomobject]@{formalWindowId='formal-synthetic-01';databasePath=(Join-Path $root 'identity.sqlite')}
 [IO.File]::WriteAllText($config.databasePath,'synthetic');$script:initialDbIdentity=[FreezeIdentity]::FileId($config.databasePath)
 $preflight=[pscustomobject]@{aclConfigurationPath='synthetic';aclConfigurationSha256=('a'*64);taskApproval=@{}}
 $WindowId='readonly-synthetic-01';$ExpectedConfigSha256='b'*64;$manifestHash='c'*64;$xmlHash='d'*64;$clock=[Diagnostics.Stopwatch]::StartNew()
 $prep=$root;$backupAudit=@{passed=$true};$templateAudit=@{prepareTemplateBytesEqual=$true}
 $validationPath='synthetic-receipt';$validationReceiptSha256='e'*64;$validation=[pscustomobject]@{comparison_policy='online-db-wal-bytes-identity-journal-existence-shm-existence-size-v1'}
 $script:copyFail=$false;$null=& ([scriptblock]::Create($body))
 Check ($script:result.passed-and !$script:result.liveMutationPerformed-and !$script:result.formalEntryConsumed) 'readonly_receipt_rejected'
 Check (!$script:result.productionPrepareInvoked-and $script:result.productionPrepareStillRequiresAclApply) 'false_prepare_attestation'
 $script:copyFail=$true;$rejected=$false;try{$null=& ([scriptblock]::Create($body))}catch{if($_.Exception.Message-ceq 'synthetic_copy_rejected'){$rejected=$true}}
 Check $rejected 'failed_copy_accepted';Check ($script:mutations-eq 0) 'live_mutation_called'
 [ordered]@{passed=$true;normalPreflightReturns=$true;failedPreflightCannotMutate=$true;dataDoubleLinkRejected=$true;configurationDoubleLinkRejected=$true;ordinaryPinLeasesRetained=$true;formalIdReserved=$true;noProductionPrepareReceipt=$true;nonemptyWindowAclPreserved=$true;emptyProtectedArtifactChildren=$true;artifactReuseRejected=$true;usbMismatchRejected=$true;incompleteBackupRejected=$true;realRestoreRequired=$true;liveMutationCalls=$script:mutations}|ConvertTo-Json -Compress
}finally{
 foreach($h in $script:leases){$h.Dispose()}
 $target=[IO.Path]::GetFullPath($root);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if($target.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)-and [IO.Path]::GetFileName($target).StartsWith('maintenance-preflight-dispatch-')){Remove-Item -LiteralPath $target -Recurse -Force}
}