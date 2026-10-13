[CmdletBinding()]
param(
  [ValidateSet('Catch','LegacyEnvironment')][string]$Mode,
  [string]$SourcePath = '',
  [AllowEmptyString()][string]$MessageBase64 = ''
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -cne 'true') { throw 'r1_diagnostics_ci_only' }
if ($Mode -eq 'LegacyEnvironment') {
  # Frozen pre-R1 predicate, including its uncaught -File exit status.
  Get-ChildItem Env: | Where-Object { $_.Name -like 'I_CORE_*' -or $_.Name -like 'NODE_*' -or $_.Name -in @(
    'NODE_OPTIONS','NODE_PATH','NODE_EXTRA_CA_CERTS','OPENSSL_CONF','SSL_CERT_FILE','SSL_CERT_DIR'
  ) } | ForEach-Object { throw 'inherited_runtime_environment_rejected' }
  exit 0
}
# Execute the exact production catch/finally AST, not a reimplementation of its filter.
# The production try body is never run by this harness.
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors)
if ($errors.Count -ne 0) { throw 'r1_diagnostics_parse_failed' }
$outer = @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] })
if ($outer.Count -ne 1 -or $outer[0].CatchClauses.Count -ne 1 -or $null -eq $outer[0].Finally) { throw 'r1_diagnostics_outer_try_missing' }
$locks = @()
$message = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($MessageBase64))
$handler = [ScriptBlock]::Create('try { throw $message } ' + $outer[0].CatchClauses[0].Extent.Text + ' finally ' + $outer[0].Finally.Extent.Text)
& $handler
throw 'r1_diagnostics_expected_exit'
