param([Parameter(Mandatory=$true)][string]$FixtureRoot,[Parameter(Mandatory=$true)][string]$TokenSource)
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$env:PSModulePath=Join-Path $PSHOME 'Modules'
Add-Type -Path $TokenSource
$report=[ordered]@{passed=$false;identity=[Schema6IdentityToken]::Current();fixedPrepare=$false;registrationValidation=$false;aclReceiptRead=$false}
try {
 $plan=Get-Content -LiteralPath (Join-Path $FixtureRoot 'consumer-plan.json') -Raw|ConvertFrom-Json
 if($report.identity.sid-cne $plan.ownerSid -or $report.identity.elevated -or $report.identity.administrator -or $report.identity.integritySid-cne 'S-1-16-8192'){throw 'consumer_identity_rejected'}
 . (Join-Path $plan.maintenance 'owned_artifacts.ps1')
 foreach($p in @($plan.aclReceiptPath,$plan.configPath)){Assert-OwnedArtifact $p $plan.ownerSid}
 $acl=Get-Content -LiteralPath $plan.aclReceiptPath -Raw|ConvertFrom-Json
 if(!$acl.passed -or $acl.mode-cne 'Apply' -or $acl.verified_count-ne 144 -or $acl.expected_foreign_owner_count-ne 16){throw 'actual_apply_receipt_rejected'}
 $report.aclReceiptRead=$true
 $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $raw=& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $plan.maintenance 'prepare-production-login.ps1') -ConfigPath $plan.configPath -ExpectedConfigSha256 $plan.configSha256
 if($LASTEXITCODE-ne 0){throw ('consumer_prepare_rejected:'+($raw-join ''))}
 $prepared=($raw-join '')|ConvertFrom-Json
 if(!$prepared.passed -or !$prepared.fixed_prepare_validated -or $prepared.registered -or $prepared.started){throw 'consumer_prepare_report_rejected'}
 $report.fixedPrepare=$true
 $config=Get-Content -LiteralPath $plan.configPath -Raw|ConvertFrom-Json
 Assert-OwnedArtifact $config.outputXmlPath $plan.ownerSid;Assert-OwnedArtifact $config.preparedReceiptPath $plan.ownerSid
 # Same guarded input and prepared proof validation used by RegisterOnly, read-only.
 $raw=& (Join-Path $plan.release 'runtime\node.exe') (Join-Path $plan.maintenance 'prepare-production-login.mjs') --config $plan.configPath --config-sha256 $plan.configSha256 --validate-registration
 if($LASTEXITCODE-ne 0 -or !(($raw-join ''|ConvertFrom-Json).validated)){throw 'consumer_registration_validation_rejected'}
 $report.registrationValidation=$true;$report.passed=$true
} catch {$report.error=[string]$_.Exception.Message}
[IO.File]::WriteAllText((Join-Path $FixtureRoot 'consumer-result.json'),($report|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
if(!$report.passed){exit 1}
