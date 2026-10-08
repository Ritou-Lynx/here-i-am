$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'module_scope.ps1')
Assert-Schema6ModuleScopeHost
$repository=(Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
$output=Join-Path $repository 'build/ci/schema6-identity-pipeline.json'
$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output))
$result=Invoke-Schema6HostedModuleScope -Body {
 & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'identity_pipeline.ps1') -Repository $repository -OutputReport $output | ForEach-Object {Write-Host $_}
 return $LASTEXITCODE
}
exit $result
