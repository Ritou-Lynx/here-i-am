[CmdletBinding(DefaultParameterSetName='Setup')]
param(
 [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSha256,
 [Parameter(Mandatory=$true)][string]$OutputDirectory,
 [Parameter(ParameterSetName='Setup',Mandatory=$true)][string]$KeyDirectory,
 [Parameter(ParameterSetName='Setup',Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$BackupSetId,
 [Parameter(ParameterSetName='Restore',Mandatory=$true)][string]$EnvelopePath,
 [Parameter(ParameterSetName='Restore',Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$EnvelopeSha256,
 [Parameter(ParameterSetName='Restore',Mandatory=$true)][string]$BindingPath,
 [Parameter(ParameterSetName='Restore',Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$BindingSha256,
 [Parameter(ParameterSetName='Restore',Mandatory=$true)][string]$ArtifactPath
)
# Passphrase is obtained interactively as SecureString inside the verified
# wrapper; never accepted as a parameter, environment variable or input file.
$invoke=@{};foreach($name in $PSBoundParameters.Keys){$invoke[$name]=$PSBoundParameters[$name]}
$invoke.Operation=if($PSCmdlet.ParameterSetName -eq 'Setup'){'SetupPortable'}else{'RestorePortable'}
& (Join-Path $PSScriptRoot 'backup_bundle_schema6.ps1') @invoke
exit $LASTEXITCODE
