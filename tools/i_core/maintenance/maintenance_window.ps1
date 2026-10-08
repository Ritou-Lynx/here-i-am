. (Join-Path $PSScriptRoot 'owned_artifacts.ps1')
# Import-safe, filesystem-only window primitives. No tasks, processes or callbacks.
function Assert-MaintenancePlainDirectory([string]$Path) {
 if($Path -notmatch '^[A-Za-z]:\\' -or $Path.Substring(2).Contains(':') -or [IO.Path]::GetFullPath($Path) -cne $Path){throw 'window_path_not_canonical'}
 for($p=$Path;$p;$p=[IO.Path]::GetDirectoryName($p)){
  $item=Get-Item -LiteralPath $p -Force -ErrorAction Stop
  if(-not $item.PSIsContainer -or ($item.Attributes-band [IO.FileAttributes]::ReparsePoint)){throw 'window_path_not_plain'}
 }
}
function Acquire-MaintenanceGuard([string]$MaintenanceRoot) {
 Assert-MaintenancePlainDirectory $MaintenanceRoot
 $guardPath=Join-Path $MaintenanceRoot 'active-window.guard'
 if(Test-Path -LiteralPath $guardPath){$g=Get-Item -LiteralPath $guardPath -Force;if($g.PSIsContainer-or ($g.Attributes-band [IO.FileAttributes]::ReparsePoint)){throw 'window_guard_not_plain'}}
 # Resolve link count from the actual exclusive handle, never pathname metadata.
 if(-not ('MaintenanceGuardIdentity' -as [type])){
 Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class MaintenanceGuardIdentity {
 [StructLayout(LayoutKind.Sequential)] struct Info {public uint attr,c1,c2,a1,a2,w1,w2,volume,sizeHigh,sizeLow,links,indexHigh,indexLow;}
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool GetFileInformationByHandle(SafeFileHandle h,out Info i);
 public static void Check(SafeFileHandle h){Info i;if(!GetFileInformationByHandle(h,out i)||i.links!=1||(i.attr&0x400)!=0||(i.attr&0x10)!=0)throw new IOException("guard_link_or_identity_rejected");}
}
"@
 }
 # Existing guards open without truncation or ACL changes; fresh guards are owner-fixed.
 $ownerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $handle=if(Test-Path -LiteralPath $guardPath){[IO.File]::Open($guardPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}else{New-OwnedArtifactFile $guardPath $ownerSid}
 try{Initialize-OwnedArtifactNative;[MaintenanceGuardIdentity]::Check($handle.SafeFileHandle);$null=[OwnedArtifactNative]::Check($handle.SafeFileHandle,$guardPath,$false);[OwnedArtifactNative]::Private($handle.SafeFileHandle,$ownerSid,$false);return $handle}catch{$handle.Dispose();throw}
}
function Open-MaintenanceWindow {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][string]$MaintenanceRoot,[Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{7,79}$')][string]$WindowId)
 Assert-MaintenancePlainDirectory $MaintenanceRoot
 $ownerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $guard=$null;$entry=$null
 try {
  $guard=Acquire-MaintenanceGuard $MaintenanceRoot
  $windows=Join-Path $MaintenanceRoot 'windows'
  if(-not (Test-Path -LiteralPath $windows)){New-OwnedArtifactDirectory $windows $ownerSid}
  Assert-MaintenancePlainDirectory $windows
  $directory=Join-Path $windows $WindowId
  if(Test-Path -LiteralPath $directory){throw 'window_id_already_used'}
  New-OwnedArtifactDirectory $directory $ownerSid;Assert-MaintenancePlainDirectory $directory
  $entryPath=Join-Path $directory 'entry.lock';$entry=New-OwnedArtifactFile $entryPath $ownerSid
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes($WindowId+"`n")
  $entry.Write($bytes,0,$bytes.Length);$entry.Flush($true);[OwnedArtifactNative]::Readback($entry,$entryPath,$ownerSid,$bytes)
  $receipts=Join-Path $directory 'phase-receipts';New-OwnedArtifactDirectory $receipts $ownerSid
  return [pscustomobject]@{WindowId=$WindowId;Directory=$directory;PhaseReceiptsDirectory=$receipts;Guard=$guard;Entry=$entry}
 } catch {if($entry){$entry.Dispose()};if($guard){$guard.Dispose()};throw}
}
function Close-MaintenanceWindow($Window) {
 if($Window){try {if($Window.Entry){$Window.Entry.Dispose()}}finally{if($Window.Guard){$Window.Guard.Dispose()}}}
 # Never delete or truncate either lock, even on a failed window.
}
