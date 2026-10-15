param(
    [Parameter(Mandatory = $true)][ValidateSet('A', 'B')][string]$Variant,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
    [string]$NodePath = 'node.exe'
)
$ErrorActionPreference = 'Stop'
# A task does not inherit the runner's environment. Require its short-lived permit.
$permit = Get-Content -LiteralPath (Join-Path $EvidenceDirectory 'hosted-job.json') -Raw | ConvertFrom-Json
if (-not $permit.githubHosted -or $permit.machine -ne $env:COMPUTERNAME -or
    [DateTime]::UtcNow -ge [DateTime]::Parse($permit.expiresUtc).ToUniversalTime() -or
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $permit.userSid -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -eq $permit.runnerSessionId) {
    throw 'hosted_interactive_test_identity_required'
}
# FreeConsole precedes WinForms initialization in B.
Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class LogoffConsole {
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool FreeConsole();
}
'@
if ($Variant -eq 'B') { $null = [LogoffConsole]::FreeConsole() }
$NodePath = (Get-Command $NodePath -CommandType Application -ErrorAction Stop).Source
Add-Type -AssemblyName System.Windows.Forms, System.Web.Extensions
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing,System.Web.Extensions -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public sealed class LogoffProbe : Form {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct Startup {
        public uint cb; public string reserved,desktop,title;
        public uint x,y,cx,cy,charsX,charsY,fill,flags;
        public ushort show,reserved2;
        public IntPtr reservedPtr,input,output,error;
    }
    [StructLayout(LayoutKind.Sequential)] struct ProcessInfo {
        public IntPtr process,thread; public uint pid,tid;
    }
    delegate bool CtrlHandler(uint kind);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetConsoleCtrlHandler(CtrlHandler handler,bool add);
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    [DllImport("kernel32.dll")] static extern uint GetConsoleCP();
    [DllImport("kernel32.dll")] static extern void GetSystemTimePreciseAsFileTime(out long time);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcess(
        string app,StringBuilder command,IntPtr ps,IntPtr ts,bool inherit,uint flags,IntPtr env,
        string cwd,ref Startup startup,out ProcessInfo info);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool ShutdownBlockReasonCreate(IntPtr window,string reason);
    [DllImport("user32.dll")] static extern bool ShutdownBlockReasonDestroy(IntPtr window);
    readonly object gate = new object();
    readonly JavaScriptSerializer json = new JavaScriptSerializer();
    readonly string directory,variant;
    readonly CtrlHandler ctrl;
    readonly uint childPid;
    readonly Timer readyTimer = new Timer();
    bool ready;

    static string Quote(string value) {
        if (value.IndexOf('"') >= 0 || value.EndsWith("\\") || value.IndexOf('\n') >= 0 || value.IndexOf('\r') >= 0)
            throw new ArgumentException("invalid_process_argument");
        return "\"" + value + "\"";
    }
    void Write(string filename, Dictionary<string,object> item, bool append) {
        lock(gate) {
            item["pid"] = Process.GetCurrentProcess().Id;
            if(!item.ContainsKey("ticks")) {
                item["ticks"] = Stopwatch.GetTimestamp().ToString();
                long time; GetSystemTimePreciseAsFileTime(out time);
                item["utc_filetime"] = time.ToString();
                item["utc"] = DateTime.FromFileTimeUtc(time).ToString("o");
            }
            byte[] bytes = Encoding.UTF8.GetBytes(json.Serialize(item) + "\n");
            using(var file = new FileStream(Path.Combine(directory,filename), append ? FileMode.Append : FileMode.Create,
                FileAccess.Write,FileShare.ReadWrite,4096,FileOptions.WriteThrough)) {
                file.Write(bytes,0,bytes.Length); file.Flush(true);
            }
        }
    }
    void Event(string name,long wparam,long lparam) {
        long ticks=Stopwatch.GetTimestamp();
        long time; GetSystemTimePreciseAsFileTime(out time);
        Write("host-events.jsonl",new Dictionary<string,object> {
            {"event",name},{"wparam",wparam},{"lparam",lparam},
            {"ticks",ticks.ToString()},{"utc_filetime",time.ToString()},
            {"utc",DateTime.FromFileTimeUtc(time).ToString("o")}
        },true);
    }
    bool OnCtrl(uint kind) {
        string name = kind==5 ? "CTRL_LOGOFF_EVENT" : kind==2 ? "CTRL_CLOSE_EVENT" : kind==6 ? "CTRL_SHUTDOWN_EVENT" : "CTRL_"+kind;
        try { Event(name,kind,0); } catch { /* A forced shutdown may prevent further IO. */ }
        return true;
    }
    public LogoffProbe(string selected,string evidence,string node,string child) {
        directory=evidence; variant=selected;
        ctrl=OnCtrl;
        bool registered=SetConsoleCtrlHandler(ctrl,true);
        Write("host-events.jsonl", new Dictionary<string,object> {
            {"event","host_started"},{"variant",variant},{"console_window",GetConsoleWindow().ToInt64().ToString()},
            {"ctrl_handler_registered",registered},{"ctrl_handler_error",registered ? 0 : Marshal.GetLastWin32Error()},
            {"session_id",Process.GetCurrentProcess().SessionId},{"qpc_frequency",Stopwatch.Frequency.ToString()}
        },true);
        ShowInTaskbar=false; FormBorderStyle=FormBorderStyle.None; Text="Logoff reproduction "+variant;
        IntPtr window=Handle; // Real hidden top-level HWND, not a message-only window.
        Startup startup=new Startup(); startup.cb=(uint)Marshal.SizeOf(typeof(Startup));
        ProcessInfo info;
        uint flags=variant=="A" ? 0x08000000u : 0x00000008u;
        var command=new StringBuilder(Quote(node)+" "+Quote(child)+" "+Quote(directory));
        if(!CreateProcess(node,command,IntPtr.Zero,IntPtr.Zero,false,flags,IntPtr.Zero,
            Path.GetDirectoryName(child),ref startup,out info)) throw new Win32Exception(Marshal.GetLastWin32Error());
        childPid=info.pid;
        CloseHandle(info.thread); CloseHandle(info.process);
        Event("child_started",childPid,flags);
        readyTimer.Interval=100;
        readyTimer.Tick += delegate {
            // Both the HWND/message pump and the child have to be running before logoff.
            if(!ready && File.Exists(Path.Combine(directory,"child-ready.json"))) {
                Write("ready.json",new Dictionary<string,object> {
                    {"event","ready"},{"variant",variant},{"child_pid",childPid},
                    {"session_id",Process.GetCurrentProcess().SessionId},{"creation_flags",flags},
                    {"window",window.ToInt64().ToString()},{"console_attached",GetConsoleCP()!=0}
                },false);
                ready=true; readyTimer.Stop();
            }
        };
        readyTimer.Start();
    }
    protected override void SetVisibleCore(bool value) {
        if(!IsHandleCreated) CreateHandle();
        base.SetVisibleCore(false);
    }
    protected override void WndProc(ref Message message) {
        if(message.Msg==0x0011 || message.Msg==0x0016) {
            Event(message.Msg==0x0011 ? "WM_QUERYENDSESSION" : "WM_ENDSESSION",
                message.WParam.ToInt64(),message.LParam.ToInt64());
            if(message.Msg==0x0011) {
                if(variant=="B") {
                    bool result=ShutdownBlockReasonCreate(Handle,"Recording bounded logoff reproduction evidence");
                    Event("ShutdownBlockReasonCreate",result ? 1 : 0,result ? 0 : Marshal.GetLastWin32Error());
                }
                message.Result=new IntPtr(1); return;
            }
            if(message.WParam!=IntPtr.Zero) Application.ExitThread();
            message.Result=IntPtr.Zero; return;
        }
        base.WndProc(ref message);
    }
    public static int Run(string selected,string evidence,string node,string child) {
        using(var window=new LogoffProbe(selected,evidence,node,child)) {
            int code=1;
            try { Application.Run(window); code=0; }
            finally {
                window.Write("exit.json",new Dictionary<string,object>{{"event","host_exit"},{"code",code}},false);
                if(window.IsHandleCreated) ShutdownBlockReasonDestroy(window.Handle);
                window.readyTimer.Dispose();
                SetConsoleCtrlHandler(window.ctrl,false);
                GC.KeepAlive(window.ctrl);
            }
        }
        return 0;
    }
}
'@
try {
    exit [LogoffProbe]::Run($Variant, $EvidenceDirectory, $NodePath, (Join-Path $PSScriptRoot 'probe_child.mjs'))
} catch {
    # Only fixture exceptions, never environment variables or command arguments.
    [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'host-error.txt'), $_.Exception.GetType().FullName)
    exit 1
}
