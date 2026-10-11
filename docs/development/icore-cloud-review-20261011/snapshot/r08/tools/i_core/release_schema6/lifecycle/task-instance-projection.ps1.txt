#requires -Version 5.1
# Read-only COM projection. This module contains no task mutation, Run or process control.
function Initialize-TaskInstanceProjection {
 if('HereIAmTaskInstanceProjection' -as [type]){return}
 Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Reflection;
using System.Runtime.InteropServices;
public sealed class HereIAmRunningTaskDto {
 public string Path; public string InstanceGuid; public int State; public int EnginePid;
}
public sealed class HereIAmTaskCollectionDto {
 public int NativeCount; public int ExplicitItemsRead; public string RuntimeType; public bool IsComObject;
 public List<HereIAmRunningTaskDto> MatchingItems=new List<HereIAmRunningTaskDto>();
}
public sealed class HereIAmTaskObservationDto {
 public string ObservedAt; public string TargetPath; public bool Enabled; public int RegisteredState;
 public HereIAmTaskCollectionDto RegisteredInstances; public HereIAmTaskCollectionDto ServiceRunningIncludingHidden;
 public bool ObservationCompleted; public string ErrorStage; public string ErrorHresult;
}
public static class HereIAmTaskInstanceProjection {
 static object Invoke(object o,string n,BindingFlags flags,params object[] args) {
  return o.GetType().InvokeMember(n,flags|BindingFlags.OptionalParamBinding,null,o,args,CultureInfo.InvariantCulture);
 }
 static object Get(object o,string n,params object[] args){return Invoke(o,n,BindingFlags.GetProperty,args);}
 static object Call(object o,string n,params object[] args){return Invoke(o,n,BindingFlags.InvokeMethod,args);}
 static object Service() {
  object s=Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service"));
  Call(s,"Connect",Type.Missing,Type.Missing,Type.Missing,Type.Missing);return s;
 }
 public static HereIAmRunningTaskDto ProjectReturnedInstance(object r) {
  Call(r,"Refresh");
  return new HereIAmRunningTaskDto{Path=Convert.ToString(Get(r,"Path")),InstanceGuid=Convert.ToString(Get(r,"InstanceGuid")),
   State=Convert.ToInt32(Get(r,"State")),EnginePid=Convert.ToInt32(Get(r,"EnginePID"))};
 }
 static HereIAmTaskCollectionDto ProjectCollection(object c,string target) {
  var result=new HereIAmTaskCollectionDto{NativeCount=Convert.ToInt32(Get(c,"Count")),
   RuntimeType=c.GetType().FullName,IsComObject=Marshal.IsComObject(c)};
  if(result.NativeCount<0||result.NativeCount>4096)throw new InvalidOperationException("collection_count_invalid");
  for(int i=1;i<=result.NativeCount;i++){
   object r=Get(c,"Item",i);result.ExplicitItemsRead++;
   // Other task paths are used only for exact target filtering and are not returned.
   if(String.Equals(Convert.ToString(Get(r,"Path")),target,StringComparison.OrdinalIgnoreCase))
    result.MatchingItems.Add(ProjectReturnedInstance(r));
  }
  return result;
 }
 public static HereIAmTaskObservationDto Observe(string taskName) {
  var r=new HereIAmTaskObservationDto{ObservedAt=DateTime.UtcNow.ToString("o"),TargetPath="\\"+taskName};
  try {
   r.ErrorStage="registered_task";
   object s=Service(),folder=Call(s,"GetFolder","\\"),task=Call(folder,"GetTask",taskName);
   r.Enabled=Convert.ToBoolean(Get(task,"Enabled"));r.RegisteredState=Convert.ToInt32(Get(task,"State"));
   r.ErrorStage="registered_instances";
   r.RegisteredInstances=ProjectCollection(Call(task,"GetInstances",0),r.TargetPath);
   r.ErrorStage="service_running_including_hidden";
   object separate=Service();r.ServiceRunningIncludingHidden=ProjectCollection(Call(separate,"GetRunningTasks",1),r.TargetPath);
   r.ObservationCompleted=true;r.ErrorStage=null;
  } catch(Exception e) {
   Exception inner=e is TargetInvocationException&&e.InnerException!=null?e.InnerException:e;
   r.ErrorHresult="0x"+inner.HResult.ToString("x8");
  }
  return r;
 }
}
"@
}
function Get-TaskInstanceProjection([Parameter(Mandatory=$true)][string]$TaskName) {
 Initialize-TaskInstanceProjection
 return [HereIAmTaskInstanceProjection]::Observe($TaskName)
}
