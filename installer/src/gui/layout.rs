use super::*;

pub(super) unsafe fn controls(hwnd: HWND) {
    child(hwnd, "STATIC", "RikUI", 0, [24, 18, 580, 30], 0);
    child(
        hwnd,
        "STATIC",
        "Install or update your Forever interface. Close World of Warcraft first.",
        0,
        [24, 52, 575, 24],
        0,
    );
    child(
        hwnd,
        "STATIC",
        "Forever game folder (contains WowB.exe)",
        0,
        [24, 86, 480, 22],
        0,
    );
    child(
        hwnd,
        "EDIT",
        "",
        PATH,
        [24, 112, 452, 26],
        WS_BORDER | WS_TABSTOP | ES_AUTOHSCROLL as u32,
    );
    child(
        hwnd,
        "BUTTON",
        "Browse...",
        BROWSE,
        [488, 112, 100, 26],
        WS_TABSTOP,
    );
    child(
        hwnd,
        "STATIC",
        "Checking bundled files...",
        SUMMARY,
        [24, 158, 564, 64],
        0,
    );
    child(
        hwnd,
        "BUTTON",
        "Choose package...",
        PACKAGE,
        [24, 226, 145, 28],
        WS_TABSTOP,
    );
    child(
        hwnd,
        "BUTTON",
        "Get latest release",
        RELEASES,
        [182, 226, 145, 28],
        WS_TABSTOP,
    );
    child(
        hwnd,
        "STATIC",
        "Existing quest data and settings are preserved. Updates keep a complete backup.",
        0,
        [24, 276, 564, 42],
        0,
    );
    child(
        hwnd,
        "BUTTON",
        "Install / update",
        INSTALL,
        [24, 324, 150, 34],
        WS_TABSTOP | BS_DEFPUSHBUTTON as u32,
    );
    child(
        hwnd,
        "BUTTON",
        "Roll back",
        ROLLBACK,
        [190, 324, 112, 34],
        WS_TABSTOP,
    );
    child(
        hwnd,
        "STATIC",
        "Ready. Choose your game folder.",
        STATUS,
        [24, 380, 564, 92],
        0,
    );
}
pub(super) unsafe fn pick(hwnd: HWND, package: bool) -> Option<PathBuf> {
    let mut file = [0u16; 32768];
    let filter = if package {
        wide("RikUI bundle (*.zip)\0*.zip\0\0")
    } else {
        wide("Forever client (WowB.exe)\0WowB.exe\0\0")
    };
    let title = wide(if package {
        "Choose a RikUI installer bundle"
    } else {
        "Select your Forever WowB.exe"
    });
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
    let end = file.iter().position(|c| *c == 0).unwrap_or(file.len());
    use std::os::windows::ffi::OsStringExt;
    Some(PathBuf::from(std::ffi::OsString::from_wide(&file[..end])))
}
pub(super) unsafe fn summary(hwnd: HWND, bytes: &[u8]) {
    match Bundle::read(bytes) {
        Ok(bundle) => label(
            hwnd,
            SUMMARY,
            &format!(
                "RikUI {}\r\nIncluded: {}",
                bundle.manifest.version,
                bundle.manifest.components.join(", ")
            ),
        ),
        Err(_) => label(
            hwnd,
            SUMMARY,
            "No usable embedded package. Choose a verified RikUI bundle ZIP.",
        ),
    }
}
