[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSha256,
 [Parameter(Mandatory=$true)][string]$LoginConfigurationPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$LoginConfigurationSha256,
 [Parameter(Mandatory=$true)][string]$OutputXml,
 [Parameter(Mandatory=$true)][switch]$PrepareOnly
)
$ErrorActionPreference='Stop'
if(-not $PrepareOnly){throw 'prepare_only_required'}
if(Test-Path -LiteralPath $OutputXml){throw 'fresh_output_required'}
$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$login=Join-Path $ReleaseDirectory 'tools/i_core/release_schema6/lifecycle/login_schema6.ps1'
if([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..')) -cne $ReleaseDirectory){throw 'prepare_release_binding_mismatch'}
$manifestPath=Join-Path $ReleaseDirectory 'manifest.json'
if((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne $ManifestSha256){throw 'prepare_manifest_mismatch'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
$entry=@($manifest.files|Where-Object{$_.path -ceq 'tools/i_core/release_schema6/lifecycle/login_schema6.ps1'})
if($entry.Count -ne 1 -or (Get-FileHash -LiteralPath $login -Algorithm SHA256).Hash -ne $entry[0].sha256){throw 'prepare_login_hash_mismatch'}
$loginLock=[IO.File]::Open($login,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try {
$raw=& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $login -ReleaseDirectory $ReleaseDirectory -ManifestSha256 $ManifestSha256 -LoginConfigurationPath $LoginConfigurationPath -LoginConfigurationSha256 $LoginConfigurationSha256 -ValidateOnly
if($LASTEXITCODE -ne 0){throw 'login_candidate_not_validated'}
} finally {$loginLock.Dispose()}
$verified=$raw|ConvertFrom-Json
if($verified.validated -ne $true -or $verified.core_port -le 0){throw 'fixed_nonzero_production_port_required'}
function Quote-Argument([string]$value){if($value.Contains('"') -or $value.EndsWith('\') -or $value.Contains("`n") -or $value.Contains("`r")){throw 'task_argument_rejected'};'"'+$value+'"'}
$arguments=@('-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',$login,'-ReleaseDirectory',$ReleaseDirectory,'-ManifestSha256',$ManifestSha256,'-LoginConfigurationPath',$LoginConfigurationPath,'-LoginConfigurationSha256',$LoginConfigurationSha256)
$argumentText=($arguments|ForEach-Object{Quote-Argument $_}) -join ' '
$document=New-Object Xml.XmlDocument
$document.LoadXml('<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"><Triggers><LogonTrigger><Enabled>true</Enabled><UserId /></LogonTrigger></Triggers><Principals><Principal id="Owner"><UserId /><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals><Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>false</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable><Enabled>true</Enabled><Hidden>true</Hidden><ExecutionTimeLimit>PT0S</ExecutionTimeLimit></Settings><Actions Context="Owner"><Exec><Command /><Arguments /></Exec></Actions></Task>')
$ns=New-Object Xml.XmlNamespaceManager($document.NameTable);$ns.AddNamespace('t',$document.DocumentElement.NamespaceURI)
foreach($node in $document.SelectNodes('//t:UserId',$ns)){$node.InnerText=$verified.owner_sid}
$document.SelectSingleNode('//t:Command',$ns).InnerText=$ps
$document.SelectSingleNode('//t:Arguments',$ns).InnerText=$argumentText
$stream=[IO.File]::Open($OutputXml,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$document.Save($stream);$stream.Flush($true)}finally{$stream.Dispose()}
@{prepared=$true;registered=$false;started=$false;manifest_sha256=$ManifestSha256;login_configuration_sha256=$LoginConfigurationSha256}|ConvertTo-Json -Compress
