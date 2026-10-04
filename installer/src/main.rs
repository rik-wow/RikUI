#![cfg_attr(windows, windows_subsystem = "windows")]
#[cfg(windows)]
mod gui;
fn main() {
    #[cfg(windows)]
    {
        let arguments: Vec<String> = std::env::args().collect();
        if let Some(index) = arguments
            .iter()
            .position(|argument| argument == "--verify-package")
        {
            let outcome = arguments
                .get(index + 1)
                .ok_or("Package receipt path required")
                .map_err(|error| -> Box<dyn std::error::Error + Send + Sync> { error.into() })
                .and_then(|path| {
                    rikui_installer::setup::verify_package(std::path::Path::new(path))
                });
            std::process::exit(if outcome.is_ok() { 0 } else { 1 });
        }
        if let Some(index) = arguments
            .iter()
            .position(|argument| argument == "--install-current")
        {
            let outcome = rikui_installer::setup::home().and_then(|root| {
                let storage = arguments
                    .get(index + 1)
                    .ok_or("Game storage folder required")?;
                let result = rikui_installer::setup::prepare_install(
                    std::path::Path::new(storage),
                    &root,
                    true,
                    !arguments.iter().any(|argument| argument == "--no-schedule"),
                );
                if let Err(error) = &result {
                    rikui_installer::setup::atomic_json(
                        &root.join("installation-error.json"),
                        &serde_json::json!({"state":"failed","message":error.to_string()}),
                    )?;
                }
                result
            });
            std::process::exit(if outcome.is_ok() { 0 } else { 1 });
        }
        if rikui_installer::setup::wait_for_previous().is_err() {
            std::process::exit(1);
        }
        if std::env::args().any(|argument| argument == "--daily-update") {
            let outcome=rikui_installer::setup::home().and_then(|root|{
                let work = || -> rikui_installer::Result<()> {
                    if let Some(program)=rikui_installer::setup::update_program(&root)? {
                        rikui_installer::setup::launch_updated(&program,true)?;
                    } else {
                        rikui_installer::setup::daily(&root)?;
                    }
                    Ok(())
                };
                match work() {
                    Ok(_)=>{
                        rikui_installer::setup::atomic_json(&root.join("daily-update.json"),
                            &serde_json::json!({"state":"checked","status":root.join("status.json"),
                                "checkedAt":std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_secs()}))?;
                        Ok(())
                    },
                    Err(error)=>{
                        rikui_installer::setup::atomic_json(&root.join("daily-update.json"),
                          &serde_json::json!({"state":"needs-attention","message":error.to_string(),
                            "recovery":"Open RikUI setup to resume. Existing files, inputs and backups are preserved."}))?;
                        Err(error)
                    }
                }
            });
            if outcome.is_err() {
                std::process::exit(1);
            }
        } else {
            gui::run();
        }
    }
    #[cfg(not(windows))]
    eprintln!(
        "The graphical installer requires Windows. Its library can be tested on this platform."
    );
}
