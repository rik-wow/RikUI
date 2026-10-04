// Win32 controls stay on the UI thread; workers return owned results.
#![allow(unsafe_op_in_unsafe_fn)]
use rikui_installer::{EMBEDDED, RUNTIME, bundle::Bundle, setup, transaction::Installer};
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
    System::LibraryLoader::GetModuleHandleW,
    UI::{
        Controls::{
            Dialogs::*, ICC_PROGRESS_CLASS, INITCOMMONCONTROLSEX, InitCommonControlsEx,
            PBM_SETMARQUEE, PBM_SETPOS, PBM_SETRANGE32, PBS_MARQUEE,
        },
        HiDpi::{
            DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2, GetDpiForSystem, GetDpiForWindow,
            SetProcessDpiAwarenessContext,
        },
        Shell::ShellExecuteW,
        WindowsAndMessaging::*,
    },
};
mod layout;
mod progress;
use layout::{arrange, controls, pick};
use progress::{Command, Display, Progress};
const PATH: i32 = 101;
const BROWSE: i32 = 102;
const INSTALL: i32 = 103;
const ROLLBACK: i32 = 104;
const CHECK: i32 = 105;
const RELEASES: i32 = 106;
const STATUS: i32 = 107;
const SUMMARY: i32 = 108;
const PAUSE: i32 = 109;
const PROGRESS: i32 = 110;
const PHASE: i32 = 111;
const METRICS: i32 = 112;
const DETAILS: i32 = 113;
const CACHE: i32 = 114;
const DONE_TIMER: usize = 1;
enum Operation {
    Probe,
    Install,
    Rollback,
}
enum Finished {
    Updated(PathBuf),
    Probe(serde_json::Value),
    Installed(String),
    RolledBack(String),
}
struct App {
    root: PathBuf,
    result: Option<mpsc::Receiver<Result<Finished, String>>>,
    smoke: bool,
    fixture: Option<serde_json::Value>,
    preparing: bool,
    close_when_done: bool,
    fonts: [HFONT; 3],
    progress: Progress,
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
        wide("RikUI setup").as_ptr(),
        MB_OK | MB_ICONERROR,
    );
}
unsafe fn font(hwnd: HWND, id: i32) -> HFONT {
    let app = GetWindowLongPtrW(hwnd, GWLP_USERDATA) as *mut App;
    if app.is_null() {
        return GetStockObject(DEFAULT_GUI_FONT) as HFONT;
    }
    (*app).fonts[if id == PHASE {
        1
    } else if id == 120 {
        2
    } else {
        0
    }]
}
unsafe fn child(hwnd: HWND, kind: &str, text: &str, id: i32, rect: [i32; 4], style: u32) -> HWND {
    let handle = CreateWindowExW(
        0,
        wide(kind).as_ptr(),
        wide(text).as_ptr(),
        WS_CHILD
            | WS_VISIBLE
            | style
            | if kind == "Static" && id != 123 {
                0x0080 // SS_NOPREFIX: literal status text; the folder label retains its mnemonic.
            } else {
                0
            },
        rect[0],
        rect[1],
        rect[2],
        rect[3],
        hwnd,
        id as usize as HMENU,
        GetModuleHandleW(null()),
        null(),
    );
    SendMessageW(handle, WM_SETFONT, font(hwnd, id) as usize, 1);
    handle
}
unsafe fn replace_fonts(hwnd: HWND, app: *mut App) {
    let dpi = if hwnd.is_null() {
        GetDpiForSystem()
    } else {
        GetDpiForWindow(hwnd)
    }
    .max(96) as i32;
    let mut fonts = [null_mut(); 3];
    for (index, (height, weight)) in [(16, FW_NORMAL), (22, FW_SEMIBOLD), (28, FW_SEMIBOLD)]
        .into_iter()
        .enumerate()
    {
        fonts[index] = CreateFontW(
            -height * dpi / 96,
            0,
            0,
            0,
            weight as i32,
            0,
            0,
            0,
            DEFAULT_CHARSET as u32,
            OUT_DEFAULT_PRECIS as u32,
            CLIP_DEFAULT_PRECIS as u32,
            CLEARTYPE_QUALITY as u32,
            DEFAULT_PITCH as u32,
            wide("Segoe UI").as_ptr(),
        );
    }
    let old = (*app).fonts;
    (*app).fonts = fonts;
    for id in layout::control_ids() {
        let handle = GetDlgItem(hwnd, id);
        if !handle.is_null() {
            SendMessageW(handle, WM_SETFONT, font(hwnd, id) as usize, 1);
        }
    }
    for handle in old {
        if !handle.is_null() {
            DeleteObject(handle as HGDIOBJ);
        }
    }
}
unsafe fn busy(hwnd: HWND, app: *mut App, enabled: bool, preparing: bool) {
    (*app).preparing = enabled && preparing;
    for id in [PATH, BROWSE, INSTALL, ROLLBACK, CHECK, CACHE] {
        EnableWindow(GetDlgItem(hwnd, id), (!enabled) as i32);
    }
    EnableWindow(GetDlgItem(hwnd, PAUSE), (enabled && preparing) as i32);
}
unsafe fn idle(hwnd: HWND) {
    label(hwnd, PHASE, "Ready to start");
    label(hwnd, SUMMARY, "Your game will be checked when you start.");
    label(hwnd, INSTALL, "&Prepare and install");
    label(
        hwnd,
        STATUS,
        "Choose Prepare and install when you're ready. Setup checks completed work before reusing it.",
    );
    label(hwnd, METRICS, "");
    show_progress(hwnd, Display::Idle);
}
unsafe fn selected(hwnd: HWND) -> PathBuf {
    let control = GetDlgItem(hwnd, PATH);
    let mut buffer = vec![0u16; GetWindowTextLengthW(control) as usize + 1];
    let count = GetWindowTextW(control, buffer.as_mut_ptr(), buffer.len() as i32);
    use std::os::windows::ffi::OsStringExt;
    PathBuf::from(std::ffi::OsString::from_wide(&buffer[..count as usize]))
}
unsafe fn start(hwnd: HWND, app: *mut App, operation: Operation) {
    if (*app).result.is_some() {
        return;
    }
    let storage = selected(hwnd);
    if !storage.is_absolute() || !storage.is_dir() {
        label(hwnd, PHASE, "Find your Forever game");
        label(
            hwnd,
            STATUS,
            "Choose the folder containing your current Forever client, then choose Prepare and install.",
        );
        return;
    }
    let root = (*app).root.clone();
    let (channel, receiver) = mpsc::channel();
    (*app).result = Some(receiver);
    let preparing = matches!(operation, Operation::Install);
    busy(hwnd, app, true, preparing);
    label(
        hwnd,
        PHASE,
        if preparing {
            "Preparing your guide"
        } else {
            "Checking your game"
        },
    );
    label(
        hwnd,
        STATUS,
        if preparing {
            "Quest information is obtained separately. Your current installation stays available until everything verifies."
        } else {
            "Checking the latest Forever build and supported data inputs."
        },
    );
    marquee(hwnd);
    std::thread::spawn(move || {
        let work = || -> rikui_installer::Result<Finished> {
            if !matches!(operation, Operation::Rollback)
                && let Some(program) = setup::update_program(&root)?
            {
                return Ok(Finished::Updated(program));
            }
            match operation {
                Operation::Probe => setup::inspect(&storage, &root).map(Finished::Probe),
                Operation::Install => {
                    setup::prepare_install(&storage, &root, true, true).map(Finished::Installed)
                }
                Operation::Rollback => {
                    let path = Installer::open(&storage)?.rollback()?;
                    Ok(Finished::RolledBack(format!(
                        "Previous files restored. The replaced files are kept in a backup.\n{}",
                        path.display()
                    )))
                }
            }
        };
        let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe(work))
    .map_err(|_|"Setup stopped unexpectedly. Reopen it to recover; your files and backups are retained.".to_string())
    .and_then(|value|value.map_err(|error|error.to_string()));
        let _ = channel.send(result);
    });
}
unsafe fn show_progress(hwnd: HWND, display: Display) {
    let app = GetWindowLongPtrW(hwnd, GWLP_USERDATA) as *mut App;
    let bar = GetDlgItem(hwnd, PROGRESS);
    for command in (*app).progress.update(display) {
        match command {
            Command::StopMarquee => {
                SendMessageW(bar, PBM_SETMARQUEE, 0, 0);
                let style = GetWindowLongPtrW(bar, GWL_STYLE);
                SetWindowLongPtrW(bar, GWL_STYLE, style & !(PBS_MARQUEE as isize));
            }
            Command::StartMarquee => {
                let style = GetWindowLongPtrW(bar, GWL_STYLE);
                SetWindowLongPtrW(bar, GWL_STYLE, style | PBS_MARQUEE as isize);
                SendMessageW(bar, PBM_SETMARQUEE, 1, 40);
            }
            Command::Range(total) => {
                SendMessageW(bar, PBM_SETRANGE32, 0, total as isize);
            }
            Command::Position(done) => {
                SendMessageW(bar, PBM_SETPOS, done as usize, 0);
            }
        }
        if (*app).fixture.is_some() {
            // Read-only interface fixtures record the actual commands sent to the native control.
            use std::io::Write;
            if let Ok(mut trace) = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open((*app).root.join("progress-trace.txt"))
            {
                let _ = writeln!(trace, "{command:?}");
            }
        }
    }
}
unsafe fn progress(hwnd: HWND, done: u64, total: u64) {
    show_progress(hwnd, Display::counted(done, total));
}
unsafe fn marquee(hwnd: HWND) {
    show_progress(hwnd, Display::Marquee);
}
unsafe fn refresh_status(hwnd: HWND, root: &std::path::Path) {
    if let Some(status) = setup::status(root) {
        EnableWindow(
            GetDlgItem(hwnd, PAUSE),
            ((*(GetWindowLongPtrW(hwnd, GWLP_USERDATA) as *mut App)).preparing
                && status["state"].as_str() != Some("committing")) as i32,
        );
        if let Some(phase) = status["phase"].as_str() {
            label(hwnd, PHASE, phase);
        }
        if let Some(message) = status["message"].as_str() {
            label(hwnd, STATUS, message);
        }
        let build = status["build"].as_str().unwrap_or("");
        let seconds = status["seconds"].as_f64();
        let completed = status["completed"].as_u64();
        let total = status["total"].as_u64();
        let elapsed = seconds.map(|seconds| {
            if seconds < 60. {
                format!("{seconds:.0} seconds elapsed")
            } else {
                format!("{:.0} minutes elapsed", seconds / 60.)
            }
        });
        let version = if build.is_empty() {
            String::new()
        } else {
            format!("  •  Forever {build}")
        };
        let metrics = match (completed, total, elapsed) {
            (Some(done), Some(total), Some(elapsed)) => format!(
                "{done} of {total} {} complete  •  {elapsed}{version}",
                status["units"].as_str().unwrap_or("jobs")
            ),
            (_, _, Some(elapsed)) => format!("{elapsed}{version}"),
            _ => String::new(),
        };
        label(hwnd, METRICS, &metrics);
        if status["state"].as_str() == Some("installed") {
            progress(hwnd, 100, 100);
        } else if let (Some(done), Some(total)) = (completed, total) {
            progress(hwnd, done, total);
        } else if (*(GetWindowLongPtrW(hwnd, GWLP_USERDATA) as *mut App)).preparing {
            marquee(hwnd);
        }
    }
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
    let app = GetWindowLongPtrW(hwnd, GWLP_USERDATA) as *mut App;
    if app.is_null() {
        return DefWindowProcW(hwnd, message, wparam, lparam);
    }
    match message {
        WM_CREATE => {
            controls(hwnd);
            arrange(hwnd);
            busy(hwnd, app, false, false);
            if let Ok(bundle) = Bundle::read(EMBEDDED) {
                label(
                    hwnd,
                    SUMMARY,
                    &format!(
                        "RikUI {}\nQuest guide and navigation are prepared on your computer.",
                        bundle.manifest.version
                    ),
                );
            }
            let storage = setup::saved_storage(&(*app).root).or_else(|| {
                std::env::var_os("ProgramFiles(x86)")
                    .map(|path| PathBuf::from(path).join("World of Warcraft"))
            });
            if let Some(storage) = storage {
                label(hwnd, PATH, &storage.to_string_lossy());
            }
            SetTimer(hwnd, DONE_TIMER, 200, None);
            if let Some(value) = &(*app).fixture {
                label(
                    hwnd,
                    PATH,
                    value["folder"]
                        .as_str()
                        .unwrap_or("C:\\Games\\World of Warcraft"),
                );
                label(
                    hwnd,
                    SUMMARY,
                    value["summary"]
                        .as_str()
                        .unwrap_or("Current Forever client verified"),
                );
                label(
                    hwnd,
                    INSTALL,
                    value["action"].as_str().unwrap_or("Prepare and install"),
                );
                busy(hwnd, app, value["busy"].as_bool().unwrap_or(false), true);
                refresh_status(hwnd, &(*app).root);
            }
            0
        }
        WM_COMMAND => {
            // Read-only interface fixtures never invoke acquisition or game mutations.
            if (*app).fixture.is_some() {
                return 0;
            }
            match (wparam & 0xffff) as i32 {
                PATH if (wparam >> 16) as u32 == EN_CHANGE && (*app).result.is_none() => idle(hwnd),
                BROWSE => {
                    if let Some(path) = pick(hwnd)
                        && let Some(folder) = path.parent()
                    {
                        label(hwnd, PATH, &folder.to_string_lossy());
                        idle(hwnd);
                    }
                }
                CACHE => {
                    if let Some(folder) = layout::pick_folder(hwnd) {
                        match setup::choose_cache(&(*app).root, &folder) {
                            Ok(()) => {
                                idle(hwnd);
                            }
                            Err(problem) => error(hwnd, &problem.to_string()),
                        }
                    }
                }
                CHECK => {
                    start(hwnd, app, Operation::Probe);
                }
                INSTALL => start(hwnd, app, Operation::Install),
                ROLLBACK => start(hwnd, app, Operation::Rollback),
                PAUSE | IDCANCEL
                    if (*app).preparing
                        && setup::status(&(*app).root)
                            .is_none_or(|value| value["state"].as_str() != Some("committing")) =>
                {
                    if let Err(problem) = setup::pause(&(*app).root) {
                        error(hwnd, &problem.to_string());
                    }
                    label(hwnd, PHASE, "Pausing safely");
                    label(
                        hwnd,
                        STATUS,
                        "Completed work is retained. Setup will finish any installation transaction safely.",
                    );
                }
                DETAILS => match setup::details(&(*app).root) {
                    Ok(path) => {
                        ShellExecuteW(
                            hwnd,
                            wide("open").as_ptr(),
                            wide(&path.to_string_lossy()).as_ptr(),
                            null(),
                            null(),
                            SW_SHOWNORMAL,
                        );
                    }
                    Err(problem) => error(hwnd, &problem.to_string()),
                },
                RELEASES => {
                    ShellExecuteW(
                        hwnd,
                        wide("open").as_ptr(),
                        wide("https://rikwow.com/install").as_ptr(),
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
                for id in layout::control_ids() {
                    assert!(
                        !GetDlgItem(hwnd, id).is_null(),
                        "Missing native control {id}"
                    );
                }
                assert!(
                    Bundle::read(EMBEDDED).is_ok(),
                    "Missing or invalid addon package"
                );
                assert!(!RUNTIME.is_empty(), "Missing local preparation runtime");
                DestroyWindow(hwnd);
                return 0;
            }
            if (*app).fixture.is_some() {
                use std::io::Write;
                if let Ok(mut trace) = std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open((*app).root.join("progress-trace.txt"))
                {
                    let _ = writeln!(trace, "Poll");
                }
            }
            if (*app).result.is_some() || (*app).fixture.is_some() {
                refresh_status(hwnd, &(*app).root);
            }
            if let Some(receiver) = &(*app).result
                && let Ok(result) = receiver.try_recv()
            {
                (*app).result = None;
                show_progress(hwnd, Display::Idle);
                match result {
                    Ok(Finished::Updated(program)) => {
                        match setup::launch_updated(&program, false) {
                            Ok(()) => {
                                label(hwnd, PHASE, "Opening updated setup");
                                (*app).close_when_done = true;
                            }
                            Err(problem) => {
                                label(hwnd, PHASE, "Setup update needs attention");
                                label(hwnd, STATUS, &problem.to_string());
                            }
                        }
                    }
                    Ok(Finished::Probe(value)) => {
                        if let Some(folder) =
                            value["resolution"]["installation"]["directory"].as_str()
                        {
                            label(hwnd, PATH, folder);
                        }
                        let build = value["resolution"]["inputs"]["identity"]["build"]
                            .as_str()
                            .unwrap_or("");
                        label(
                            hwnd,
                            SUMMARY,
                            &format!(
                                "Forever {build} verified\nQuestieDB quest information and current game files will be used."
                            ),
                        );
                        label(hwnd, PHASE, "Your game is ready");
                        label(
                            hwnd,
                            STATUS,
                            if value["rebuild"]
                                .as_array()
                                .is_some_and(|rows| rows.is_empty())
                            {
                                "Local guide files are current. Prepare and install also verifies the files in your game."
                            } else {
                                "Choose Prepare and install. Setup will download quest information and build the supported routes."
                            },
                        );
                    }
                    Ok(Finished::Installed(text)) => {
                        label(hwnd, PHASE, "Ready to play");
                        label(hwnd, STATUS, &text);
                        progress(hwnd, 100, 100);
                    }
                    Ok(Finished::RolledBack(text)) => {
                        label(hwnd, PHASE, "Backup restored");
                        label(hwnd, STATUS, &text);
                    }
                    Err(text) => {
                        label(hwnd, PHASE, "Setup needs attention");
                        label(
                            hwnd,
                            STATUS,
                            &format!(
                                "{text}\nReopen or retry setup. Existing files and verified work are retained."
                            ),
                        );
                        label(hwnd, INSTALL, "&Resume setup");
                    }
                }
                busy(hwnd, app, false, false);
                if (*app).close_when_done {
                    DestroyWindow(hwnd);
                }
            };
            0
        }
        WM_CTLCOLORSTATIC => {
            SetBkColor(wparam as HDC, GetSysColor(COLOR_WINDOW));
            SetTextColor(wparam as HDC, GetSysColor(COLOR_WINDOWTEXT));
            GetSysColorBrush(COLOR_WINDOW) as isize
        }
        WM_DPICHANGED => {
            let rect = &*(lparam as *const RECT);
            SetWindowPos(
                hwnd,
                null_mut(),
                rect.left,
                rect.top,
                rect.right - rect.left,
                rect.bottom - rect.top,
                SWP_NOZORDER,
            );
            replace_fonts(hwnd, app);
            arrange(hwnd);
            0
        }
        WM_CLOSE => {
            if (*app).result.is_none() {
                DestroyWindow(hwnd);
            } else {
                (*app).close_when_done = true;
                if (*app).preparing
                    && setup::status(&(*app).root)
                        .is_none_or(|value| value["state"].as_str() != Some("committing"))
                {
                    let _ = setup::pause(&(*app).root);
                }
                label(hwnd, PHASE, "Finishing safely");
                label(
                    hwnd,
                    STATUS,
                    "Please wait while setup retains completed work or finishes its installation transaction.",
                );
            };
            0
        }
        WM_DESTROY => {
            KillTimer(hwnd, DONE_TIMER);
            for font in (*app).fonts {
                if !font.is_null() {
                    DeleteObject(font as HGDIOBJ);
                }
            }
            PostQuitMessage(0);
            0
        }
        _ => DefWindowProcW(hwnd, message, wparam, lparam),
    }
}
pub fn run() {
    // SAFETY: all window/control/GDI handles are owned by this thread; workers receive only owned paths.
    unsafe {
        SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        let common = INITCOMMONCONTROLSEX {
            dwSize: size_of::<INITCOMMONCONTROLSEX>() as u32,
            dwICC: ICC_PROGRESS_CLASS,
        };
        InitCommonControlsEx(&common);
        windows_sys::Win32::System::Com::CoInitializeEx(
            null(),
            windows_sys::Win32::System::Com::COINIT_APARTMENTTHREADED as u32,
        );
        let root = match setup::home() {
            Ok(root) => root,
            Err(problem) => {
                error(null_mut(), &problem.to_string());
                return;
            }
        };
        let mut app = Box::new(App {
            root,
            result: None,
            smoke: std::env::args().any(|arg| arg == "--smoke-test"),
            preparing: false,
            close_when_done: false,
            fonts: [null_mut(); 3],
            progress: Progress::default(),
            fixture: {
                let args: Vec<String> = std::env::args().collect();
                args.iter()
                    .position(|arg| arg == "--ui-fixture")
                    .and_then(|at| args.get(at + 1))
                    .map(|path| {
                        let raw = std::fs::read(path).expect("UI fixture unavailable");
                        assert!(raw.len() <= 16384, "UI fixture byte bound");
                        let value: serde_json::Value =
                            serde_json::from_slice(&raw).expect("Invalid UI fixture");
                        setup::atomic_json(
                            &setup::home().expect("UI fixture home").join("status.json"),
                            &value,
                        )
                        .expect("UI fixture status");
                        value
                    })
            },
        });
        replace_fonts(null_mut(), app.as_mut());
        let class = wide("RikUIInstallerWindow");
        let instance = GetModuleHandleW(null());
        let mut window: WNDCLASSW = zeroed();
        window.lpfnWndProc = Some(procedure);
        window.hInstance = instance;
        window.lpszClassName = class.as_ptr();
        window.hCursor = LoadCursorW(null_mut(), IDC_ARROW);
        window.hbrBackground = (COLOR_WINDOW + 1) as HBRUSH;
        if RegisterClassW(&window) == 0 {
            error(null_mut(), "Could not open RikUI setup.");
            return;
        }
        let scale = GetDpiForSystem().max(96) as i32;
        let hwnd = CreateWindowExW(
            WS_EX_CONTROLPARENT,
            class.as_ptr(),
            wide("RikUI setup").as_ptr(),
            WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            690 * scale / 96,
            680 * scale / 96,
            null_mut(),
            null_mut(),
            instance,
            app.as_mut() as *mut App as *const c_void,
        );
        if hwnd.is_null() {
            error(null_mut(), "Could not create RikUI setup.");
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
