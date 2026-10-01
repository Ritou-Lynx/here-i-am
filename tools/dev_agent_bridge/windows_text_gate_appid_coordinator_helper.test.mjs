// Only default/token-plan/self-test/invalid read-only entrypoints; no UAC, CLI, Job, or WFP execution.
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const local = name => fileURLToPath(new URL(name, import.meta.url));
const source = local('./windows_text_gate_appid_coordinator_helper.cs');
const core = local('./windows_text_gate_isolation_helper.cs');
const appid = local('./windows_text_gate_appid_startup_helper.cs');
const frozen = new Map([
  [core, 'd22017641d9f8df750f6db7db9319b8c1930a726a8575ff1ffabfde0d5ffdcd8'],
  [local('./windows_text_gate_isolation_helper.test.mjs'), '3b30a568278284378bb75fb7024f3ed175fe289583b32aaa76c4e4fdde261d0f'],
  [appid, 'c777023495ccdbf3b52663f49683f5d84dcfd03a36b3d280a75c925f37b7a1ea'],
  [local('./windows_text_gate_appid_startup_helper.test.mjs'), '91a1579202df71262329bd8eb06c6628f5075929ff73e4b70e62035c40433aed'],
]);
const artifacts = local('../../tmp/p6-r7-helper/');
const isolationRoot = String.raw`D:\memex\tmp\p6-r7-appid-coordinator`;
const csc = String.raw`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`;
const supported = process.platform === 'win32' && existsSync(csc);
const rootState = () => ({ legacy: existsSync(isolationRoot) ? readdirSync(isolationRoot).sort() : null, normalExists: existsSync(String.raw`D:\HereIAm-P6-R7-Isolated`) });
const checkFrozen = () => {
  for (const [file, expected] of frozen) assert.equal(createHash('sha256').update(readFileSync(file)).digest('hex'), expected);
};

test('v12 coordinator compiles with immutable dependencies and exercises only read-only paths', { skip: !supported }, async t => {
  checkFrozen(); const before = rootState();
  const root = mkdtempSync(path.join(artifacts, 'coordinator-test-'));
  const exe = path.join(root, 'candidate.exe');
  t.after(() => {
    checkFrozen(); assert.deepEqual(rootState(), before);
    const canonical = realpathSync(root);
    assert.equal(path.dirname(canonical), realpathSync(artifacts));
    assert.match(path.basename(canonical), /^coordinator-test-/);
    rmSync(canonical, { recursive: true, force: true });
  });
  const compilation = spawnSync(csc, ['/nologo', '/target:exe', '/platform:x64', '/optimize+',
    '/reference:System.Web.Extensions.dll', '/main:HereIAm.R7.CoordinatorProgram', `/out:${exe}`, core, appid, source],
  { encoding: 'utf8', windowsHide: true, timeout: 30_000 });
  assert.equal(compilation.status, 0, 'joint Framework compilation failed');
  assert.equal(compilation.stderr, '');

  function run(args) {
    assert.ok(!args.some(a => /^--(?:apply|install|cleanup|recover|synthetic)/.test(a)), 'mutating verbs forbidden in tests');
    const result = spawnSync(exe, args, { encoding: 'utf8', windowsHide: true, timeout: 10_000 });
    assert.equal(result.signal, null); assert.equal(result.stderr, '');
    assert.doesNotMatch(result.stdout, /PRIVATE|S-1-/);
    const report = JSON.parse(result.stdout);
    assert.equal(report.schema, 'p6_r7_appid_coordinator_candidate_v1');
    for (const key of ['system_mutation_requested', 'coordinator_startup_passed', 'production_isolation_passed', 'human_gate_passed']) assert.equal(report[key], false);
    assert.equal(report.real_upstream_requests, 0); assert.equal(report.model_turns_requested, 0);
    return { status: result.status, report };
  }
  await t.test('default, plan and token-plan expose only fixed current-token attributes', () => {
    const a = run([]), b = run(['--plan']), c = run(['--token-plan']);
    assert.equal(a.status, 0); assert.deepEqual(a, b); assert.deepEqual(a, c);
    assert.equal(a.report.diagnostic_only, true);
    const token = a.report.current_token;
    assert.deepEqual(Object.keys(token).sort(), ['appcontainer', 'authentication_id_nonzero', 'elevated', 'elevation_type', 'impersonation_level', 'integrity_rid', 'type']);
    for (const key of ['type', 'integrity_rid', 'elevation_type', 'elevated', 'appcontainer']) assert.equal(Number.isInteger(token[key]), true);
    assert.equal(typeof token.authentication_id_nonzero, 'boolean');
    assert.equal(a.report.coordinator_token_accepted, token.type === 1 && token.integrity_rid === 8192 && token.elevation_type === 3 && token.elevated === 0 && token.appcontainer === 0 && token.authentication_id_nonzero);
  });
  await t.test('330 ABI, never-spawned cleanup, journal, inspection and accounting boundaries pass', () => {
    const r = run(['--self-test']); assert.equal(r.status, 0);
    assert.equal(r.report.assertions_passed, 330);
    assert.equal(r.report.native_layouts_passed, true);
    assert.equal(r.report.journal_receipt_checks_passed, true);
  });
  for (const args of [['PRIVATE'], ['--plan', 'PRIVATE'], ['--token-plan', 'PRIVATE'], ['--self-test', 'PRIVATE'], ['--validate-port', '443']]) {
    await t.test(`invalid/surplus arguments rejected: ${args[0]}`, () => {
      const r = run(args); assert.equal(r.status, 2); assert.equal(r.report.error_code, 'invalid_arguments');
    });
  }
  await t.test('v13 exposes explicit ordinary modes and retains fixed-scope historical cleanup', () => {
    const code = readFileSync(source, 'utf8');
    const main = code.slice(code.indexOf('[STAThread] public static int Main'), code.indexOf('internal sealed class CoordinatorBoundary'));
    assert.match(main, /--inspect-own-appid/);
    assert.match(main, /--cleanup-never-spawned-v12/);
    assert.match(main, /return Apply\(args\[1\]\)/);
    assert.match(main, /return Elevated\(true,Guard.Attempt/);
    assert.match(main, /return Elevated\(false,Guard.Attempt/);
    assert.match(main, /--apply-coordinator-startup-synthetic/);
    assert.match(main, /--install-own-appid/); assert.match(main, /--cleanup-own-appid/);
    assert.doesNotMatch(main, /--apply-cli|--apply-synthetic|--recover|--synthetic-worker/);
  });
  await t.test('only medium coordinator creates CLI; no token conversion, credentials or profile operations', () => {
    const code = readFileSync(source, 'utf8');
    assert.doesNotMatch(code, /DuplicateTokenEx|LinkedMediumToken|CreateProcessAsUserW|LogonUser|Impersonate|NetworkIsolation|CreateAppContainerProfile|DeleteAppContainerProfile|auth\.json|backend-api|Bearer\s|HttpClient|WebRequest/);
    assert.doesNotMatch(code, /Environment\.GetEnvironmentVariables?\s*\(|Directory\.Delete\s*\(/);
    const elevated = code.slice(code.indexOf('static int Elevated'), code.indexOf('static void InvokeHelper'));
    assert.doesNotMatch(elevated, /CreateCli|CreateProcessW|\.Resume\(/);
    assert.match(elevated, /OpenJobObjectW\(4,false,JobName\(id\)\)/);
    assert.match(elevated, /install\?"install-report.json":"cleanup-report.json"/);
    assert.match(code, /identity\.IsMedium&&identity\.Same\(MediumIdentity\.OfProcess\(Native.GetCurrentProcess\(\)\)\)/);
    assert.match(code, /new IntPtr\(0x2000d\)/); assert.match(code, /new IntPtr\(0x20002\)/);
    assert.match(code, /Check\(error!=183,"named_job_collision"\)/);
  });
  await t.test('inspection dispatcher rejects malformed UUID before journal or WFP reads', () => {
    const r = run(['--inspect-own-appid', 'PRIVATE']);
    assert.equal(r.status, 2); assert.equal(r.report.error_code, 'invalid_attempt_id');
  });
  await t.test('inspection is limited to known-owner journal and reads with a local corrected filter ABI', () => {
    const code = readFileSync(source, 'utf8');
    const inspection = code.slice(code.indexOf('static int Inspect('), code.indexOf('static void Acl('));
    assert.match(inspection, /ValidateJournal\(ReadRecord\(directory,"ownership.json"\),id,InspectOwnerHash\)/);
    assert.match(inspection, /InspectorMatches\(current,expected\)/);
    assert.match(inspection, /AppIdProgram.VerifyImage\(image\)/);
    assert.doesNotMatch(inspection, /InvokeHelper|CreateCli|CreateJob|VerifyOwner|RemoveAfterZero|Terminate|ShellExecute/);
    const nativeInspection = code.slice(code.indexOf('internal static class InspectionNative'), code.indexOf('internal static class CoordinatorNative'));
    assert.match(nativeInspection, /Marshal.SizeOf\(typeof\(Filter\)\)==200/);
    assert.match(nativeInspection, /Marshal.ReadInt64\(value.Pointer\)/);
    assert.doesNotMatch(nativeInspection, /FwpmFilterAdd|FwpmFilterDelete|FwpmTransaction|\.Display\.(?:Name|Description)/);
  });
  await t.test('sublayer diagnostics and v12e historical recovery remain unchanged', () => {
    const code = readFileSync(source, 'utf8');
    const diagnostic = code.slice(code.indexOf('internal static Dictionary<string,object> DescribeSublayer'), code.indexOf('internal static object Read('));
    assert.match(diagnostic, /"data_pointer_nonnull",value.Data.Data!=IntPtr.Zero/);
    assert.doesNotMatch(diagnostic, /Marshal|CopyBlob|Display|ToString/);
    assert.match(code, /Marshal.SizeOf\(typeof\(Native.Sublayer\)\)==72/);
    for (const [field, offset] of [['Flags', 32], ['Provider', 40], ['Data', 48], ['Weight', 64]]) assert.ok(code.includes(`Marshal.OffsetOf(typeof(Native.Sublayer),"${field}").ToInt32()==${offset}`));
    const frozenSource = readFileSync(local('../../tmp/p6-r7-review/native-appid-coordinator-candidate-12e.cs'), 'utf8');
    const readOnly = value => value.slice(value.indexOf('internal static class InspectionNative'), value.indexOf('internal sealed class EvidenceReadLock')).replace(/\r\n/g, '\n');
    assert.equal(readOnly(code), readOnly(frozenSource));
    assert.match(code, /const ushort NeverSpawnedAssignedWeight=32766;/);
    assert.match(code, /NeverSpawnedInspectionHash="f25be0daee071d9e082343725e9b22bb920e5f5aeb59248307eb220734352bd1"/);
    assert.match(code, /EvidenceReadLock inspectionFile=new EvidenceReadLock\(Path.Combine\(directory,"inspect-report.json"\),NeverSpawnedInspectionHash\);evidence.Add\(inspectionFile\);/);
    const cleanup = value => value.slice(value.indexOf('static int CleanupNeverSpawned'), value.includes('internal static readonly Guid ClosedAttempt') ? value.indexOf('internal static readonly Guid ClosedAttempt') : value.indexOf('static void Acl(')).replace(/\r\n/g, '\n');
    assert.equal(cleanup(code), cleanup(frozenSource));
    const historicalRules = value => value.slice(value.indexOf('static bool ExactIndexedFilter'), value.indexOf('static int CleanupNeverSpawned')).replace(/\r\n/g, '\n');
    assert.equal(historicalRules(code), historicalRules(frozenSource));
  });
  await t.test('one-attempt cleanup holds evidence locks and validates rules inside a transaction', () => {
    const code = readFileSync(source, 'utf8');
    assert.match(code, /NeverSpawnedAttempt=new Guid\("dce75105-11ad-49c7-bc16-377823ceecc8"\)/);
    assert.match(code, /FileMode.Open,FileAccess.Read,FileShare.Read/);
    assert.match(code, /file.SafeFileHandle.DangerousGetHandle\(\)/);
    const cleanup = code.slice(code.indexOf('static int CleanupNeverSpawned'), code.indexOf('static void Acl('));
    assert.match(cleanup, /Check\(id==NeverSpawnedAttempt/);
    assert.match(cleanup, /report\["process_close_claimed"\]=false;report\["job_zero_claimed"\]=false/);
    assert.match(cleanup, /report\["attempt_id"\]=id.ToString\("D"\)/);
    assert.ok(cleanup.indexOf('FwpmTransactionBegin0') < cleanup.indexOf('ReadNeverSpawnedRules'));
    assert.ok(cleanup.indexOf('ReadNeverSpawnedRules') < cleanup.indexOf('FwpmFilterDeleteByKey0'));
    assert.ok(cleanup.indexOf('FwpmTransactionCommit0') < cleanup.indexOf('"post_commit_absence"'));
    assert.doesNotMatch(cleanup, /CreateCli|CreateJob|InvokeHelper|TerminateProcess|OpenJobObject|Directory.Delete/);
  });
  await t.test('install and cleanup receipt acceptance follow actual helper close and exact binding', () => {
    const code = readFileSync(source, 'utf8');
    const helper = code.slice(code.indexOf('static void InvokeHelper'), code.indexOf('static void Acl'));
    assert.ok(helper.indexOf('Native.WaitForSingleObject(shell.Process,30000)==0') < helper.indexOf('ValidateReceipt('));
    assert.ok(helper.indexOf('Check(exit==0,"helper_exit_nonzero")') < helper.lastIndexOf('ValidateReceipt('));
    assert.match(helper, /TokenProof.Image\(shell.Process,SelfPath\)/);
    assert.match(code, /HereIAm\.P6R7\.CoordinatorV12\//);
    assert.match(code, /Local\\HereIAm\.P6R7\.CoordinatorV12\./);
    assert.match(code, /p6_r7_appid_coordinator_receipt_v2/);
    assert.match(code, /actual_assigned_sublayer_weight/);
    const normal = code.slice(code.indexOf('static int Apply('), code.indexOf('static void Layouts()', code.indexOf('static int Apply(')));
    assert.match(normal, /else if\(installed&&installRun.Closed&&zero&&journal!=null\)try/);
    assert.match(normal, /installRun.Closed&&installRun.RollbackVerified&&!child.Started/);
    const rollbackWrite = code.indexOf('WriteRecord(directory,"install-rollback-receipt.json"');
    assert.ok(rollbackWrite < code.indexOf('report["cleanup_pending"]=false', rollbackWrite));
  });
  await t.test('ordinary boundary uses Filter200 Add/Get and exact transaction readback, without legacy Filter', () => {
    const code = readFileSync(source, 'utf8');
    assert.doesNotMatch(code, /\bNative\.Filter\b|\bNative\.FwpmFilter(?:Add|GetByKey)0/);
    assert.match(code, /extern uint AddFilter\(IntPtr engine,ref InspectionNative.Filter filter/);
    const boundary = code.slice(code.indexOf('internal sealed class CoordinatorBoundary'), code.indexOf('internal static class CoordinatorFilterNative'));
    assert.match(boundary, /Flags=0x40/);
    assert.match(boundary, /AssignedWeight=actual.Weight/);
    assert.match(boundary, /f.Flags!=0x40/);
    assert.match(boundary, /InstallFlow.Run\(/);
    assert.match(boundary, /proveClosure\(\);OpenAndVerify\(true\)/);
    assert.match(boundary, /proveClosure\(\);OpenAndVerify\(true\);Guard.Require\(!Installed/);
    assert.doesNotMatch(boundary, /if\(!Installed\) return/);
  });

  await t.test('after-close cleanup is fixed to one historical attempt and cannot run from ordinary startup', () => {
    const code = readFileSync(source, 'utf8');
    const recovery = code.slice(code.indexOf('internal static readonly Guid ClosedAttempt'), code.indexOf('internal static readonly Guid Closed14Attempt'));
    assert.match(recovery, /87c68152-eba1-4012-9edd-8afb6a1f26b3/);
    assert.match(recovery, /Check\(id==ClosedAttempt/);
    assert.match(recovery, /Process.GetProcessesByName\("codex"\)/);
    assert.match(recovery, /QueryFullProcessImageNameW/);
    assert.doesNotMatch(recovery, /CreateCli|CreateJob|OpenJobObject|Terminate|ShellExecute|Directory.Delete|CommandLine|never_spawned/);
    assert.match(recovery, /"historical_closure_verified"/);
    assert.match(recovery, /"process_close_claimed"\]=false;report\["job_zero_claimed"\]=false/);
    assert.equal((recovery.match(/new EvidenceReadLock\(/g) || []).length, 7);
    assert.ok(recovery.indexOf('FwpmTransactionBegin0') < recovery.indexOf('int found=ReadClosedRules'));
    assert.ok(recovery.indexOf('int found=ReadClosedRules') < recovery.indexOf('FwpmFilterDeleteByKey0'));
    assert.ok(recovery.indexOf('FwpmTransactionCommit0') < recovery.indexOf('"post_commit_absence"'));
    const frozenSource = readFileSync(local('../../tmp/p6-r7-review/native-appid-coordinator-candidate-13.cs'), 'utf8');
    const ordinary = value => value.slice(value.indexOf('static void Acl('), value.indexOf('static void Reject(')).replace(/\r\n/g, '\n');
    const historical = value => value.slice(value.indexOf('internal static readonly Guid ClosedAttempt'), value.includes('internal static readonly Guid Closed14Attempt') ? value.indexOf('internal static readonly Guid Closed14Attempt') : value.indexOf('static void Acl(')).replace(/\r\n/g, '\n');
    const frozenRecovery = readFileSync(local('../../tmp/p6-r7-review/native-appid-coordinator-candidate-13b.cs'), 'utf8');
    assert.equal(historical(code), historical(frozenRecovery));
    assert.doesNotMatch(ordinary(code), /CleanupClosedV13/);
  });

  await t.test('v14 keeps original config acceptance and uses exact held child closure plus Active0', () => {
    const code = readFileSync(source, 'utf8');
    const original = readFileSync(core, 'utf8');
    const features = text => text.match(/(?:internal )?static readonly string\[\] Disabled=\("([^"\n]+)"\)/)[1];
    assert.equal(features(code), features(original));
    assert.match(code, /Check\(CliStartupContract.ConfigMatches\(configReply,port\),"startup_config_rejected"\)/);
    assert.doesNotMatch(code, /Check\(ConfigProjection.PredicatesMatch/);
    assert.match(code, /return expected<=1&&active==0&&\(expected==1\|\|total==0\)/);
    assert.doesNotMatch(code, /[Tt]otal\s*-\s*[Tt]erminated/);
    const held = code.slice(code.indexOf('static void VerifyHeldClosedChild('), code.indexOf('static Dictionary<string,object> JobDiagnostic'));
    assert.match(held, /CoordinatorNative.GetProcessId\(child\)==Number\(journal\["child_pid"\]\)/);
    assert.match(held, /TokenProof.Creation\(child\)==TimeValue\(journal\["child_creation"\]\)/);
    assert.match(held, /Native.WaitForSingleObject\(child,0\)==0/);
    assert.doesNotMatch(held, /TokenProof.Image|QueryFullProcessImageName/);
    const elevated = code.slice(code.indexOf('static int Elevated('), code.indexOf('sealed class HelperRun'));
    assert.match(elevated, /heldChild=OpenHeldClosedChild/);
    assert.ok(elevated.indexOf('WriteRecord(directory,install?"install-receipt.json"') < elevated.indexOf('Native.CloseHandle(heldChild)'));
    for (const stage of ['job_created', 'child_created', 'before_termination', 'after_termination', 'cleanup', 'helper_preflight', 'helper_revalidation']) assert.ok(code.includes(`ReadJobRecorded(report,"${stage}"`));
  });

  await t.test('v14b is an independent seven-lock d06f recovery and preserves ordinary v14', () => {
    const code = readFileSync(source, 'utf8');
    const recovery = code.slice(code.indexOf('internal static readonly Guid Closed14Attempt'), code.indexOf('internal static readonly Guid Closed15Attempt'));
    assert.match(recovery, /d06f803f-69b0-44f0-bed9-37252a02dc00/);
    assert.match(recovery, /Check\(id==Closed14Attempt/);
    assert.match(recovery, /windows_text_gate_appid_coordinator_helper.v14.exe/);
    assert.match(recovery, /native-appid-coordinator-candidate-14.cs/);
    assert.match(recovery, /process_image_query_failed/);
    assert.match(recovery, /"closed14_history_accounting_rejected"/);
    assert.equal((recovery.match(/new EvidenceReadLock\(/g) || []).length, 7);
    assert.doesNotMatch(recovery, /CreateCli|CreateJob|OpenJobObject|ShellExecute|Directory.Delete|CommandLine/);
    const frozenSource = readFileSync(local('../../tmp/p6-r7-review/native-appid-coordinator-candidate-14.cs'), 'utf8');
    const historic = value => value.slice(value.indexOf('internal static readonly Guid Closed14Attempt'), value.includes('internal static readonly Guid Closed15Attempt') ? value.indexOf('internal static readonly Guid Closed15Attempt') : value.indexOf('static void Acl(')).replace(/\r\n/g, '\n');
    const frozenRecovery = readFileSync(local('../../tmp/p6-r7-review/native-appid-coordinator-candidate-14b.cs'), 'utf8');
    assert.equal(historic(code), historic(frozenRecovery));
    assert.match(code, /--cleanup-closed-v14"\)return CleanupClosedV14/);
  });

  await t.test('v15 normal paths are outside repository and class9 limits are read before UAC or CLI', () => {
    const code = readFileSync(source, 'utf8');
    assert.match(code, /NormalRoot=@"D:\\HereIAm-P6-R7-Isolated"/);
    const normal = code.slice(code.indexOf('static int Apply('), code.indexOf('static void Layouts()', code.indexOf('static int Apply(')));
    assert.match(normal, /directory=NormalDirectoryFor\(id\)/);
    assert.match(normal, /PrepareNormalDirectory\(id,identity.User\)/);
    assert.ok(normal.indexOf('CoordinatorJobNative.Verify(child.Job,report)') < normal.indexOf('InvokeHelper(true'));
    assert.ok(normal.indexOf('RequireWorkingDirectoryMetadata(Path.Combine(work,"empty-workspace"))') < normal.indexOf('CreateCli('));
    assert.match(normal, /AppIdProgram.VerifyImage\(Path.Combine\(directory,"codex.exe"\)\);VerifySelf\(selfHash\)/);
    const helper = code.slice(code.indexOf('static int Elevated('), code.indexOf('internal const string InspectOwnerHash'));
    assert.doesNotMatch(helper, /(?<!Normal)DirectoryFor\(id\)/);
    const paths = code.slice(code.indexOf('internal const string NormalRoot'), code.indexOf('static string JobName'));
    assert.match(paths, /new string\[\]\{".git",".codex"\}/);
    assert.doesNotMatch(paths, /ReadAllText|ReadAllBytes|Delete/);
    assert.match(paths, /Path.Combine\(cwd,"config.toml"\)/);
    assert.match(paths, /normal_cwd_config_present_or_unknown/);
    assert.match(code, /QueryLimits\(job,9,out value,144,IntPtr.Zero\)/);
    assert.match(code, /value.Basic.Flags==0x2008&&value.Basic.ActiveLimit==1/);
    for (const size of ['BasicLimit))==64', 'ExtendedLimit))==144', 'JobAccounting))==48']) assert.ok(code.includes(size));
    assert.match(normal, /Check\(CliStartupContract.ConfigMatches\(configReply,port\),"startup_config_rejected"\)/);
  });

  await t.test('v15b only adds the fixed outside-repository seven-lock historical cleanup', () => {
    const code = readFileSync(source, 'utf8');
    const recovery = code.slice(code.indexOf('internal static readonly Guid Closed15Attempt'), code.indexOf('static void Acl('));
    assert.match(recovery, /2718ce42-8bc5-42e8-9be3-2a8939c6157d/);
    assert.match(recovery, /Closed15Directory=@"D:\\HereIAm-P6-R7-Isolated\\2718ce428bc542e89be32a8939c6157d"/);
    assert.match(recovery, /directory=Closed15DirectoryFor\(id\)/);
    assert.match(recovery, /Check\(id==Closed15Attempt/);
    assert.match(recovery, /windows_text_gate_appid_coordinator_helper.v15.exe/);
    assert.match(recovery, /native-appid-coordinator-candidate-15.cs/);
    assert.match(recovery, /Number\(original\["win32_error"\]\)==1223/);
    assert.match(recovery, /Number\(original\["child_exit_code_before_termination"\]\)==0/);
    assert.match(recovery, /"closed15_history_before_rejected"/);
    assert.match(recovery, /"closed15_history_limits_rejected"/);
    assert.equal((recovery.match(/new EvidenceReadLock\(/g) || []).length, 7);
    assert.doesNotMatch(recovery, /CreateCli|CreateJob|OpenJobObject|ShellExecute|Directory.Delete|CommandLine|Process.Start|(?<!Closed15)DirectoryFor\(id\)/);
    assert.match(recovery, /"process_close_claimed"\]=false;report\["job_zero_claimed"\]=false/);
    const frozen = readFileSync(local('../../tmp/p6-r7-review/native-appid-coordinator-candidate-15b.cs'), 'utf8');
    const normal = value => value.slice(value.indexOf('static void Acl('), value.indexOf('static void Reject(')).replace(/\r\n/g, '\n');
    const beforeRecovery = value => value.slice(value.indexOf('internal sealed class CoordinatorBoundary'), value.indexOf('internal static readonly Guid Closed14Attempt')).replace(/\r\n/g, '\n');
    const histories = value => value.slice(value.indexOf('internal static readonly Guid Closed14Attempt'), value.indexOf('static void Acl(')).replace(/\r\n/g, '\n');
    assert.equal(histories(code), histories(frozen)); assert.equal(beforeRecovery(code), beforeRecovery(frozen));
    assert.match(code, /--cleanup-closed-v15"\)return CleanupClosedV15/);
  });

  await t.test('v16 detached entry preserves legacy flags and samples only a confirmed live held CLI', () => {
    const code = readFileSync(source, 'utf8');
    assert.match(code, /--apply-coordinator-detached-startup-synthetic"\)return Apply\(args\[1\],true\)/);
    assert.match(code, /--apply-coordinator-startup-synthetic"\)return Apply\(args\[1\]\)/);
    assert.match(code, /static int Apply\(string source,bool detached=false\)/);
    assert.match(code, /return detached\?0x0008040cU:0x08080404U/);
    const spawn = code.slice(code.indexOf('static void CreateCli('), code.indexOf('static int Apply('));
    assert.match(spawn, /true,CliCreationFlags\(detached\),arena.Text\(environment\)/);
    assert.match(spawn, /new IntPtr\(0x2000d\)/); assert.match(spawn, /new IntPtr\(0x20002\)/);
    assert.match(spawn, /Check\(handles.Length==3/); assert.match(spawn, /identity.Same\(MediumIdentity.OfProcess\(child.Handle\)\)/);
    assert.match(spawn, /TokenProof.Image\(child.Handle,image\);AppIdProgram.VerifyImage\(image\)/);
    const observation = code.slice(code.indexOf('static void ObserveLiveCli('), code.indexOf('static bool LiveObservationsComplete'));
    assert.match(observation, /CoordinatorNative.GetProcessId\(child.Handle\)==child.Pid&&TokenProof.Creation\(child.Handle\)==child.Created/);
    assert.match(observation, /before=Native.WaitForSingleObject\(child.Handle,0\);if\(before==258\)/);
    assert.ok(observation.indexOf('Native.QueryInformationJobObject') < observation.indexOf('after=Native.WaitForSingleObject'));
    assert.doesNotMatch(observation, /QueryFullProcessImageName|TokenProof.Image|OpenProcess|Terminate|Thread.Sleep/);
    const normal = code.slice(code.indexOf('static int Apply('), code.indexOf('static void Layouts()', code.indexOf('static int Apply(')));
    assert.match(normal, /stdio.Reply\(1,10000\);report\["initialize_replied"\]=true;if\(detached\)ObserveLiveCli\(report,"after_initialize",child\)/);
    assert.match(normal, /Check\(CliStartupContract.ConfigMatches\(configReply,port\),"startup_config_rejected"\);report\["config_checks_passed"\]=true;stdio.Check\(\);if\(detached\)ObserveLiveCli\(report,"after_config_before_eof",child\);stdio.EndInput\(\)/);
    assert.match(normal, /report\["single_process_enforcement_tested"\]=false/);
    assert.match(normal, /report\["detached_cli_compatibility_passed"\]=report\["coordinator_startup_passed"\]/);
    assert.match(code, /binding&&before==258&&queried&&after==258/);
    assert.match(code, /"active",live\?\(object\)accounting.Active:null/);
    assert.match(code, /"single_member_at_observation",live&&accounting.Active==1&&accounting.Total==1/);
  });

  await t.test('v16b reads only one cancelled install with five evidence locks and no rule mutations', () => {
    const code = readFileSync(source, 'utf8');
    const candidate = code.slice(code.indexOf('internal static readonly Guid Cancelled16Attempt'), code.indexOf('static void Reject('));
    assert.match(candidate, /56e435bd-05cb-4569-b86d-ba884d2eb717/);
    assert.match(candidate, /Cancelled16Directory=@"D:\\HereIAm-P6-R7-Isolated\\56e435bd05cb4569b86dba884d2eb717"/);
    assert.match(candidate, /directory=Cancelled16DirectoryFor\(id\)/);
    assert.equal((candidate.match(/new EvidenceReadLock\(/g) || []).length, 5);
    assert.match(candidate, /3c46568b216ed4c6c30c8576ebcd1101f091b95fd7d3b796eac8c028090a5560/);
    assert.match(candidate, /02b3285f9234fdf9b772a63410967b4bd573225c35ad3864e309f3285789ad21/);
    assert.match(candidate, /Number\(original\["win32_error"\]\)==1223/);
    assert.match(candidate, /Object.Equals\(journal\["phase"\],"prepared"\)&&journal\["child_pid"\]==null&&journal\["child_creation"\]==null/);
    assert.match(candidate, /RequireBindingInactive\(Number\(journal\["coordinator_pid"\]\)/);
    assert.match(candidate, /RequireCancelled16OwnerImageIdle\(\);RequireCopiedPathIdle\(image\)/);
    assert.match(candidate, /Process.GetProcessesByName\(Path.GetFileNameWithoutExtension\(Cancelled16OwnerImage\)\)/);
    assert.match(candidate, /Native.FwpmTransactionBegin0\(engine,1\)/);
    assert.match(candidate, /InspectionNative.GetFilter\(engine,ref key,out pointer\)/);
    assert.match(candidate, /filtersChecked==3&&filtersPresent==0&&sublayerChecked&&!sublayerPresent/);
    assert.match(candidate, /report\["filters_deleted_count"\]=0;report\["sublayers_deleted_count"\]=0/);
    assert.match(candidate, /"install-cancelled-inspect-report.json"/);
    assert.doesNotMatch(candidate, /FwpmFilterDelete|FwpmSubLayerDelete|FwpmFilterAdd|FwpmSubLayerAdd|FwpmTransactionCommit|CreateJob|CreateCli|Process.Start|Terminate|Directory.Delete|OpenJobObject|CommandLine|NetworkIsolation/);
    const frozen = readFileSync(local('../../tmp/p6-r7-review/native-appid-coordinator-candidate-16.cs'), 'utf8');
    const ordinary = value => value.slice(value.indexOf('static void Acl('), value.indexOf('internal static readonly Guid Cancelled16Attempt') >= 0 ? value.indexOf('internal static readonly Guid Cancelled16Attempt') : value.indexOf('static void Reject(')).replace(/\r\n/g, '\n');
    assert.equal(ordinary(code), ordinary(frozen));
    assert.match(code, /--inspect-cancelled-install-v16"\)return InspectCancelledV16/);
  });

});
