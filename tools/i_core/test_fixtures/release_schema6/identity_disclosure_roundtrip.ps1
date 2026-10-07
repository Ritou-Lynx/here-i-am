param([Parameter(Mandatory=$true)][string]$Repository)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
if($PSVersionTable.PSVersion.Major-ne 5 -or $PSVersionTable.PSEdition-ne 'Desktop'){throw 'real_windows_powershell_51_required'}
. (Join-Path $Repository 'tools/i_core/maintenance/register_task_primitives.ps1')
. (Join-Path $Repository 'tools/i_core/maintenance/task_security_policy.ps1')
. (Join-Path $PSScriptRoot 'identity_task_oracle.ps1')
# Evaluate only the actual pipeline's disclosure value AST, never its lifecycle.
$errors=$null;$tokens=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'identity_pipeline.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'pipeline_parse_failed'}
$values=@(foreach($h in $ast.FindAll({param($n)$n-is [Management.Automation.Language.HashtableAst]},$true)){foreach($pair in $h.KeyValuePairs){if($pair.Item1.Value-ceq 'inheritedReadOnlyPrincipals'){$pair.Item2}}})
if($values.Count-ne 1){throw 'pipeline_disclosure_value_required'}
$commands=@($values[0].FindAll({param($n)$n-is [Management.Automation.Language.CommandAst]},$true))
if($commands.Count-ne 1 -or $commands[0].GetCommandName()-cne 'Get-TaskInheritedReadOnlyPrincipals'){throw 'pure_disclosure_expression_required'}
$assign=[scriptblock]::Create('$disclosureConfig=@{inheritedReadOnlyPrincipals='+$values[0].Extent.Text+'}')
$owner='S-1-5-21-101-202-303-1001'
$registration='O:'+$owner+'G:'+$owner+'D:(A;;FA;;;'+$owner+')(A;;FA;;;SY)(A;;FA;;;BA)'
$baseParent='O:SYG:SYD:(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'
$results=@()
foreach($row in @(@{name='empty';suffix='';count=0},@{name='one';suffix='(A;OICI;FR;;;BU)';count=1},@{name='two';suffix='(A;OICI;FR;;;BU)(A;OICI;FR;;;AU)';count=2})){
 $parent=$baseParent+$row.suffix
 $expected=Get-IdentityExpectedSddl $registration $parent $owner
 if((Convert-TaskSecurity $expected)-cne (Convert-TaskSecurity (Get-TaskPolicyExpectedSecurity $registration $parent $owner))){throw 'independent_oracle_mismatch'}
 . $assign
 $config=[pscustomobject]@{ownerSid=$owner;registrationSddl=$registration;expectedRegisteredSddl=$expected;parentSddlSha256=(Get-TaskSecuritySha256 $parent);taskSecurityPolicyVersion='windows-file-oi-v1';inheritedReadOnlyPrincipals=$disclosureConfig.inheritedReadOnlyPrincipals}
 $round=($config|ConvertTo-Json -Depth 10 -Compress)|ConvertFrom-Json
 if($round.inheritedReadOnlyPrincipals-isnot [array] -or $round.inheritedReadOnlyPrincipals.Count-ne $row.count){throw 'roundtrip_array_shape_rejected'}
 $null=Assert-TaskSecurityPolicy $round $parent
 # Preserve the exact old bug for the JS rejection assertion, including [ [] ].
 $broken=[pscustomobject]@{inheritedReadOnlyPrincipals=@(Get-TaskInheritedReadOnlyPrincipals $expected $owner)}
 $results+=@{name=$row.name;config=$round;oldWrapped=$broken.inheritedReadOnlyPrincipals}
}
@{passed=$true;psVersion=$PSVersionTable.PSVersion.ToString();cases=$results}|ConvertTo-Json -Depth 12 -Compress
