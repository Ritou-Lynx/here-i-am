[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'


# Pure gate, also exercised with fake callbacks: a failed probe never invokes suites.
function Invoke-Schema6GatedSuites([scriptblock]$Probe,[scriptblock]$Suites) {
 $probeExit=[int](& $Probe)
 if($probeExit -ne 0){return $probeExit}
 return [int](& $Suites)
}
function Invoke-Schema6NativeProbe([string]$NodePath) {
 $info=[Diagnostics.ProcessStartInfo]::new()
 $info.FileName=$NodePath
 $info.Arguments='"'+(Join-Path $PSScriptRoot 'ci_native_probe.mjs')+'"'
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $info.EnvironmentVariables.Clear()
 # Same fixed OS-only environment as production cleanEnvironment on Windows.
 foreach($name in @('SystemRoot','WINDIR','TEMP','TMP','COMSPEC')){
  $value=[Environment]::GetEnvironmentVariable($name)
  if($null -ne $value){$info.EnvironmentVariables[$name]=$value}
 }
 $info.EnvironmentVariables['PATHEXT']='.EXE'
 $process=[Diagnostics.Process]::new();$process.StartInfo=$info
 try {
  if(-not $process.Start()){throw 'probe_start_failed'}
  $output=$process.StandardOutput.ReadToEndAsync();$errors=$process.StandardError.ReadToEndAsync()
  # Probe has five individually bounded 60s native calls and one unchanged 10s gate.
  $process.WaitForExit()
  $text=$output.GetAwaiter().GetResult();$null=$errors.GetAwaiter().GetResult()
  if($text.Length -gt 32768){throw 'probe_report_invalid'}
  $value=$text|ConvertFrom-Json -ErrorAction Stop
  if($value.format -cne 'schema6-ci-native-probe-v1' -or $value.passed -isnot [bool]){throw 'probe_report_invalid'}
  $stages=@();$allowed=@('no_op','prepare_root','default_acl','default_assert','system_module_assert','production_gate','cleanup')
  if(@($value.stages).Count -gt $allowed.Count){throw 'probe_report_invalid'}
  foreach($stage in $value.stages){
   if($stage.stage -cnotin $allowed -or $stage.error_code -cnotin @('none','timeout','operation_failed','process_failed') -or $stage.timed_out -isnot [bool]){throw 'probe_report_invalid'}
   foreach($field in @('elapsed_ms','exit_code')){
    $number=$stage.$field
    if($field -eq 'exit_code' -and $null -eq $number){continue}
    if(($number -isnot [int] -and $number -isnot [long]) -or $number -lt 0 -or $number -gt 1000000000){throw 'probe_report_invalid'}
   }
   $metrics=$null
   if($null -ne $stage.metrics){
    $metrics=@{}
    foreach($field in @('script_elapsed_ms','module_directory_count','module_path_count')){
     $number=$stage.metrics.$field
     if(($number -isnot [int] -and $number -isnot [long]) -or $number -lt 0 -or $number -gt 1000000000){throw 'probe_report_invalid'}
     $metrics[$field]=$number
    }
   }
   $stages+=@{stage=$stage.stage;elapsed_ms=$stage.elapsed_ms;exit_code=$stage.exit_code;timed_out=$stage.timed_out;error_code=$stage.error_code;metrics=$metrics}
  }
  $passed=$process.ExitCode -eq 0 -and $value.passed -and $stages.Count -eq $allowed.Count -and
   (($stages|ForEach-Object{$_.stage}) -join ',') -ceq ($allowed -join ',') -and @($stages|Where-Object{$_.error_code -ne 'none'}).Count -eq 0
  $safe=@{format='schema6-ci-native-probe-v1';passed=[bool]$passed;stages=$stages}
  $json=$safe|ConvertTo-Json -Depth 5 -Compress
  [IO.File]::WriteAllText((Join-Path (Get-Location) 'build/ci/schema6-native-probe.json'),$json,[Text.UTF8Encoding]::new($false))
  [Console]::Out.WriteLine($json)
  if($passed){return 0}
 } catch {
  $json='{"format":"schema6-ci-native-probe-v1","passed":false,"stages":[]}'
  [IO.File]::WriteAllText((Join-Path (Get-Location) 'build/ci/schema6-native-probe.json'),$json,[Text.UTF8Encoding]::new($false))
  [Console]::Out.WriteLine($json)
 }
 finally {$process.Dispose()}
 # The existing artifact path remains present even when the suite is not launched.
 [IO.File]::WriteAllText((Join-Path (Get-Location) 'build/ci/schema6-windows.tap'),"TAP version 13"+[Environment]::NewLine+"1..1"+[Environment]::NewLine+"not ok 1 - CI native preflight rejected; full suite not started"+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
 return 1
}

# Hosted Windows runners have an elevated token whose default file owner can
# be Administrators. Give this synthetic test process tree a user-owned default
# instead. This does not change machine policy or relax production ACL checks.
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
public static class Schema6SyntheticTokenOwner {
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr p, uint access, out IntPtr token);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool GetTokenInformation(IntPtr token, int info, IntPtr data, int size, out int needed);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool SetTokenInformation(IntPtr token, int info, IntPtr data, int size);
  public static string Set(string owner) {
    IntPtr token;
    if (!OpenProcessToken(GetCurrentProcess(), 0x0088, out token)) throw new Win32Exception();
    IntPtr previous = IntPtr.Zero, sidBuffer = IntPtr.Zero, ownerBuffer = IntPtr.Zero;
    try {
      int length;
      GetTokenInformation(token, 4, IntPtr.Zero, 0, out length);
      previous = Marshal.AllocHGlobal(length);
      if (!GetTokenInformation(token, 4, previous, length, out length)) throw new Win32Exception();
      string old = new SecurityIdentifier(Marshal.ReadIntPtr(previous)).Value;
      if (old == owner) return old;
      var sid = new SecurityIdentifier(owner);
      byte[] bytes = new byte[sid.BinaryLength]; sid.GetBinaryForm(bytes, 0);
      sidBuffer = Marshal.AllocHGlobal(bytes.Length); Marshal.Copy(bytes, 0, sidBuffer, bytes.Length);
      ownerBuffer = Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(ownerBuffer, sidBuffer);
      if (!SetTokenInformation(token, 4, ownerBuffer, IntPtr.Size)) throw new Win32Exception();
      return old;
    } finally {
      if (previous != IntPtr.Zero) Marshal.FreeHGlobal(previous);
      if (sidBuffer != IntPtr.Zero) Marshal.FreeHGlobal(sidBuffer);
      if (ownerBuffer != IntPtr.Zero) Marshal.FreeHGlobal(ownerBuffer);
      CloseHandle(token);
    }
  }
}
'@
$owner = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$previousOwner = [Schema6SyntheticTokenOwner]::Set($owner)
try {
  New-Item -ItemType Directory -Force build/ci | Out-Null
  # The small hosted runner cannot service concurrent suites' native ACL/DPAPI
  # subprocess trees within production deadlines. Serialize suites, not checks.
  # Every original test still runs once. Both reporters observe the same run.
  $nodePath=(Get-Command node.exe -ErrorAction Stop).Source
  $testExitCode = Invoke-Schema6GatedSuites -Probe {Invoke-Schema6NativeProbe $nodePath} -Suites {
    & $nodePath --test --test-concurrency=1 --test-reporter=spec --test-reporter=tap --test-reporter-destination=stdout --test-reporter-destination=build/ci/schema6-windows.tap tools/i_core/release_schema6/*.test.mjs tools/i_core/release_schema6/lifecycle/*.test.mjs | ForEach-Object {Write-Host $_}
    return $LASTEXITCODE
  }
} finally {
  [void][Schema6SyntheticTokenOwner]::Set($previousOwner)
}
exit $testExitCode
