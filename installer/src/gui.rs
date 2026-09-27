// Win32 handles belong to the UI thread. Workers return owned results through a channel.
#![allow(unsafe_op_in_unsafe_fn)]
use rikui_installer::{EMBEDDED, bundle::Bundle, transaction::Installer};
use std::{
    ffi::c_void,
    mem::{size_of, zeroed},
    path::PathBuf,
    ptr::{null, null_mut},
    sync::mpsc,
};
use windows_sys::Win32::UI::Input::KeyboardAndMouse::EnableWindow;
use windows_sys::Win32::{
    Foundation::*,
    Graphics::Gdi::*,
    System::{Diagnostics::ToolHelp::*, LibraryLoader::GetModuleHandleW},
    UI::{Controls::Dialogs::*, Shell::ShellExecuteW, WindowsAndMessaging::*},
};

mod layout;
use layout::{controls, pick, summary};

const PATH: i32 = 101;
const BROWSE: i32 = 102;
const INSTALL: i32 = 103;
const ROLLBACK: i32 = 104;
const PACKAGE: i32 = 105;
const RELEASES: i32 = 106;
const STATUS: i32 = 107;
const SUMMARY: i32 = 108;
const DONE_TIMER: usize = 1;

struct App {
    package: Option<PathBuf>,
    result: Option<mpsc::Receiver<Result<String, String>>>,
    smoke: bool,
}
fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(Some(0)).collect()
}

unsafe fn label(hwnd: HWND, id: i32, text: &str) {
    SetWindowTextW(GetDlgItem(hwnd, id), wide(text).as_ptr());
}
unsafe fn error(hwnd: HWND, text: &str) {
    MessageBoxW(
        hwnd,
        wide(text).as_ptr(),
        wide("RikUI installer").as_ptr(),
        MB_OK | MB_ICONERROR,
    );
}
unsafe fn child(hwnd: HWND, kind: &str, text: &str, id: i32, rect: [i32; 4], style: u32) -> HWND {
    let handle = CreateWindowExW(
        0,
        wide(kind).as_ptr(),
        wide(text).as_ptr(),
        WS_CHILD | WS_VISIBLE | style,
        rect[0],
        rect[1],
        rect[2],
        rect[3],
        hwnd,
        id as usize as HMENU,
        GetModuleHandleW(null()),
        null(),
    );
    SendMessageW(
        handle,
        WM_SETFONT,
        GetStockObject(DEFAULT_GUI_FONT) as usize,
        1,
    );
    handle
}
fn game_running() -> Result<bool, String> {
    unsafe {
        let snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if snapshot == INVALID_HANDLE_VALUE {
            return Err("Could not check running processes".into());
        }
        let mut entry: PROCESSENTRY32W = zeroed();
        entry.dwSize = size_of::<PROCESSENTRY32W>() as u32;
        let mut success = Process32FirstW(snapshot, &mut entry);
        let mut running = false;
        while success != 0 {
            let end = entry
                .szExeFile
                .iter()
                .position(|c| *c == 0)
                .unwrap_or(entry.szExeFile.len());
            if String::from_utf16_lossy(&entry.szExeFile[..end]).eq_ignore_ascii_case("WowB.exe") {
                running = true;
                break;
            }
            success = Process32NextW(snapshot, &mut entry);
        }
        CloseHandle(snapshot);
        Ok(running)
    }
}
unsafe fn busy(hwnd: HWND, enabled: bool) {
    for id in [PATH, BROWSE, INSTALL, ROLLBACK, PACKAGE, RELEASES] {
        EnableWindow(GetDlgItem(hwnd, id), (!enabled) as i32);
    }
}
unsafe fn start(hwnd: HWND, app: *mut App, rollback: bool) {
    if (*app).result.is_some() {
        return;
    }
    match game_running() {
        Ok(false) => {}
        Ok(true) => {
            error(
                hwnd,
                "Close World of Warcraft before installing or rolling back.",
            );
            return;
        }
        Err(e) => {
            error(hwnd, &e);
            return;
        }
    }
    let control = GetDlgItem(hwnd, PATH);
    let mut buffer = vec![0u16; GetWindowTextLengthW(control) as usize + 1];
    let count = GetWindowTextW(control, buffer.as_mut_ptr(), buffer.len() as i32);
    use std::os::windows::ffi::OsStringExt;
    let game = PathBuf::from(std::ffi::OsString::from_wide(&buffer[..count as usize]));
    if let Err(e) = rikui_installer::transaction::game_root(&game) {
        error(hwnd, &e.to_string());
        return;
    }
    if rollback
        && MessageBoxW(
            hwnd,
            wide("Restore the previous RikUI files? The current files will also be backed up.")
                .as_ptr(),
            wide("Roll back RikUI").as_ptr(),
            MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2,
        ) != IDYES
    {
        return;
    }
    let package = (*app).package.clone();
    let (sender, receiver) = mpsc::channel();
    (*app).result = Some(receiver);
    busy(hwnd, true);
    label(
        hwnd,
        STATUS,
        "Verifying files and preparing a backup. Please keep this window open.",
    );
    std::thread::spawn(move || {
        let operation = || -> rikui_installer::Result<String> {
            let bundle = if !rollback {
                let bytes = if let Some(path) = package {
                    std::fs::read(path)?
                } else {
                    EMBEDDED.to_vec()
                };
                Some(Bundle::read(&bytes)?)
            } else {
                None
            };
            let installer = Installer::open(&game)?;
            let backup = if let Some(bundle) = bundle {
                installer.install(&bundle)?
            } else {
                installer.rollback()?
            };
            Ok(format!(
                "Done. Start WoW again to load RikUI.\r\nBackup: {}",
                backup.display()
            ))
        };
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(operation))
            .map_err(|_| {
                "Installer worker stopped unexpectedly. Reopen to recover; backups are retained."
                    .to_string()
            })
            .and_then(|r| r.map_err(|e| e.to_string()));
        let _ = sender.send(result);
    });
}
unsafe extern "system" fn procedure(
    hwnd: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    if message == WM_NCCREATE {
        let create = &*(lparam as *const CREATESTRUCTW);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, create.lpCreateParams as isize);
    }
    let state = GetWindowLongPtrW(hwnd, GWLP_USERDATA) as *mut App;
    if state.is_null() {
        return DefWindowProcW(hwnd, message, wparam, lparam);
    }
    let app = state;
    match message {
        WM_CREATE => {
            controls(hwnd);
            summary(hwnd, EMBEDDED);
            SetTimer(hwnd, DONE_TIMER, 200, None);
            0
        }
        WM_COMMAND => {
            match (wparam & 0xffff) as i32 {
                BROWSE => {
                    if let Some(path) = pick(hwnd, false)
                        && let Some(parent) = path.parent()
                    {
                        label(hwnd, PATH, &parent.to_string_lossy());
                    }
                }
                PACKAGE => {
                    if let Some(path) = pick(hwnd, true) {
                        match std::fs::read(&path)
                            .map_err(|e| e.to_string())
                            .and_then(|b| Bundle::read(&b).map(|_| b).map_err(|e| e.to_string()))
                        {
                            Ok(bytes) => {
                                summary(hwnd, &bytes);
                                (*app).package = Some(path);
                            }
                            Err(e) => error(hwnd, &e),
                        }
                    }
                }
                INSTALL => start(hwnd, app, false),
                ROLLBACK => start(hwnd, app, true),
                RELEASES => {
                    ShellExecuteW(
                        hwnd,
                        wide("open").as_ptr(),
                        wide("https://github.com/rik-wow/RikUI/releases").as_ptr(),
                        null(),
                        null(),
                        SW_SHOWNORMAL,
                    );
                }
                _ => {}
            };
            0
        }
        WM_TIMER => {
            if (*app).smoke {
                for id in [
                    PATH, BROWSE, INSTALL, ROLLBACK, PACKAGE, RELEASES, STATUS, SUMMARY,
                ] {
                    assert!(!GetDlgItem(hwnd, id).is_null(), "Missing native control");
                }
                assert!(
                    Bundle::read(EMBEDDED).is_ok(),
                    "Missing or invalid embedded release package"
                );
                DestroyWindow(hwnd);
                return 0;
            }
            if let Some(receiver) = &(*app).result
                && let Ok(result) = receiver.try_recv()
            {
                (*app).result = None;
                busy(hwnd, false);
                match result {
                    Ok(text) => label(hwnd, STATUS, &text),
                    Err(text) => {
                        label(
                            hwnd,
                            STATUS,
                            "Installation did not complete. Existing backups are retained.",
                        );
                        error(hwnd, &text);
                    }
                }
            }
            0
        }
        WM_CLOSE => {
            if (*app).result.is_none() {
                DestroyWindow(hwnd);
            } else {
                label(
                    hwnd,
                    STATUS,
                    "Please wait for the current operation to finish.",
                );
            }
            0
        }
        WM_DESTROY => {
            KillTimer(hwnd, DONE_TIMER);
            PostQuitMessage(0);
            0
        }
        _ => DefWindowProcW(hwnd, message, wparam, lparam),
    }
}
pub fn run() {
    unsafe {
        let mut app = Box::new(App {
            package: None,
            result: None,
            smoke: std::env::args().any(|arg| arg == "--smoke-test"),
        });
        let class = wide("RikUIInstallerWindow");
        let instance = GetModuleHandleW(null());
        let mut window: WNDCLASSW = zeroed();
        window.lpfnWndProc = Some(procedure);
        window.hInstance = instance;
        window.lpszClassName = class.as_ptr();
        window.hCursor = LoadCursorW(null_mut(), IDC_ARROW);
        window.hbrBackground = (COLOR_WINDOW + 1) as HBRUSH;
        if RegisterClassW(&window) == 0 {
            error(null_mut(), "Could not register installer window");
            return;
        }
        let hwnd = CreateWindowExW(
            WS_EX_CONTROLPARENT,
            class.as_ptr(),
            wide("RikUI installer").as_ptr(),
            WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            630,
            520,
            null_mut(),
            null_mut(),
            instance,
            app.as_mut() as *mut App as *const c_void,
        );
        if hwnd.is_null() {
            error(null_mut(), "Could not create installer window");
            return;
        }
        ShowWindow(hwnd, SW_SHOW);
        let mut message: MSG = zeroed();
        while GetMessageW(&mut message, null_mut(), 0, 0) > 0 {
            if IsDialogMessageW(hwnd, &message) == 0 {
                TranslateMessage(&message);
                DispatchMessageW(&message);
            }
        }
    }
}
