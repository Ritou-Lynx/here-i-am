#requires -Version 5.1
[CmdletBinding()]param(
 [switch]$Execute,
 [string]$BindingPath,[string]$ExpectedBindingSha256,[string]$ExpectedApprovalSha256,
 [string]$SessionDirectory,[string]$ControlDirectory,
 [ValidateSet('initial-activation','login-recovery','host-control-recovery')][string]$Phase
)
if(!$Execute){
 [Console]::Out.WriteLine('{"format":"p3-permit-producer-plan-v1","mode":"Plan","ioPerformed":false,"productionAuthorized":false}')
 return
}
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
Set-StrictMode -Version 2
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
# The exact frozen native source follows. It defines functions only and is part
# of this entrypoint's hash; no unvalidated source is loaded for bootstrapping.

#requires -Version 5.1
# Function library only. Caller loads the reviewed pinned bytes; no top-level I/O.
function Initialize-P4EvidenceNative {
 if('P4EvidenceLease' -as [type]){return}
 Add-Type -TypeDefinition @"
using System;using System.IO;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;using System.ComponentModel;using System.Security.Cryptography;using System.Security.AccessControl;using Microsoft.Win32.SafeHandles;
public sealed class P4EvidenceOpenException:IOException { public int NativeErrorCode {get;private set;} public string RequestedPath {get;private set;} public bool Directory {get;private set;} public P4EvidenceOpenException(string path,bool directory,int code):base("evidence_open_failed:"+code){NativeErrorCode=code;RequestedPath=path;Directory=directory;} }
public sealed class P4EvidenceLease:IDisposable {
 [StructLayout(LayoutKind.Sequential)]struct Info{public uint attr,c1,c2,a1,a2,w1,w2,volume,hi,lo,links,idHi,idLo;}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern SafeFileHandle CreateFile(string p,uint a,uint s,IntPtr sa,uint d,uint f,IntPtr t);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern uint GetFinalPathNameByHandle(SafeFileHandle h,StringBuilder b,uint n,uint f);
 [DllImport("advapi32.dll")]static extern uint GetSecurityInfo(SafeFileHandle h,int type,uint flags,out IntPtr o,out IntPtr g,out IntPtr d,out IntPtr s,out IntPtr sd);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode)]static extern bool ConvertSecurityDescriptorToStringSecurityDescriptor(IntPtr sd,uint rev,uint flags,out IntPtr text,out uint size);
 [DllImport("kernel32.dll")]static extern IntPtr LocalFree(IntPtr p);
 List<SafeFileHandle> parents=new List<SafeFileHandle>();SafeFileHandle handle;FileStream stream;string path,identity,owner;bool dir,priv;long max;readonly object streamSync=new object();
 public static void Plain(string p){if(String.IsNullOrEmpty(p)||p.Length<3||!Char.IsLetter(p[0])||p[1]!=':'||p[2]!='\\'||p.Substring(2).Contains(":")||p.Contains("/")||Path.GetFullPath(p)!=p)throw new IOException("evidence_path_rejected");foreach(var s in p.Substring(3).Split('\\'))if((s.Length==0&&p.Length!=3)||s.EndsWith(".")||s.EndsWith(" ")||s.IndexOfAny(Path.GetInvalidFileNameChars())>=0)throw new IOException("evidence_path_rejected");}
 static string Check(SafeFileHandle h,string p,bool directory){Info i;var b=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(h,b,32768,0);if(!GetFileInformationByHandle(h,out i)||n==0||n>=32768)throw new IOException("evidence_identity_failed");if((i.attr&0x400)!=0||((i.attr&0x10)!=0)!=directory||(!directory&&(p.Equals(@"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",StringComparison.OrdinalIgnoreCase)?i.links!=2:i.links!=1))||!String.Equals(b.ToString(),"\\\\?\\"+p,StringComparison.OrdinalIgnoreCase))throw new IOException("evidence_identity_rejected");return i.volume+":"+i.idHi+":"+i.idLo;}
 static SafeFileHandle Open(string p,bool directory,uint share){var h=CreateFile(p,directory?0x20081u:0x80020080u,share,IntPtr.Zero,3,0x02200000,IntPtr.Zero);if(h.IsInvalid){int error=Marshal.GetLastWin32Error();h.Dispose();throw new P4EvidenceOpenException(p,directory,error);}try{Check(h,p,directory);return h;}catch{h.Dispose();throw;}}
 static void Private(SafeFileHandle h,string owner){IntPtr o,g,d,s,sd,t=IntPtr.Zero;uint n;if(GetSecurityInfo(h,1,5,out o,out g,out d,out s,out sd)!=0)throw new IOException("evidence_acl_failed");try{if(!ConvertSecurityDescriptorToStringSecurityDescriptor(sd,1,5,out t,out n))throw new IOException("evidence_acl_failed");var raw=new RawSecurityDescriptor(Marshal.PtrToStringUni(t));if(raw.Owner==null||raw.Owner.Value!=owner||raw.DiscretionaryAcl==null||(raw.ControlFlags&ControlFlags.DiscretionaryAclProtected)==0)throw new IOException("evidence_acl_rejected");bool own=false;foreach(GenericAce a in raw.DiscretionaryAcl){var c=a as CommonAce;if(c==null||c.IsCallback)throw new IOException("evidence_acl_rejected");if(c.AceQualifier==AceQualifier.AccessAllowed){string sid=c.SecurityIdentifier.Value;if(sid!=owner&&sid!="S-1-5-18"&&sid!="S-1-5-32-544")throw new IOException("evidence_acl_rejected");if(sid==owner&&(c.AceFlags&AceFlags.InheritOnly)==0&&(c.AccessMask&0x1F01FF)==0x1F01FF)own=true;}}if(!own)throw new IOException("evidence_acl_rejected");}finally{if(t!=IntPtr.Zero)LocalFree(t);LocalFree(sd);}}
 public P4EvidenceLease(string p,string ownerSid,bool directory,bool privateRequired,long maximum){Plain(p);path=p;owner=ownerSid;dir=directory;priv=privateRequired;max=maximum;try{var ps=new List<string>();for(var q=Path.GetDirectoryName(p);!String.IsNullOrEmpty(q);q=Path.GetDirectoryName(q))ps.Insert(0,q);foreach(var q in ps)parents.Add(Open(q,true,3));handle=Open(p,directory,directory?3u:1u);identity=Check(handle,path,dir);if(priv)Private(handle,owner);if(!dir){stream=new FileStream(handle,FileAccess.Read);if(stream.Length<0||stream.Length>max)throw new IOException("evidence_size_rejected");}}catch{Dispose();throw;}}
 public string Identity {get{Assert();return identity;}}
 public long LinkCount {get{Assert();Info i;if(!GetFileInformationByHandle(handle,out i))throw new IOException("evidence_identity_failed");return i.links;}}
 public long Length {get{Assert();return dir?0:stream.Length;}}
 public void Assert(){if(handle==null||handle.IsClosed||Check(handle,path,dir)!=identity)throw new IOException("evidence_identity_changed");if(priv)Private(handle,owner);}
 public byte[] Bytes(){lock(streamSync){Assert();if(dir||stream.Length>max||stream.Length>Int32.MaxValue)throw new IOException("evidence_size_rejected");stream.Position=0;byte[] b=new byte[(int)stream.Length];int at=0,n;while(at<b.Length&&(n=stream.Read(b,at,b.Length-at))>0)at+=n;if(at!=b.Length||stream.ReadByte()!=-1)throw new IOException("evidence_bytes_changed");Assert();return b;}}
 public string Hash(){lock(streamSync){Assert();if(dir)throw new IOException("evidence_not_file");stream.Position=0;string h;using(var sha=SHA256.Create())h=BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","").ToLowerInvariant();Assert();return h;}}
 public void Dispose(){if(stream!=null){stream.Dispose();stream=null;}if(handle!=null){handle.Dispose();handle=null;}foreach(var p in parents)p.Dispose();parents.Clear();}
}
public static class P4EvidenceRegistry { public static readonly System.Collections.Hashtable Items=System.Collections.Hashtable.Synchronized(new System.Collections.Hashtable()); }
public static class P4StrictJson {
 sealed class Parser{
  string s;int i,depth;public Parser(string text){s=text;}
  void W(){while(i<s.Length&&(s[i]==' '||s[i]=='\r'||s[i]=='\n'||s[i]=='\t'))i++;}
  void E(){throw new IOException("evidence_json_rejected");}
  string S(){if(i>=s.Length||s[i++]!='"'){E();return null;}var b=new StringBuilder();while(i<s.Length){char c=s[i++];if(c=='"')return b.ToString();if(c<32){E();return null;}if(c=='\\'){if(i>=s.Length){E();return null;}c=s[i++];if(c=='u'){if(i+4>s.Length){E();return null;}int n;if(!Int32.TryParse(s.Substring(i,4),System.Globalization.NumberStyles.HexNumber,null,out n)){E();return null;}i+=4;b.Append((char)n);}else if(c=='"'||c=='\\'||c=='/')b.Append(c);else if(c=='b')b.Append('\b');else if(c=='f')b.Append('\f');else if(c=='n')b.Append('\n');else if(c=='r')b.Append('\r');else if(c=='t')b.Append('\t');else E();}else b.Append(c);}E();return null;}
  void V(){W();if(++depth>40||i>=s.Length){E();return;}char c=s[i];if(c=='{'){i++;W();var keys=new HashSet<string>(StringComparer.Ordinal);if(i<s.Length&&s[i]=='}')i++;else{while(true){W();string k=S();if(!keys.Add(k))E();W();if(i>=s.Length||s[i++]!=':')E();V();W();if(i>=s.Length)E();c=s[i++];if(c=='}')break;if(c!=',')E();}}}else if(c=='['){i++;W();if(i<s.Length&&s[i]==']')i++;else{while(true){V();W();if(i>=s.Length)E();c=s[i++];if(c==']')break;if(c!=',')E();}}}else if(c=='"')S();else{int start=i;while(i<s.Length&&",]} \r\n\t".IndexOf(s[i])<0)i++;string a=s.Substring(start,i-start);if(a!="true"&&a!="false"&&a!="null"&&!System.Text.RegularExpressions.Regex.IsMatch(a,@"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"))E();}depth--;}
  public void Run(){V();W();if(i!=s.Length)E();}
 }
 public static string Decode(byte[] bytes){if(bytes.Length>1048576)throw new IOException("evidence_json_size");string s=new UTF8Encoding(false,true).GetString(bytes);new Parser(s).Run();return s;}
}

public sealed class P4EvidencePump:IDisposable{
 System.Diagnostics.Process p;System.Collections.Concurrent.BlockingCollection<string> lines=new System.Collections.Concurrent.BlockingCollection<string>(32);System.Threading.Thread output,error;volatile string failure=null;volatile bool eof=false;long total=0;
 public P4EvidencePump(System.Diagnostics.Process child){p=child;output=new System.Threading.Thread(ReadOutput);error=new System.Threading.Thread(ReadError);output.IsBackground=true;error.IsBackground=true;output.Start();error.Start();}
 void ReadOutput(){try{var b=new StringBuilder();int c;while((c=p.StandardOutput.Read())>=0){if(System.Threading.Interlocked.Increment(ref total)>1048576){failure="evidence_output_limit";continue;}if(c=='\n'){string s=b.ToString();b.Length=0;if(s.EndsWith("\r"))s=s.Substring(0,s.Length-1);if(s.Length>0&&!lines.TryAdd(s))failure="evidence_output_queue";}else if(b.Length<65536)b.Append((char)c);else failure="evidence_output_line_limit";}if(b.Length!=0)failure="evidence_output_partial";}catch{failure="evidence_output_invalid";}finally{eof=true;lines.CompleteAdding();}}
 void ReadError(){try{int n=0,c;while((c=p.StandardError.Read())>=0)if(++n>0)failure=n>4096?"evidence_stderr_limit":"evidence_stderr_present";}catch{failure="evidence_stderr_invalid";}}
 public string Next(int timeout){if(failure!=null)throw new IOException(failure);string line;if(lines.TryTake(out line,Math.Max(0,timeout))){if(failure!=null)throw new IOException(failure);return line;}if(failure!=null)throw new IOException(failure);return null;}
 public bool OutputEof{get{return eof;}}
 public void Finish(){if(!output.Join(1000)||!error.Join(1000)||failure!=null)throw new IOException("evidence_drain_failed");}
 public void Dispose(){if(!output.IsAlive&&!error.IsAlive)lines.Dispose();}
}

"@
}
function Read-P4StrictJson([byte[]]$Bytes) {
 Initialize-P4EvidenceNative
 return ([P4StrictJson]::Decode($Bytes) | ConvertFrom-Json)
}
function Get-P4ByteHash([byte[]]$Bytes) {
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Write-P4ReceiptNative {
 param([Parameter(Mandatory=$true)]$Context,[Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][byte[]]$Bytes,[Parameter(Mandatory=$true)][string]$ExpectedSha256)
 $ErrorActionPreference='Stop'
 # Context is issued only by the pinned launcher's verified session; ordinary
 # hash-only read contexts never receive it. Fixed phase names prevent arbitrary paths.
 if($null-eq$script:P4IssuedContext -or ![object]::ReferenceEquals($Context,$script:P4IssuedContext) -or !$Context.Verified -or $Context.Failed -or $Context.Ended){throw 'evidence_write_unauthorized'}
 if($Name -cne (@('00-intent.json','01-result.json','02-commit.json')[$Context.Next]) -or $Bytes.Length -gt 32768 -or $ExpectedSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'evidence_write_rejected'}
 try {
  $Context.RootLease.Assert();$Context.AttemptLease.Assert()
  if((Get-P4ByteHash $Bytes) -cne $ExpectedSha256){throw 'evidence_write_hash'}
  $r=Read-P4StrictJson $Bytes
  $expectedKeys=@('format','evidenceMode','attemptId','sequence','phase','previousSha256','bindingSha256','approvalSha256','p3ReceiptSha256','runLedgerSha256','utcMs','identitySha256','payload')
  $receiptFormat='p4-evidence-receipt-v1'
  if($Context.Policy.format-ceq'p4-evidence-policy-v2'){
   $expectedKeys+=,'evidenceNamespace';$receiptFormat='p4-evidence-receipt-v2'
   if((ConvertTo-P4CanonicalJson $r.evidenceNamespace)-cne(ConvertTo-P4CanonicalJson $Context.Policy.evidenceNamespace)){throw 'evidence_write_namespace'}
  }elseif($Context.Policy.format-cne'p4-evidence-policy-v1'){throw 'evidence_write_policy'}
  if((@($r.PSObject.Properties.Name|Sort-Object)-join ',') -cne (($expectedKeys|Sort-Object)-join ',')){throw 'evidence_write_schema'}
  if($r.evidenceMode -cne $Context.Policy.mode -or $r.format -cne $receiptFormat -or $r.attemptId -cne $Context.Policy.attemptId -or $r.sequence -ne $Context.Next -or $r.phase -cne @('intent','result','commit')[$Context.Next] -or $r.previousSha256 -cne $Context.Previous){throw 'evidence_write_chain'}
  foreach($key in @('bindingSha256','approvalSha256','p3ReceiptSha256','runLedgerSha256')){if($r.$key -cne $Context.Policy.$key){throw 'evidence_write_binding'}}
  if($r.identitySha256 -cne $Context.IdentitySha256 -or $r.payload.backupEvidenceComplete -ne $false -or $r.payload.overallP4Passed -ne $false){throw 'evidence_write_gate'}
  if($r.utcMs -lt $Context.Policy.notBeforeUtcMs -or $r.utcMs -gt $Context.Policy.notAfterUtcMs){throw 'evidence_write_time'}
  $target=Join-Path $Context.AttemptPath $Name
  [OwnedArtifactNative]::Write($target,$Context.Owner,$Bytes)
  $read=[P4EvidenceLease]::new($target,$Context.Owner,$false,$true,32768)
  try{if($read.Hash() -cne $ExpectedSha256 -or $read.Length -ne $Bytes.Length){throw 'evidence_write_readback'}}finally{$read.Dispose()}
  $Context.RootLease.Assert();$Context.AttemptLease.Assert()
  $Context.Previous=$ExpectedSha256;$Context.Next++;if($Context.Next-eq3){$Context.Ended=$true}
  return [ordered]@{name=$Name;sha256=$ExpectedSha256;byteCount=$Bytes.Length;createNew=$true;flushToDisk=$true;sameHandleReadback=$true;pathReadback=$true;sameIdentity=$true;privateProtectedAcl=$true;singleLink=$true;noReparse=$true}
 }catch{$Context.Failed=$true;throw 'evidence_write_failed'}
}


$lease=$null;$bootstrap=New-Object 'Collections.Generic.List[IDisposable]'
try{
 if(!$Phase-or$ExpectedBindingSha256-cnotmatch'^[a-f0-9]{64}$'-or$ExpectedApprovalSha256-cnotmatch'^[a-f0-9]{64}$'){throw 'producer_arguments'}
 if($PSVersionTable.PSEdition-cne'Desktop'-or$PSVersionTable.PSVersion.Major-ne5-or[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName-ine'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'){throw 'producer_runtime'}
 $env:PSModulePath='C:\Windows\System32\WindowsPowerShell\v1.0\Modules'
 $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 if($owner-cne'S-1-5-21-111111111-222222222-333333333-1001'){throw 'producer_owner'}
 $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
 if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'producer_elevated'}
 Initialize-P4EvidenceNative
 $nativePath=Join-Path $PSScriptRoot 'evidence-native.ps1'
 $launcherPath=Join-Path $PSScriptRoot 'evidence-pinned-launch.ps1'
 $native=[P4EvidenceLease]::new($nativePath,$owner,$false,$true,1048576);$bootstrap.Add($native)
 $launcher=[P4EvidenceLease]::new($launcherPath,$owner,$false,$true,1048576);$bootstrap.Add($launcher)
 if($native.Hash()-cne'fdd9e0fa8345597f8530fe28e28c3b873851a7a96b98e9aa8d49a264036ce8df'-or$launcher.Hash()-cne'c2a98c4a0c939a1709ef59c3efd378b44a5dc1e91a339b708ad13c956e1ac22a'){throw 'producer_bootstrap_hash'}
 . ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($launcher.Bytes())))
 $lease=Get-ReviewedEvidenceLease -BindingPath $BindingPath -ExpectedBindingSha256 $ExpectedBindingSha256 -ExpectedApprovalSha256 $ExpectedApprovalSha256 -ForIdentity -ObservationPhase 'host-attached' -LifecyclePhase $Phase
 if($lease.Mode-cne'reviewed-live'-or$lease.Path('p3_producer')-cne$PSCommandPath-or$lease.Hash('evidence_native')-cne$native.Hash()-or$lease.Hash('evidence_launcher')-cne$launcher.Hash()){throw 'producer_locked_source'}
 $record=Get-P4LeaseRecord $lease
 $approval=$lease.ReadJson('approval')
 if($approval.scope-cne'task-update-enable-run-attach-p3-p4-normal-close-once'){throw 'producer_scope'}
 foreach($role in @('identity_library','activation_proof','p3_library','identity_sampler','recovery_helper')){
  . ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($lease.Bytes($role))))
 }
 $null=$lease.AttachSession($SessionDirectory,$ControlDirectory)
 Initialize-ReviewedIdentity $lease
 $null=Open-ReviewedLifecyclePhase -Lease $lease
 if($Phase-ceq'initial-activation'){
  $result=Wait-InitialReviewedP3Permit -Lease $lease
 }else{
  $null=Set-ReviewedIdentityActivation -Lease $lease -Phase $Phase
  $result=Invoke-ReviewedP3Permit -Lease $lease
 }
 if($result.format-cne'p3-permit-producer-result-v1'-or$result.passed-isnot[bool]-or$result.passed-ne$true-or$result.permitSha256-cnotmatch'^[a-f0-9]{64}$'){throw 'producer_result'}
 $record=Get-P4LeaseRecord $lease
 $permit=[P4EvidenceLease]::new((Join-Path $record.Attachment.ControlPath 'p3-backup-permit.json'),$owner,$false,$true,1048576)
 try{if($permit.Hash()-cne$result.permitSha256){throw 'producer_final_readback'}}finally{$permit.Dispose()}
 [Console]::Out.WriteLine((ConvertTo-IdentityCanonicalJson $result))
}catch{
 [Console]::Error.WriteLine('p3_producer_rejected')
 exit 1
}finally{
 if($null-ne$lease){$lease.Dispose()}
 foreach($h in $bootstrap){$h.Dispose()}
}
