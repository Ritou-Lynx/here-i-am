# Test-only observer: the fixed guardian explicitly terminates the Job on parent
# death. Keep an independent query handle to verify active=0; completion delivery
# alone is not guaranteed during teardown. This is not a kill-on-close-only test.
param([Parameter(Mandatory=$true)][string]$ControlDirectory,[switch]$CrashGuardian)
$ErrorActionPreference='Stop'
$env:PSModulePath="$PSHOME\Modules"
$runtime=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../runtime_upgrade/r3'))
. (Join-Path $runtime 'protected_paths.ps1')
Assert-ProtectedPath $ControlDirectory -Root
if((Split-Path $ControlDirectory -Leaf) -notmatch '^control-[a-f0-9]+$' -or (Split-Path (Split-Path $ControlDirectory -Parent) -Leaf) -notmatch '^mda2-r3-') { throw 'self_created_fixture_required' }
$launch=Get-Content -LiteralPath (Join-Path $ControlDirectory 'launch.json') -Raw | ConvertFrom-Json
if(Test-Path -LiteralPath (Join-Path $ControlDirectory 'startup-barrier.json')) {
  $ready=Get-Content -LiteralPath (Join-Path $ControlDirectory 'startup-barrier.json') -Raw | ConvertFrom-Json
  $guardian=@{pid=$ready.guardian_pid}
} else {
  $ready=Get-Content -LiteralPath (Join-Path $ControlDirectory 'ready.json') -Raw | ConvertFrom-Json
  $guardian=Get-Content -LiteralPath (Join-Path $ControlDirectory 'guardian-ready.json') -Raw | ConvertFrom-Json
}
if($ready.token -ne $launch.token) { throw 'witness_binding_mismatch' }
$node=Join-Path $launch.release 'runtime/node.exe'
Assert-ProtectedPath $node
if((Get-FileHash -LiteralPath $node).Hash -ne '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f') { throw 'node_fingerprint_mismatch' }
$source=[IO.File]::ReadAllText((Join-Path $runtime 'owned_job.ps1'))
$native=$source.Substring($source.IndexOf('using System;'))
$native=$native.Substring(0,$native.IndexOf('  public static Receipt Run(')).Replace('Mda2R3OwnedJob','R3Witness')
$body=@'
  [StructLayout(LayoutKind.Sequential)] struct PORT_ASSOC { public IntPtr key,port; }
  [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr CreateIoCompletionPort(IntPtr file,IntPtr existing,IntPtr key,uint count);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int type,ref PORT_ASSOC value,uint size);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetQueuedCompletionStatus(IntPtr port,out uint bytes,out IntPtr key,out IntPtr overlapped,uint timeout);
  static void Image(IntPtr handle,string expected) {
    var image=new StringBuilder(4096); uint size=4096;
    if(handle==IntPtr.Zero || !QueryFullProcessImageName(handle,0,image,ref size) || !String.Equals(image.ToString(),expected,StringComparison.OrdinalIgnoreCase)) throw new Exception("witness_image_mismatch");
  }
  public static string Observe(string node,string entry,string root,string runId,uint servicePid,uint guardianPid,uint parentPid,bool crashGuardian) {
    IntPtr job=IntPtr.Zero,port=IntPtr.Zero,service=IntPtr.Zero,grand=IntPtr.Zero,guardian=IntPtr.Zero,parent=IntPtr.Zero;
    var child=new PROCESS_INFORMATION();
    bool empty=false; uint serviceCode=259,memberCode=259,grandCode=259,guardianCode=259,parentCode=259;
    try {
      job=OpenJobObject(0x001F003F,false,"Local\\MDA2R3-"+runId);
      if(job==IntPtr.Zero) throw new Exception("witness_job_open_failed");
      port=CreateIoCompletionPort(new IntPtr(-1),IntPtr.Zero,IntPtr.Zero,1);
      var assoc=new PORT_ASSOC(); assoc.key=new IntPtr(19); assoc.port=port;
      if(port==IntPtr.Zero || !SetInformationJobObject(job,7,ref assoc,(uint)Marshal.SizeOf(typeof(PORT_ASSOC)))) throw new Exception("witness_port_failed");
      service=OpenProcess(0x101000,false,servicePid); Image(service,node);
      guardian=OpenProcess(crashGuardian?0x101001u:0x101000u,false,guardianPid); Image(guardian,Path.Combine(Environment.GetEnvironmentVariable("SystemRoot"),"System32\\WindowsPowerShell\\v1.0\\powershell.exe"));
      parent=OpenProcess(0x101000,false,parentPid); Image(parent,Path.Combine(Environment.GetEnvironmentVariable("SystemRoot"),"System32\\WindowsPowerShell\\v1.0\\powershell.exe"));
      var startup=new STARTUPINFO(); startup.cb=(uint)Marshal.SizeOf(typeof(STARTUPINFO));
      if(!CreateProcess(node,new StringBuilder(Quote(node)+" "+Quote(entry)+" "+Quote(root)+" "+runId+" parent"),IntPtr.Zero,IntPtr.Zero,false,0x08000004,IntPtr.Zero,root,ref startup,out child)) throw new Exception("witness_fixture_spawn_failed");
      if(!AssignProcessToJobObject(job,child.process)) throw new Exception("witness_fixture_assign_failed");
      ResumeThread(child.thread);
      // Get a handle to the actual grandchild while its unique fixture is alive.
      var clock=Stopwatch.StartNew(); string descendant=Path.Combine(root,"descendant.json");
      while(!File.Exists(descendant) && clock.ElapsedMilliseconds<10000) Thread.Sleep(25);
      var match=System.Text.RegularExpressions.Regex.Match(File.ReadAllText(descendant),"\"pid\"\\s*:\\s*(\\d+)");
      grand=OpenProcess(0x101000,false,UInt32.Parse(match.Groups[1].Value)); Image(grand,node);
      File.WriteAllText(Path.Combine(root,"witness-ready"),runId);
      if(crashGuardian && !TerminateProcess(guardian,137)) throw new Exception("guardian_test_termination_failed");
      while(clock.ElapsedMilliseconds<180000) {
        uint message; IntPtr key,overlapped;
        GetQueuedCompletionStatus(port,out message,out key,out overlapped,100);
        if(Accounting(job).active==0) { empty=true; break; }
      }
      bool serviceExit=WaitForSingleObject(service,5000)==0 && GetExitCodeProcess(service,out serviceCode);
      bool memberExit=WaitForSingleObject(child.process,5000)==0 && GetExitCodeProcess(child.process,out memberCode);
      bool grandExit=WaitForSingleObject(grand,5000)==0 && GetExitCodeProcess(grand,out grandCode);
      bool guardianExit=WaitForSingleObject(guardian,5000)==0 && GetExitCodeProcess(guardian,out guardianCode);
      bool parentExit=WaitForSingleObject(parent,5000)==0 && GetExitCodeProcess(parent,out parentCode);
      return "{\"run_id\":\""+runId+"\",\"job_active_zero_query\":"+empty.ToString().ToLowerInvariant()+",\"service_exit_confirmed\":"+serviceExit.ToString().ToLowerInvariant()+",\"member_exit_confirmed\":"+memberExit.ToString().ToLowerInvariant()+",\"grandchild_exit_confirmed\":"+grandExit.ToString().ToLowerInvariant()+",\"guardian_exit_confirmed\":"+guardianExit.ToString().ToLowerInvariant()+",\"parent_exit_confirmed\":"+parentExit.ToString().ToLowerInvariant()+",\"service_exit_code\":"+serviceCode+",\"member_exit_code\":"+memberCode+",\"grandchild_exit_code\":"+grandCode+",\"guardian_exit_code\":"+guardianCode+",\"parent_exit_code\":"+parentCode+"}";
    } finally {
      if(job!=IntPtr.Zero) { if(!empty) TerminateJobObject(job,124); CloseHandle(job); }
      if(child.thread!=IntPtr.Zero) CloseHandle(child.thread);
      if(child.process!=IntPtr.Zero) CloseHandle(child.process);
      if(service!=IntPtr.Zero) CloseHandle(service);
      if(grand!=IntPtr.Zero) CloseHandle(grand);
      if(guardian!=IntPtr.Zero) CloseHandle(guardian);
      if(parent!=IntPtr.Zero) CloseHandle(parent);
      if(port!=IntPtr.Zero) CloseHandle(port);
    }
  }
}
'@
Add-Type -TypeDefinition ($native+$body)
$result=[R3Witness]::Observe($node,(Join-Path $PSScriptRoot 'descendant_fixture.mjs'),$ControlDirectory,$launch.token,$ready.pid,$guardian.pid,$launch.parent_pid,[bool]$CrashGuardian)
[IO.File]::WriteAllText((Join-Path $ControlDirectory 'process-witness.json'),$result,[Text.UTF8Encoding]::new($false))
