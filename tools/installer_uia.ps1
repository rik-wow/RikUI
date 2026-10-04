param([long]$WindowHandle)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
# Query the native COM client, independently of optional .NET proxy assemblies.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
[ComImport, Guid("FF48DBA4-60EF-4201-AA87-54103EEF594E")]
public class NativeAutomation {}
[ComImport, Guid("30CBE57D-D9D0-452A-AB13-7AC5AC4825EE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface AutomationClient {
 [PreserveSig] int CompareElements();
 [PreserveSig] int CompareRuntimeIds();
 [PreserveSig] int GetRootElement();
 void ElementFromHandle(IntPtr window, out AutomationElement element);
}
[ComImport, Guid("D22108AA-8AC5-49A5-837B-37BBB3D7591E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface AutomationElement {
 [PreserveSig] int SetFocus();
 [PreserveSig] int GetRuntimeId();
 [PreserveSig] int FindFirst();
 [PreserveSig] int FindAll();
 [PreserveSig] int FindFirstBuildCache();
 [PreserveSig] int FindAllBuildCache();
 [PreserveSig] int BuildUpdatedCache();
 void GetCurrentPropertyValue(int property, [MarshalAs(UnmanagedType.Struct)] out object value);
}
public static class NativeControls {
 [DllImport("user32.dll")] static extern IntPtr GetDlgItem(IntPtr parent, int id);
 public static object Property(AutomationElement element,int id) {
  object value; element.GetCurrentPropertyValue(id,out value); return value;
 }
 public static object[] Read(long window) {
  var client=(AutomationClient)new NativeAutomation();
  var rows=new List<object>();
  foreach(int id in new int[]{101,102,103,104,105,106,109,113,114}) {
   AutomationElement element;client.ElementFromHandle(GetDlgItem(new IntPtr(window),id),out element);
   rows.Add(new {id=id,name=Property(element,30005),role=Property(element,30003),
     enabled=Property(element,30010),focusable=Property(element,30009)});
   Marshal.ReleaseComObject(element);
  }
  Marshal.ReleaseComObject(client);return rows.ToArray();
 }
}
'@
ConvertTo-Json -InputObject @([NativeControls]::Read($WindowHandle)) -Compress
