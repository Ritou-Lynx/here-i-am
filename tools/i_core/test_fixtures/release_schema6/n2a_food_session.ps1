param([string]$InputPath,[string]$MaintenanceDirectory,[string[]]$Rotate=@())
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true'){throw 'n2a_fixture_ci_only'}
# Dot-sourcing rebinds the script's own param block in this scope; keep the request first.
$requestedRotate=@($Rotate)
. (Join-Path $MaintenanceDirectory 'provision-food-domain.ps1')
$script:foodFixture=Get-Content -LiteralPath $InputPath -Raw|ConvertFrom-Json
# Only the Task Scheduler read is synthetic. Session, ACL, process, HMAC,
# request publication, runtime provisioning and token consumption are real.
$script:Schema6TaskAdapter={param($Operation,$TaskName)
 if($Operation -cne 'Read' -or $TaskName -cne $script:foodFixture.Name){throw 'n2a_task_mutation_forbidden'}
 return $script:foodFixture
}
Invoke-Schema6FoodProvisionCli -TaskName $script:foodFixture.Name -Rotate $requestedRotate
