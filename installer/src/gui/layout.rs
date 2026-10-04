use super::*;
fn definitions() -> Vec<(&'static str, &'static str, i32, [i32; 4], u32)> {
    vec![
        ("Static", "RikUI", 120, [32, 14, 606, 36], 0),
        (
            "Static",
            "Your quest guide and routes, prepared from current Forever inputs.",
            121,
            [32, 56, 606, 36],
            0,
        ),
        (
            "Static",
            "1  Find game   →   2  Get quests   →   3  Prepare routes   →   4  Ready",
            122,
            [32, 100, 606, 24],
            0,
        ),
        (
            "Static",
            "Find your Forever game",
            PHASE,
            [32, 140, 606, 32],
            0,
        ),
        ("Static", "&Forever game folder", 123, [32, 188, 606, 22], 0),
        (
            "Edit",
            "",
            PATH,
            [32, 216, 460, 30],
            WS_BORDER | WS_TABSTOP | ES_AUTOHSCROLL as u32,
        ),
        (
            "Button",
            "&Browse…",
            BROWSE,
            [508, 216, 130, 30],
            WS_TABSTOP,
        ),
        (
            "Static",
            "Checking your game…",
            SUMMARY,
            [32, 260, 606, 42],
            0,
        ),
        (
            "Static",
            "QuestieDB supplies quest targets and locations. Setup obtains it from its publisher. Routes are generated locally from your game files.",
            124,
            [32, 314, 606, 46],
            0,
        ),
        (
            "Static",
            "First preparation needs 16 GiB free. Setup stores compressed build files. You can pause and resume. Unknown quests and unsupported regions stay explicit.",
            125,
            [32, 372, 606, 42],
            0,
        ),
        ("msctls_progress32", "", PROGRESS, [32, 428, 606, 16], 0x08),
        ("Static", "", METRICS, [32, 454, 606, 24], 0),
        (
            "Button",
            "&Prepare and install",
            INSTALL,
            [32, 492, 194, 38],
            WS_TABSTOP | BS_DEFPUSHBUTTON as u32,
        ),
        (
            "Button",
            "&Pause setup",
            PAUSE,
            [242, 492, 140, 38],
            WS_TABSTOP,
        ),
        (
            "Button",
            "Preparation &folder…",
            CACHE,
            [398, 492, 240, 38],
            WS_TABSTOP,
        ),
        (
            "Static",
            "Choose your game folder to begin.",
            STATUS,
            [32, 544, 606, 62],
            0,
        ),
        (
            "Button",
            "&Check again",
            CHECK,
            [32, 610, 140, 28],
            WS_TABSTOP,
        ),
        (
            "Button",
            "&Restore backup",
            ROLLBACK,
            [184, 610, 145, 28],
            WS_TABSTOP,
        ),
        (
            "Button",
            "View &details",
            DETAILS,
            [342, 610, 140, 28],
            WS_TABSTOP,
        ),
        (
            "Button",
            "Installation &help",
            RELEASES,
            [494, 610, 144, 28],
            WS_TABSTOP,
        ),
    ]
}
pub(super) fn control_ids() -> Vec<i32> {
    definitions()
        .into_iter()
        .map(|(_, _, id, _, _)| id)
        .collect()
}
pub(super) unsafe fn controls(hwnd: HWND) {
    for (kind, text, id, rect, style) in definitions() {
        child(hwnd, kind, text, id, rect, style);
    }
}
pub(super) unsafe fn arrange(hwnd: HWND) {
    let dpi = GetDpiForWindow(hwnd).max(96) as i32;
    for (_, _, id, rect, _) in definitions() {
        MoveWindow(
            GetDlgItem(hwnd, id),
            rect[0] * dpi / 96,
            rect[1] * dpi / 96,
            rect[2] * dpi / 96,
            rect[3] * dpi / 96,
            1,
        );
    }
}
pub(super) unsafe fn pick_folder(hwnd: HWND) -> Option<PathBuf> {
    use windows_sys::Win32::{
        System::Com::CoTaskMemFree,
        UI::Shell::{BROWSEINFOW, SHBrowseForFolderW, SHGetPathFromIDListW},
    };
    let title = wide("Choose a drive or folder with space for local preparation");
    let mut display = [0u16; 260];
    let info = BROWSEINFOW {
        hwndOwner: hwnd,
        pidlRoot: null_mut(),
        pszDisplayName: display.as_mut_ptr(),
        lpszTitle: title.as_ptr(),
        ulFlags: 0x0041,
        lpfn: None,
        lParam: 0,
        iImage: 0,
    };
    let item = SHBrowseForFolderW(&info);
    if item.is_null() {
        return None;
    }
    let mut path = [0u16; 260];
    let ok = SHGetPathFromIDListW(item, path.as_mut_ptr());
    CoTaskMemFree(item as *const c_void);
    if ok == 0 {
        return None;
    }
    use std::os::windows::ffi::OsStringExt;
    let end = path
        .iter()
        .position(|value| *value == 0)
        .unwrap_or(path.len());
    Some(PathBuf::from(std::ffi::OsString::from_wide(&path[..end])))
}
pub(super) unsafe fn pick(hwnd: HWND) -> Option<PathBuf> {
    let mut file = [0u16; 32768];
    let filter = wide("World of Warcraft client (*.exe)\0Wow*.exe\0\0");
    let title = wide("Choose your current Forever game executable");
    let mut dialog: OPENFILENAMEW = zeroed();
    dialog.lStructSize = size_of::<OPENFILENAMEW>() as u32;
    dialog.hwndOwner = hwnd;
    dialog.lpstrFile = file.as_mut_ptr();
    dialog.nMaxFile = file.len() as u32;
    dialog.lpstrFilter = filter.as_ptr();
    dialog.lpstrTitle = title.as_ptr();
    dialog.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR | OFN_DONTADDTORECENT;
    if GetOpenFileNameW(&mut dialog) == 0 {
        return None;
    }
    let end = file
        .iter()
        .position(|value| *value == 0)
        .unwrap_or(file.len());
    use std::os::windows::ffi::OsStringExt;
    Some(PathBuf::from(std::ffi::OsString::from_wide(&file[..end])))
}
