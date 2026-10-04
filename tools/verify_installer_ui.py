"""Capture and check the actual native installer controls with read-only state fixtures."""
import argparse
import ctypes as c
from ctypes import wintypes as w
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import time
import zlib

u=c.WinDLL("user32",use_last_error=True)
g=c.WinDLL("gdi32",use_last_error=True)
u.SetProcessDpiAwarenessContext.argtypes=[c.c_void_p]
u.SetProcessDpiAwarenessContext.restype=w.BOOL
u.SetProcessDpiAwarenessContext(c.c_void_p(-4))
for name,args,result in (
 ("GetDlgItem",[w.HWND,c.c_int],w.HWND),("GetDC",[w.HWND],w.HDC),
 ("GetNextDlgTabItem",[w.HWND,w.HWND,w.BOOL],w.HWND),
 ("GetWindowLongPtrW",[w.HWND,c.c_int],c.c_ssize_t),
 ("GetWindowThreadProcessId",[w.HWND,c.POINTER(w.DWORD)],w.DWORD),
 ("GetWindowTextW",[w.HWND,w.LPWSTR,c.c_int],c.c_int),
 ("GetClassNameW",[w.HWND,w.LPWSTR,c.c_int],c.c_int),
 ("IsWindowEnabled",[w.HWND],w.BOOL),("GetWindowRect",[w.HWND,c.POINTER(w.RECT)],w.BOOL),
 ("GetClientRect",[w.HWND,c.POINTER(w.RECT)],w.BOOL),
 ("MapWindowPoints",[w.HWND,w.HWND,c.POINTER(w.POINT),c.c_uint],c.c_int),
 ("SendMessageW",[w.HWND,w.UINT,w.WPARAM,w.LPARAM],w.LPARAM),
 ("PostMessageW",[w.HWND,w.UINT,w.WPARAM,w.LPARAM],w.BOOL),
 ("PrintWindow",[w.HWND,w.HDC,w.UINT],w.BOOL),("ReleaseDC",[w.HWND,w.HDC],c.c_int),
):
 fn=getattr(u,name);fn.argtypes=args;fn.restype=result
for name,args,result in (
 ("CreateCompatibleDC",[w.HDC],w.HDC),("CreateCompatibleBitmap",[w.HDC,c.c_int,c.c_int],w.HBITMAP),
 ("SelectObject",[w.HDC,w.HGDIOBJ],w.HGDIOBJ),("DeleteObject",[w.HGDIOBJ],w.BOOL),
 ("DeleteDC",[w.HDC],w.BOOL),
 ("GetDIBits",[w.HDC,w.HBITMAP,w.UINT,w.UINT,c.c_void_p,c.c_void_p,w.UINT],c.c_int),
):
 fn=getattr(g,name);fn.argtypes=args;fn.restype=result
CALLBACK=c.WINFUNCTYPE(w.BOOL,w.HWND,w.LPARAM)
u.EnumWindows.argtypes=[CALLBACK,w.LPARAM]
def find(pid):
 found=[]
 @CALLBACK
 def visit(hwnd,_):
  other=w.DWORD();u.GetWindowThreadProcessId(hwnd,c.byref(other))
  name=c.create_unicode_buffer(128);u.GetClassNameW(hwnd,name,128)
  if other.value==pid and name.value=="RikUIInstallerWindow":found.append(hwnd)
  return True
 u.EnumWindows(visit,0)
 return found[0] if found else None

def text(hwnd):
 value=c.create_unicode_buffer(32768);u.GetWindowTextW(hwnd,value,len(value))
 return value.value

def png(hwnd,path):
 rect=w.RECT();assert u.GetWindowRect(hwnd,c.byref(rect))
 width,height=rect.right-rect.left,rect.bottom-rect.top
 dc=u.GetDC(hwnd);memory=g.CreateCompatibleDC(dc);bitmap=g.CreateCompatibleBitmap(dc,width,height)
 old=g.SelectObject(memory,bitmap)
 try:
  assert dc and memory and bitmap,"Native capture GDI allocation failed"
  assert u.PrintWindow(hwnd,memory,2),"Native window capture failed"
  g.SelectObject(memory,old)
  header=struct.pack("<IiiHHIIiiII",40,width,-height,1,32,0,width*height*4,0,0,0,0)
  info=c.create_string_buffer(header+b"\0"*16)
  raw=c.create_string_buffer(width*height*4)
  assert g.GetDIBits(memory,bitmap,0,height,raw,info,0)==height
  pixels=raw.raw
  assert len(set(pixels))>8,"Native capture is blank; no visual evidence accepted"
  rows=bytearray()
  for y in range(height):
   rows.append(0)
   for x in range(width):
    at=(y*width+x)*4;b,green,r,_=pixels[at:at+4]
    rows.extend((r,green,b,255))
  def chunk(tag,data):
   return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data)&0xffffffff)
  image=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",width,height,8,6,0,0,0))+chunk(b"IDAT",zlib.compress(rows,9))+chunk(b"IEND",b"")
  path.write_bytes(image)
  return dict(width=width,height=height,sha256=hashlib.sha256(image).hexdigest())
 finally:
  g.SelectObject(memory,old);g.DeleteObject(bitmap);g.DeleteDC(memory);u.ReleaseDC(hwnd,dc)

def check(hwnd):
 client=w.RECT();u.GetClientRect(hwnd,c.byref(client))
 rows=[]
 for ident in [101,102,103,104,105,106,107,108,109,110,111,112,113,114,120,121,122,123,124,125]:
  control=u.GetDlgItem(hwnd,ident);assert control,f"Missing control {ident}"
  rect=w.RECT();u.GetWindowRect(control,c.byref(rect))
  point=w.POINT(rect.left,rect.top);u.MapWindowPoints(None,hwnd,c.byref(point),1)
  assert point.x>=0 and point.y>=0 and point.x+rect.right-rect.left<=client.right and point.y+rect.bottom-rect.top<=client.bottom,f"Clipped control {ident}"
  label=text(control)
  if ident not in (101,110,112):assert label.strip(),f"Missing accessible name {ident}"
  rows.append(dict(id=ident,name=label,enabled=bool(u.IsWindowEnabled(control)),
                   tabStop=bool(u.GetWindowLongPtrW(control,-16)&0x10000)))
 first=u.GetNextDlgTabItem(hwnd,None,False);assert first,"No keyboard entry"
 tab=[];at=first
 for _ in range(32):
  tab.append(next(row["id"] for row in rows if u.GetDlgItem(hwnd,row["id"])==at))
  at=u.GetNextDlgTabItem(hwnd,at,False)
  if at==first:break
 assert len(tab)==len(set(tab)) and 106 in tab and 113 in tab,"Keyboard cycle incomplete"
 assert all(row["id"] in tab for row in rows if row["tabStop"] and row["enabled"]),"Enabled action missing from keyboard cycle"
 return dict(controls=rows,tabOrder=tab)

def accessibility(hwnd):
 system=Path(os.environ["SystemRoot"])/"System32/WindowsPowerShell/v1.0/powershell.exe"
 result=subprocess.run([str(system),"-NoProfile","-NonInteractive","-File",
   str(Path(__file__).resolve().with_name("installer_uia.ps1")),str(hwnd)],
   stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding="utf-8",timeout=30,
   creationflags=subprocess.CREATE_NO_WINDOW)
 if result.returncode:raise ValueError("Native automation client error: "+result.stderr)
 rows=json.loads(result.stdout)
 buttons=[row for row in rows if row["role"]==50000]
 assert len(buttons)==8 and all(row["name"].strip() for row in buttons),"Accessible button names missing: "+json.dumps(rows)
 edits=[row for row in rows if row["role"]==50004]
 assert edits and all(row["name"].strip() for row in edits),"Game folder needs an accessible label"
 assert all(row["focusable"] for row in buttons if row["enabled"]),"Enabled button is not keyboard accessible"
 return rows

STATES={
 "selection":dict(phase="Your game is ready",message="Choose Prepare and install. Setup gets quest information and prepares supported routes.",verified=True),
 "mismatch":dict(summary="Installed Forever version needs updating",phase="Update Forever first",message="Your installed game does not match the latest Forever build. Update it in Battle.net, then Check again.",verified=False),
 "download":dict(phase="Getting quest information",message="Downloading QuestieDB from its publisher. Existing installed files remain available.",busy=True,completed=12,total=40,units="MiB",seconds=21),
 "generation":dict(phase="Preparing routes",message="Building current routes on your computer. Completed work is retained if you pause.",busy=True,completed=403,total=2290,seconds=535,build="current fixture"),
 "paused":dict(phase="Preparation paused",message="Completed work and your existing installation are retained. Choose Resume setup to continue.",action="&Resume setup",verified=True,state="cancelled"),
 "disk-failure":dict(phase="More disk space needed",message="First preparation needs 16 GiB; 7 GiB is free on C:. Choose Preparation folder on another drive, or free space and retry.",verified=True,state="failed"),
 "provider-failure":dict(phase="Quest information unavailable",message="QuestieDB could not be obtained from its publisher. Check your connection, then Resume setup.",action="&Resume setup",verified=True,state="failed"),
 "partial":dict(phase="Guide partially prepared",message="Supported regions are still being generated. This is incomplete. Resume setup to finish before installation.",action="&Resume setup",verified=True,state="cancelled"),
 "verification-failure":dict(phase="Files need rebuilding",message="Generated files failed verification. Existing installed files are retained. Resume setup to rebuild safely.",action="&Resume setup",verified=True,state="failed"),
 "file-verification":dict(phase="Checking your game",message="Checking prepared region files.",busy=True,completed=14367,total=16030,units="files",seconds=4021,build="current fixture"),
 "committing":dict(phase="Finishing installation",message="Installing verified files and retaining your backup. Please wait for this transaction to finish safely.",busy=True,state="committing"),
 "ready":dict(phase="Ready to play",message="Quest guide and supported routes installed and verified. Daily checks are active. Unknown coverage stays explicit.",verified=True,state="installed"),
 "rollback":dict(phase="Backup restored",message="Previous files were restored. Replaced files are retained in a backup. Check current compatibility before using guidance.",verified=True),
}
def verify_progress(hwnd, folder, name):
 # Exercise the actual WM_TIMER/status/control path; fixtures never acquire or install data.
 home=folder/"RikUI"
 trace=home/"progress-trace.txt"
 def commands():
  return [line for line in trace.read_text(encoding="utf-8").splitlines() if line!="Poll"] if trace.exists() else []
 def poll():
  for _ in range(10):u.SendMessageW(hwnd,0x0113,1,0)
 def update(value):
  temporary=home/"status-next.json";temporary.write_text(json.dumps(value),encoding="utf-8")
  os.replace(temporary,home/"status.json");poll()
 before=commands();poll()
 assert commands()==before,"Identical polls reconfigured the native progress bar: "+name
 lines=trace.read_text(encoding="utf-8").splitlines()
 assert lines.count("Poll")>=10,"Fixture did not exercise repeated timer refreshes"
 evidence=dict(repeatedPolls=lines.count("Poll"),initialCommands=before)
 if name=="generation":
  assert before==["Range(2290)","Position(403)"],before
  bar=u.GetDlgItem(hwnd,110)
  assert u.SendMessageW(bar,0x0408,0,0)==403
  update(dict(phase="Preparing routes",busy=True,completed=404,total=2290))
  assert commands()==before+["Position(404)"],commands()
  assert u.SendMessageW(bar,0x0408,0,0)==404
  update(dict(phase="Preparing roads",busy=True,completed=1,total=7))
  assert commands()[-2:]==["Range(7)","Position(1)"]
  assert u.SendMessageW(bar,0x0407,0,0)==7 and u.SendMessageW(bar,0x0408,0,0)==1
  update(dict(phase="Checking files",busy=True))
  assert commands()[-1:]==["StartMarquee"]
  assert u.GetWindowLongPtrW(bar,-16)&8,"Unknown work did not start native marquee"
  unchanged=commands();poll();assert commands()==unchanged,"Marquee restarted on identical polls"
  update(dict(phase="Ready to play",state="installed",completed=0,total=0))
  assert commands()[-3:]==["StopMarquee","Range(100)","Position(100)"]
  assert not u.GetWindowLongPtrW(bar,-16)&8
  assert u.SendMessageW(bar,0x0408,0,0)==100
  evidence["transitions"]=commands()
 elif name=="committing":
  assert before==["StartMarquee"],before
 evidence["finalCommands"]=commands()
 return evidence

def verify_idle_start(executable, root):
 # Normal production launch, without --ui-fixture: stale status must not resume work.
 results={}
 for name,state in (("startup-new",None),("startup-paused","cancelled"),("startup-installed","installed")):
  folder=root/name;folder.mkdir()
  home=folder/"RikUI";home.mkdir()
  game=folder/"game";game.mkdir()
  (home/"configuration.json").write_text(json.dumps(dict(storage_root=str(game),executable=str(game/"WowB.exe"))),encoding="utf-8")
  if state:
   (home/"status.json").write_text(json.dumps(dict(state=state,phase="Old preparation",completed=5,total=10)),encoding="utf-8")
   cache=home/"cache";cache.mkdir();(cache/"retained-input").write_bytes(b"Retain these bytes")
   if state=="cancelled":(cache/"cancel").write_bytes(b"Paused")
  def snapshot():
   return {str(path.relative_to(home)):hashlib.sha256(path.read_bytes()).hexdigest() for path in home.rglob("*") if path.is_file()}
  before=snapshot()
  for opening in range(2):
   startup=subprocess.STARTUPINFO();startup.dwFlags=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=4
   process=subprocess.Popen([executable],env=dict(os.environ,LOCALAPPDATA=str(folder)),startupinfo=startup)
   hwnd=None
   try:
    for _ in range(100):
     hwnd=find(process.pid)
     if hwnd:break
     assert process.poll() is None,"Normal installer exited"
     time.sleep(.05)
    assert hwnd,"Normal installer window unavailable"
    time.sleep(.4)
    for _ in range(30):u.SendMessageW(hwnd,0x0113,1,0)
    assert text(u.GetDlgItem(hwnd,111))=="Ready to start","Opening setup started work"
    assert u.IsWindowEnabled(u.GetDlgItem(hwnd,103)),"Primary start action unavailable"
    assert not u.IsWindowEnabled(u.GetDlgItem(hwnd,109)),"Idle setup offers Pause"
    bar=u.GetDlgItem(hwnd,110)
    assert not u.GetWindowLongPtrW(bar,-16)&8,"Idle progress bar animates"
    assert u.SendMessageW(bar,0x0408,0,0)==0,"Stale progress is shown on startup"
    assert snapshot()==before,"Opening setup changed retained files or started a worker"
    if opening==0:
     results[name]=dict(**check(hwnd),accessibility=accessibility(hwnd),image=png(hwnd,folder/"window.png"),normalLaunch=True,reopenVerified=True)
    # Editing a folder must stay idle; explicit actions reject bad input without work.
    invalid=str(folder/"missing-game")
    buffer=c.create_unicode_buffer(invalid)
    u.SendMessageW(u.GetDlgItem(hwnd,101),0x000c,0,c.cast(buffer,c.c_void_p).value)
    for _ in range(10):u.SendMessageW(hwnd,0x0113,1,0)
    assert text(u.GetDlgItem(hwnd,111))=="Ready to start" and snapshot()==before
    for action in (103,105):
     u.SendMessageW(hwnd,0x0111,action,u.GetDlgItem(hwnd,action))
     assert text(u.GetDlgItem(hwnd,111))=="Find your Forever game","Explicit action did not run its input check"
     assert snapshot()==before,"Invalid input changed files"
   finally:
    if hwnd:u.PostMessageW(hwnd,0x0010,0,0)
    try:process.wait(timeout=10)
    except subprocess.TimeoutExpired:process.kill();process.wait();raise
 return results

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--exe",required=True);parser.add_argument("--output",required=True)
 args=parser.parse_args();root=Path(args.output).absolute()
 root.mkdir(parents=True,exist_ok=False)
 results=verify_idle_start(args.exe,root)
 for name,state in STATES.items():
  folder=root/name;folder.mkdir();fixture=folder/"state.json";fixture.write_text(json.dumps(state),encoding="utf-8")
  env=dict(os.environ,LOCALAPPDATA=str(folder))
  startup=subprocess.STARTUPINFO();startup.dwFlags=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=4  # Show the actual interface without taking keyboard focus.
  process=subprocess.Popen([args.exe,"--ui-fixture",str(fixture)],env=env,startupinfo=startup)
  try:
   hwnd=None
   for _ in range(100):
    hwnd=find(process.pid)
    if hwnd:break
    if process.poll() is not None:raise ValueError("Installer fixture exited")
    time.sleep(.05)
   assert hwnd,"Installer window unavailable";time.sleep(.4)
   results[name]=dict(**check(hwnd),accessibility=accessibility(hwnd),image=png(hwnd,folder/"window.png"),
                      progress=verify_progress(hwnd,folder,name))
  finally:
   if hwnd:u.PostMessageW(hwnd,0x0010,0,0)
   try:process.wait(timeout=10)
   except subprocess.TimeoutExpired:process.kill();process.wait();raise
 (root/"evidence.json").write_text(json.dumps(results,indent=2)+"\n",encoding="utf-8")
 print(json.dumps(dict(states=len(results),output=str(root),executableSHA256=hashlib.sha256(Path(args.exe).read_bytes()).hexdigest())))
if __name__=="__main__":main()
