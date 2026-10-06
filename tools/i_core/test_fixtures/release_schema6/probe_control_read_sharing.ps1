[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OwnedJobScript,[Parameter(Mandatory=$true)][string]$Directory)
$ErrorActionPreference='Stop'
. $OwnedJobScript
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
public static class SyntheticRenamePublisher {
 public static string Read(Type reader,string target) {return (string)reader.GetMethod("ReadOptionalControl",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Static).Invoke(null,new object[]{target});}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateFile(string name,uint access,uint share,IntPtr security,uint mode,uint flags,IntPtr template);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetFileInformationByHandle(IntPtr file,int kind,IntPtr information,uint size);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr file);
 public static IntPtr Publish(string pending,string target) {
  // Reproduce the final stage of MoveFile: renamed, publisher DELETE handle open.
  IntPtr file=CreateFile(pending,0x00010000,7,IntPtr.Zero,3,0,IntPtr.Zero);
  if(file==new IntPtr(-1))throw new Exception("synthetic_publisher_open_failed");
  byte[] name=Encoding.Unicode.GetBytes(target);int offset=IntPtr.Size==8?20:12;
  IntPtr information=Marshal.AllocHGlobal(offset+name.Length);
  try{
   for(int i=0;i<offset;i++)Marshal.WriteByte(information,i,0);
   Marshal.WriteInt32(information,offset-4,name.Length);Marshal.Copy(name,0,IntPtr.Add(information,offset),name.Length);
   if(!SetFileInformationByHandle(file,3,information,(uint)(offset+name.Length)))throw new Exception("synthetic_publish_failed");
   return file;
  }catch{CloseHandle(file);throw;}finally{Marshal.FreeHGlobal(information);}
 }
}
'@
$key=[Text.Encoding]::UTF8.GetBytes('synthetic-control-key')
$hmac=New-Object Security.Cryptography.HMACSHA256(,$key)
try{$valid=([BitConverter]::ToString($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes(('a'*64)+'|'+('b'*64)+'|close')))).Replace('-','').ToLowerInvariant()}finally{$hmac.Dispose()}
$oldRejected=$false;$validAccepted=$false;$forgedRejected=$false;$concurrentRead=$false
foreach($kind in @('valid','forged')){
 $pending=Join-Path $Directory ($kind+'.pending');$target=Join-Path $Directory $kind
 [IO.File]::WriteAllText($pending,$(if($kind -eq 'valid'){$valid}else{'0'*64}),[Text.UTF8Encoding]::new($false))
 $publisher=[SyntheticRenamePublisher]::Publish($pending,$target)
 try{
  try{$null=[IO.File]::ReadAllText($target)}catch{if(($_.Exception.InnerException.HResult -band 0xffff) -eq 32){$oldRejected=$true}else{throw}}
  $value=[SyntheticRenamePublisher]::Read([Schema6OwnedJob],$target)
  if($kind -eq 'valid'){$validAccepted=$value -ceq $valid}else{$forgedRejected=$value -cne $valid}
  $reader=[IO.File]::Open($target,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::Read -bor [IO.FileShare]::Delete))
  try{$concurrentRead=[SyntheticRenamePublisher]::Read([Schema6OwnedJob],$target) -ceq $value}finally{$reader.Dispose()}
 }finally{[SyntheticRenamePublisher]::CloseHandle($publisher)|Out-Null}
}
@{old_reader_sharing_violation=$oldRejected;authenticated_bytes_accepted=$validAccepted;forged_bytes_rejected=$forgedRejected;concurrent_read_compatible=$concurrentRead}|ConvertTo-Json -Compress
