#![cfg_attr(windows, windows_subsystem = "windows")]
#[cfg(windows)]
mod gui;

fn main() {
    #[cfg(windows)]
    gui::run();
    #[cfg(not(windows))]
    eprintln!(
        "The graphical installer requires Windows. The installer library can be tested on this platform."
    );
}
