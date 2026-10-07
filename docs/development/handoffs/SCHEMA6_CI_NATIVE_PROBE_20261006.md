# Schema6 CI native probe — 2026-10-06

- Exact base: `2c75e5105608e7a68ad6e4a279377b89ad046de4`.
- Branch: `codex/schema6-ci-native-probe-20261006`; preserves earlier worker branches.
- Scope: CI runner, new CI-only probe and its own tests, this handoff. No production file, 43-file inventory, plainPath/ACL/authentication checks, cleanEnvironment or production timeout changed. No push; parent owns workflow artifact configuration and global state. Authorized per-commit `SKIP_PROJECT_STATE=1` is restored in `finally`.

## Evidence boundary

Parent-provided final push run `37431689258` / job `112163883579` reported 151 tests, 141 pass, 8 fail, 2 cancel, 0 skip. Log SHA-256: `32a8221cbdeaaa6e57b7c11b725704b5969bfb3becc16d309e3fbc984bc9c31b` (verified). The PR companion reported 141 pass, 7 fail and 3 cancel, with the same ten marked names. The first failure is the original 10 s protectedPath PowerShell Assert-ProtectedPath invocation timing out. Six later lifecycle failures precede Store construction; their safe generic code does not prove the exact native stage. Two push cancellations are per-test 180 s budgets.

Module discovery/cache cost remains a hypothesis. The failing test already calls Protect-NewDirectory with the same clean environment before its Assert failure; that preparation cannot establish that another fresh process will be fast. Missing LOCALAPPDATA in the supplied environment also does not prove absence of the normal module analysis cache. No cache, registry, module directory, Defender or machine policy is changed by this patch. No warm-cache fix is claimed.

## Probe and gate

After the existing test-process token-owner setup, the runner starts the probe with a fresh .NET ProcessStartInfo containing exactly the production OS environment keys and fixed PATHEXT. Every diagnostic PowerShell child receives actual cleanEnvironment(), the fixed SystemRoot PowerShell 5.1 executable and NoProfile/NonInteractive. Stages are fresh processes, not claims of machine coldness:

1. no_op; 2. prepare_root using unmodified Protect-NewDirectory; 3. default_acl; 4. default_assert using unmodified Assert-ProtectedPath; 5. system_module_assert using only that comparison child's explicit PSHOME system-module path. Each of these native diagnostic calls has a 60 s limit, no retry, and bounded captured output. Preparation is not production acceptance.
6. Exactly one direct import/call of actual configuration.protectedPath(root,true). Its fresh PS child, cleanEnvironment and original 10000 ms deadline remain unchanged.
7. Cleanup checks canonical path, original directory identity, own prefix and emptiness, then removes that empty directory non-recursively. No other root can be selected by arguments.

Reports expose only fixed stage/error enums, booleans, bounded integer exit/timing/count metrics. module_directory_count counts PSHOME/Modules immediate directories; module_path_count counts configured path entries, without emitting names or paths. Raw stdout/stderr, exception bodies, command arguments, nonce or environment values are never forwarded. The PowerShell driver reconstructs the report from a whitelist. Diagnostic failures, invalid reports or the production gate failing keep the job failed and do not invoke the suites. A preflight-failure TAP explicitly says the full suite did not start. Passing runs use the original full glob, concurrency=1 and both reporters; no test is skipped, removed or retried.

Per-child limits bound ordinary execution; they are not a hard real-time guarantee against OS process teardown or filesystem hangs. A successful probe does not guarantee the entire later suite remains within every native deadline. Its purpose is early evidence and an unchanged precondition, not to mask later failures.

## Outputs and validation

- `build/ci/schema6-native-probe.json`: sanitized report, also printed once to normal console output.
- `build/ci/schema6-windows.tap`: original full-suite TAP on success; explicit failed preflight TAP if the suite was not started.
- Parent integration should upload the new JSON alongside the existing TAP; workflow was not edited by this worker.
- Exact test command: `D:\Nodejs\node.exe --test tools/i_core/test_fixtures/release_schema6/ci_native_probe.test.mjs`: **8/8 pass, 0 skip**, 622.5966 ms. Covers environment/argument rejection, metrics validation, output redaction, one-call/no-retry gate and the actual PS gate function's failure/exception paths never calling the suite callback. Successful preflight preserves the suite exit code.
- `D:\Nodejs\node.exe --check tools/i_core/test_fixtures/release_schema6/ci_native_probe.mjs`, PS5.1 runner AST parse and `git diff --check` pass.
- Actual PS5.1 driver-function probe on a new local synthetic directory: no_op 342 ms; prepare_root 561; default_acl 386; default_assert 468; system_module_assert 437; actual production gate 415; cleanup 1. All stages pass. Default module-path count 4 versus explicit system comparison 1; system module directory count 80. This is local evidence only, not proof of a hosted cause or repair.
- An initial verification launcher using Node spawnSync was rejected by the strict parent environment guard because Windows/libuv added extra bootstrap environment keys. The real CI driver uses .NET EnvironmentVariables.Clear and the exact intended entries; the real-driver local verification above passed without weakening the guard or production environment. Its PSScriptRoot is bound when extracting the function into the verification process, because an in-memory scriptblock has no file directory.
- No full suite rerun, account, service, task, live Core/MCP/tunnel, original database or phone operation. Only fresh synthetic directory, bounded owned PS children and ignored local CI report outputs.

To reproduce only the actual probe driver (not the suites), use this body in Windows PowerShell 5.1 from the repository root:

```powershell
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$tokens=$null;$errors=$null
$runner=Join-Path (Get-Location) 'tools/i_core/test_fixtures/release_schema6/run_windows_tests.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($runner,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'parser_failed'}
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-Schema6NativeProbe'},$true)
$boundSource=$fn.Extent.Text.Replace('$PSScriptRoot',("'"+(Split-Path $runner).Replace("'","''")+"'"))
. ([scriptblock]::Create($boundSource))
New-Item -ItemType Directory -Force build/ci | Out-Null
$code=Invoke-Schema6NativeProbe 'D:\Nodejs\node.exe'
exit $code

```
