//! Local assembly, exact-byte installation and the daily update entry point.
use crate::{
    EMBEDDED, RUNTIME, Result,
    bundle::{Bundle, digest},
    runtime,
    transaction::{Installer, normal},
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{SystemTime, UNIX_EPOCH},
};

#[derive(Serialize, Deserialize)]
pub struct Configuration {
    pub storage_root: PathBuf,
    pub executable: PathBuf,
    pub workers: u8,
}
pub fn home() -> Result<PathBuf> {
    let base = std::env::var_os("LOCALAPPDATA")
        .ok_or("Windows local application-data folder unavailable")?;
    let root = PathBuf::from(base).join("RikUI");
    if !root.is_absolute() {
        return Err("Absolute local application-data folder required".into());
    }
    for path in root.ancestors() {
        if path.exists() {
            normal(path)?;
        }
    }
    fs::create_dir_all(&root)?;
    Ok(root)
}
fn hidden(command: &mut Command) {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000);
    }
    #[cfg(not(windows))]
    let _ = command;
}
pub fn atomic_json(path: &Path, value: &impl Serialize) -> Result<()> {
    let next = path.with_extension(format!(
        "next-{}",
        SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
    ));
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&next)?;
    file.write_all(&serde_json::to_vec_pretty(value)?)?;
    file.sync_all()?;
    drop(file);
    if path.exists() {
        normal(path)?;
    }
    for attempt in 0..40 {
        match fs::rename(&next, path) {
            Ok(()) => return Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::PermissionDenied && attempt < 39 => {
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
            Err(error) => return Err(error.into()),
        }
    }
    Err("Unable to publish setup receipt".into())
}
fn json(path: &Path) -> Result<Value> {
    normal(path)?;
    if fs::metadata(path)?.len() > 16 * 1024 * 1024 {
        return Err("Setup receipt byte bound".into());
    }
    Ok(serde_json::from_slice(&fs::read(path)?)?)
}
pub fn cache(root: &Path) -> Result<PathBuf> {
    let target = json(&root.join("preferences.json"))
        .ok()
        .and_then(|value| value["preparation_folder"].as_str().map(PathBuf::from))
        .unwrap_or_else(|| root.join("cache"));
    if !target.is_absolute() {
        return Err("Absolute preparation folder required".into());
    }
    for path in target.ancestors() {
        if path.exists() {
            normal(path)?;
        }
    }
    Ok(target)
}
pub fn choose_cache(root: &Path, selected: &Path) -> Result<()> {
    if !selected.is_absolute() || !selected.is_dir() {
        return Err("Choose an existing preparation folder".into());
    }
    for path in selected.ancestors() {
        normal(path)?;
    }
    // The selected folder can contain other files; setup owns only this child.
    let target = selected.join("RikUI-preparation");
    for path in target.ancestors() {
        if path.exists() {
            normal(path)?;
        }
    }
    atomic_json(
        &root.join("preferences.json"),
        &serde_json::json!({"preparation_folder":target}),
    )?;
    Ok(())
}

fn worker(
    runtime: &Path,
    root: &Path,
    storage: &Path,
    base: &Path,
    result: &Path,
    probe: bool,
) -> Result<Value> {
    let log_path = root.join(if probe {
        "update-check.log"
    } else {
        "preparation.log"
    });
    if log_path.exists() {
        normal(&log_path)?;
    }
    let log = File::create(log_path)?;
    let mut command = Command::new(runtime.join("python/python.exe"));
    command
        .arg("-B")
        .arg(runtime.join("tools/local_assembly.py"))
        .arg("--runtime")
        .arg(runtime)
        .arg("--cache")
        .arg(cache(root)?)
        .arg("--storage-root")
        .arg(storage)
        .arg("--base-bundle")
        .arg(base)
        .arg("--status")
        .arg(root.join("status.json"))
        .arg("--result")
        .arg(result)
        .arg("--workers")
        .arg("2")
        .current_dir(runtime.join("tools"))
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    if probe {
        command.arg("--check-only");
    }
    hidden(&mut command);
    if !command.status()?.success() {
        let status = json(&root.join("status.json")).ok();
        let message = status
            .as_ref()
            .and_then(|value| value["message"].as_str())
            .unwrap_or("Preparation did not finish. Existing files and backups are preserved.");
        return Err(message.to_string().into());
    }
    json(result)
}
fn required_path<'a>(value: &'a Value, key: &str) -> Result<&'a str> {
    value[key]
        .as_str()
        .ok_or_else(|| format!("Missing setup result field: {key}").into())
}
pub fn inspect(storage: &Path, root: &Path) -> Result<Value> {
    for path in root.ancestors() {
        if path.exists() {
            normal(path)?;
        }
    }
    fs::create_dir_all(root)?;
    let lock_path = root.join("setup.lock");
    if lock_path.exists() {
        normal(&lock_path)?;
    }
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(lock_path)?;
    lock.try_lock()
        .map_err(|_| "Another RikUI setup is using this local cache")?;
    atomic_json(
        &root.join("status.json"),
        &serde_json::json!({"phase":"Checking your game","message":"Checking the latest Forever build, quest publisher and local files."}),
    )?;
    let runtime = runtime::ensure(RUNTIME, &root.join("runtimes"))?;
    let base = root.join("base-bundle.zip");
    if base.exists() {
        normal(&base)?;
    }
    fs::write(&base, EMBEDDED)?;
    worker(
        &runtime,
        root,
        storage,
        &base,
        &root.join("probe.json"),
        true,
    )
}
/// A player-readable receipt; raw logs stay available beside it for recovery.
pub fn details(root: &Path) -> Result<PathBuf> {
    let installed = json(&root.join("installed.json")).ok();
    let status = json(&root.join("status.json")).ok();
    let mut body = format!(
        "RikUI setup details\r\n\r\nPreparation folder: {}\r\n\r\n",
        cache(root)?.display()
    );
    if let Some(value) = &status {
        body.push_str(&format!(
            "Current step: {}\r\n{}\r\n\r\n",
            value["phase"].as_str().unwrap_or("Checking setup"),
            value["message"].as_str().unwrap_or("")
        ));
    }
    if let Some(value) = &installed {
        body.push_str(&format!(
            "Verified Forever version: {}\r\nGame folder: {}\r\nBackup: {}\r\n\r\n",
            value["resolution"]["inputs"]["identity"]["build"]
                .as_str()
                .unwrap_or("unknown"),
            value["game"].as_str().unwrap_or("unknown"),
            value["backup"]
                .as_str()
                .unwrap_or("Unchanged installation; previous backups retained")
        ));
        let coverage = &value["coverage"];
        body.push_str(&format!("Quest coverage\r\n{} quests have provider information. {} current client quest IDs have membership only, without provider objectives or locations. Unknown data is shown as unknown in the guide.\r\n",
            coverage["questCounts"]["quests"].as_u64().unwrap_or(0),
            coverage["clientUniverse"]["clientOnly"].as_u64().unwrap_or(0)));
        if let Some(worlds) = coverage["worlds"].as_array() {
            body.push_str("Navigation regions prepared (game map IDs): ");
            body.push_str(
                &worlds
                    .iter()
                    .filter_map(|world| world["worldMapID"].as_u64())
                    .map(|world| world.to_string())
                    .collect::<Vec<_>>()
                    .join(", "),
            );
            body.push_str("\r\n");
        }
        if let Some(limits) = coverage["limits"].as_array() {
            for limit in limits {
                if let Some(text) = limit.as_str() {
                    body.push_str(text);
                    body.push_str("\r\n");
                }
            }
        }
        body.push_str("\r\n");
    } else {
        body.push_str("Preparation has not produced a verified installation yet. Your existing game and addon files are preserved.\r\n\r\n");
    }
    body.push_str("How preparation works\r\nQuestieDB reference information is obtained separately from its publisher. Terrain and quest membership are read from your current Forever client. Guide and supported routes are generated only on this computer. Provider lag, unknown quest semantics and unsupported floors or physics remain explicit.\r\n\r\nRecovery\r\nOpen setup and choose Resume setup to retry interrupted preparation. Verified completed work is reused. Use Restore backup to restore the previous owned addon files. Your WoW settings are preserved.\r\n\r\n");
    body.push_str(&format!(
        "Local receipt and log folder: {}\r\nHelp: https://rikwow.com/install\r\n",
        root.display()
    ));
    let target = root.join("installation-details.txt");
    if target.exists() {
        normal(&target)?;
    }
    let next = root.join(format!(
        "details-next-{}",
        SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
    ));
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&next)?;
    file.write_all(body.as_bytes())?;
    file.sync_all()?;
    fs::rename(next, &target)?;
    Ok(target)
}

pub fn saved_storage(root: &Path) -> Option<PathBuf> {
    json(&root.join("configuration.json"))
        .ok()
        .and_then(|value| value["storage_root"].as_str().map(PathBuf::from))
}
pub fn status(root: &Path) -> Option<Value> {
    json(&root.join("status.json")).ok()
}
pub fn pause(root: &Path) -> Result<()> {
    let cache = cache(root)?;
    for path in cache.ancestors() {
        if path.exists() {
            normal(path)?;
        }
    }
    fs::create_dir_all(&cache)?;
    let cancel = cache.join("cancel");
    if cancel.exists() {
        normal(&cancel)?;
    }
    fs::write(cancel, b"Player paused preparation")?;
    Ok(())
}
pub fn prepare_install(
    storage: &Path,
    root: &Path,
    resume: bool,
    schedule_updates: bool,
) -> Result<String> {
    for path in root.ancestors() {
        if path.exists() {
            normal(path)?;
        }
    }
    fs::create_dir_all(root)?;
    let lock_path = root.join("setup.lock");
    if lock_path.exists() {
        normal(&lock_path)?;
    }
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(lock_path)?;
    lock.try_lock()
        .map_err(|_| "Another RikUI setup is using this local cache")?;
    let cancel = cache(root)?.join("cancel");
    if cancel.exists() {
        normal(&cancel)?;
        if resume {
            fs::remove_file(&cancel)?;
        } else {
            return Err("Updates paused. Open RikUI setup and choose Resume setup.".into());
        }
    }
    atomic_json(
        &root.join("status.json"),
        &serde_json::json!({"phase":"Checking setup","message":"Verifying the packaged tools. Your game files remain preserved.","state":"running"}),
    )?;
    let runtime = runtime::ensure(RUNTIME, &root.join("runtimes"))?;
    let base = root.join("base-bundle.zip");
    if base.exists() {
        normal(&base)?;
    }
    fs::write(&base, EMBEDDED)?;
    let result = worker(
        &runtime,
        root,
        storage,
        &base,
        &root.join("result.json"),
        false,
    )?;
    let probe = worker(
        &runtime,
        root,
        storage,
        &base,
        &root.join("probe.json"),
        true,
    )?;
    if probe["resolution"]["fingerprint"] != result["resolution"]["fingerprint"]
        || probe["rebuild"]
            .as_array()
            .is_none_or(|rows| !rows.is_empty())
    {
        return Err("Inputs changed before installation. Reopen setup to refresh safely.".into());
    }
    let cache = cache(root)?.canonicalize()?;
    let bundle_path = PathBuf::from(required_path(&result, "bundle")?);
    normal(&bundle_path)?;
    if !bundle_path.canonicalize()?.starts_with(&cache) {
        return Err("Generated bundle outside local cache".into());
    }
    let bytes = fs::read(&bundle_path)?;
    if digest(&bytes) != required_path(&result, "bundleSHA256")? {
        return Err("Generated bundle byte verification failed".into());
    }
    let bundle = Bundle::read(&bytes)?;
    let installation = &result["resolution"]["installation"];
    let game = PathBuf::from(required_path(installation, "directory")?);
    let executable = PathBuf::from(required_path(installation, "executable")?);
    if game_running(&executable)? {
        atomic_json(
            &root.join("status.json"),
            &serde_json::json!({"phase":"Ready to install","state":"waiting-for-game","message":"Preparation is verified. Close World of Warcraft, then reopen setup to finish installation."}),
        )?;
        return Err("Close World of Warcraft to finish the verified installation. Prepared work is retained.".into());
    }
    if cancel.exists() {
        return Err("Preparation paused before installation. Verified work is retained.".into());
    }
    atomic_json(
        &root.join("status.json"),
        &serde_json::json!({"phase":"Finishing installation","state":"committing","message":"Installing verified files and retaining your backup. Please wait for this transaction to finish safely."}),
    )?;
    let installer = Installer::open(&game)?;
    let backup = if installer.verify(&bundle).is_ok() {
        None
    } else {
        Some(installer.install(&bundle)?)
    };
    installer.verify(&bundle)?;
    let config = Configuration {
        storage_root: PathBuf::from(required_path(installation, "storageRoot")?),
        executable,
        workers: 2,
    };
    atomic_json(&root.join("configuration.json"), &config)?;
    atomic_json(
        &root.join("installed.json"),
        &serde_json::json!({"format":"rikui-verified-installation-v1",
   "bundleSHA256":digest(&bytes),"resolution":result["resolution"],"coverage":result["coverage"],"game":game,"backup":backup}),
    )?;
    if schedule_updates {
        schedule(root)?;
    }
    atomic_json(
        &root.join("status.json"),
        &serde_json::json!({"phase":"Ready to play","state":"installed",
   "message":if schedule_updates {"Quest guide and supported routes installed and verified. Daily checks are active."}
       else {"Quest guide and supported routes installed and verified."},
   "coverage":result["coverage"],"build":result["resolution"]["inputs"]["identity"]["build"]}),
    )?;
    details(root)?;
    Ok(if schedule_updates {
        "Quest guide and supported routes are installed and verified.\nDaily update checks are active. Coverage and backups are listed in Details.".into()
    } else {
        "Quest guide and supported routes are installed and verified.\nCoverage and backups are listed in Details.".into()
    })
}
pub fn verify_package(target: &Path) -> Result<()> {
    let parent = target.parent().ok_or("Package receipt requires a parent")?;
    if !parent.is_absolute() {
        return Err("Absolute verification output required".into());
    }
    let bundle = Bundle::read(EMBEDDED)?;
    let runtime = runtime::ensure(RUNTIME, &parent.join("verified-runtime"))?;
    let manifest = fs::read(runtime.join("runtime.json"))?;
    let program = fs::read(std::env::current_exe()?)?;
    atomic_json(
        target,
        &serde_json::json!({
            "format":"rikui-embedded-package-proof-v1", "version":bundle.manifest.version,
            "programSHA256":digest(&program), "baseSHA256":digest(EMBEDDED),
            "runtimeSHA256":digest(RUNTIME), "runtimeManifestSHA256":digest(&manifest),
            "runtimeFiles":serde_json::from_slice::<Value>(&manifest)?["files"].as_array().ok_or("Runtime inventory")?.len()
        }),
    )
}

pub fn daily(root: &Path) -> Result<String> {
    let config: Configuration = serde_json::from_value(json(&root.join("configuration.json"))?)?;
    prepare_install(&config.storage_root, root, false, true)
}
pub fn schedule(root: &Path) -> Result<()> {
    let source = std::env::current_exe()?;
    normal(&source)?;
    let bytes = fs::read(&source)?;
    let directory = root.join("programs").join(digest(&bytes));
    fs::create_dir_all(&directory)?;
    normal(&directory)?;
    let target = directory.join("RikUI-Setup.exe");
    if target.exists() {
        normal(&target)?;
        if digest(&fs::read(&target)?) != digest(&bytes) {
            let retained = directory.join(format!(
                "RikUI-Setup-retained-{}.exe",
                SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
            ));
            fs::rename(&target, retained)?;
        }
    }
    if !target.exists() {
        fs::write(&target, &bytes)?;
    }
    normal(&target)?;
    if digest(&fs::read(&target)?) != digest(&bytes) {
        return Err("Saved update program failed verification".into());
    }
    let task = format!("\"{}\" --daily-update", target.display());
    let system =
        PathBuf::from(std::env::var_os("SystemRoot").ok_or("Windows system folder unavailable")?);
    let mut command = Command::new(system.join("System32/schtasks.exe"));
    command.args([
        "/Create",
        "/SC",
        "DAILY",
        "/TN",
        "RikUI Current Forever Updates",
        "/TR",
        &task,
        "/ST",
        "12:00",
        "/F",
    ]);
    hidden(&mut command);
    let result = command.output()?;
    if !result.status.success() {
        return Err(format!(
            "Installation verified, but daily scheduling failed: {}",
            String::from_utf8_lossy(&result.stderr)
        )
        .into());
    }
    Ok(())
}
pub fn game_running(executable: &Path) -> Result<bool> {
    #[cfg(windows)]
    {
        use windows_sys::Win32::{
            Foundation::{CloseHandle, INVALID_HANDLE_VALUE},
            System::Diagnostics::ToolHelp::{
                CreateToolhelp32Snapshot, PROCESSENTRY32W, Process32FirstW, Process32NextW,
                TH32CS_SNAPPROCESS,
            },
        };
        let expected = executable
            .file_name()
            .ok_or("Game executable name missing")?
            .to_string_lossy();
        // SAFETY: snapshot and initialized PROCESSENTRY32W remain valid throughout enumeration and are closed exactly once.
        unsafe {
            let snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
            if snapshot == INVALID_HANDLE_VALUE {
                return Err("Could not check running game processes".into());
            }
            let mut entry: PROCESSENTRY32W = std::mem::zeroed();
            entry.dwSize = std::mem::size_of::<PROCESSENTRY32W>() as u32;
            let mut success = Process32FirstW(snapshot, &mut entry);
            let mut running = false;
            while success != 0 {
                let end = entry
                    .szExeFile
                    .iter()
                    .position(|value| *value == 0)
                    .unwrap_or(entry.szExeFile.len());
                if String::from_utf16_lossy(&entry.szExeFile[..end]).eq_ignore_ascii_case(&expected)
                {
                    running = true;
                    break;
                }
                success = Process32NextW(snapshot, &mut entry);
            }
            CloseHandle(snapshot);
            Ok(running)
        }
    }
    #[cfg(not(windows))]
    {
        let _ = executable;
        Ok(false)
    }
}

pub fn update_program(root: &Path) -> Result<Option<PathBuf>> {
    for path in root.ancestors() {
        if path.exists() {
            normal(path)?;
        }
    }
    fs::create_dir_all(root)?;
    let lock_path = root.join("setup.lock");
    if lock_path.exists() {
        normal(&lock_path)?;
    }
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(lock_path)?;
    lock.try_lock()
        .map_err(|_| "Another RikUI setup is checking updates")?;
    atomic_json(
        &root.join("status.json"),
        &serde_json::json!({"phase":"Checking setup updates","message":"Checking the published RikUI setup channel for newer compatibility support."}),
    )?;
    let runtime = runtime::ensure(RUNTIME, &root.join("runtimes"))?;
    let version = Bundle::read(EMBEDDED)?.manifest.version;
    let log_path = root.join("setup-update.log");
    if log_path.exists() {
        normal(&log_path)?;
    }
    let log = File::create(log_path)?;
    let result_path = root.join("setup-update.json");
    let mut command = Command::new(runtime.join("python/python.exe"));
    command
        .arg("-B")
        .arg(runtime.join("tools/update_setup.py"))
        .arg("--version")
        .arg(version)
        .arg("--current-program")
        .arg(std::env::current_exe()?)
        .arg("--programs")
        .arg(root.join("programs"))
        .arg("--result")
        .arg(&result_path)
        .current_dir(runtime.join("tools"))
        .stdout(Stdio::from(log.try_clone()?))
        .stderr(Stdio::from(log));
    hidden(&mut command);
    if !command.status()?.success() {
        return Err("The RikUI update channel could not be verified. Check your connection and retry. Details are retained in setup-update.log.".into());
    }
    let value = json(&result_path)?;
    if value["state"].as_str() == Some("current") {
        return Ok(None);
    }
    if value["state"].as_str() != Some("verified-update") {
        return Err("Unsupported setup update result".into());
    }
    let program = PathBuf::from(required_path(&value, "program")?);
    normal(&program)?;
    if !program
        .canonicalize()?
        .starts_with(root.join("programs").canonicalize()?)
    {
        return Err("Setup update outside its owned program directory".into());
    }
    if fs::metadata(&program)?.len() > 256 * 1024 * 1024
        || digest(&fs::read(&program)?) != required_path(&value, "sha256")?
    {
        return Err("Downloaded setup failed byte verification".into());
    }
    Ok(Some(program))
}
pub fn launch_updated(program: &Path, daily: bool) -> Result<()> {
    normal(program)?;
    let mut command = Command::new(program);
    command
        .arg("--wait-for-pid")
        .arg(std::process::id().to_string());
    if daily {
        command.arg("--daily-update");
    }
    hidden(&mut command);
    command.spawn()?;
    Ok(())
}
pub fn wait_for_previous() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if let Some(at) = args.iter().position(|arg| arg == "--wait-for-pid") {
        let pid: u32 = args
            .get(at + 1)
            .ok_or("Missing previous setup process")?
            .parse()?;
        #[cfg(windows)]
        {
            use windows_sys::Win32::{
                Foundation::CloseHandle,
                System::Threading::{OpenProcess, PROCESS_SYNCHRONIZE, WaitForSingleObject},
            };
            // SAFETY: synchronization-only handle is closed once; the wait is bounded.
            unsafe {
                let handle = OpenProcess(PROCESS_SYNCHRONIZE, 0, pid);
                if !handle.is_null() {
                    let outcome = WaitForSingleObject(handle, 60000);
                    CloseHandle(handle);
                    if outcome != 0 {
                        return Err(
                            "Previous setup has not finished. Reopen setup to resume safely."
                                .into(),
                        );
                    }
                }
            }
        }
        #[cfg(not(windows))]
        let _ = pid;
    }
    Ok(())
}
