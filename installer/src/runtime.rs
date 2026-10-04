//! Manifest-verified extraction of the embedded build runtime.
use crate::{
    Result,
    bundle::{Entry, digest},
    transaction::normal,
};
use serde::Deserialize;
use std::{
    collections::{BTreeMap, BTreeSet},
    fs::{self, OpenOptions},
    io::{Cursor, Read, Write},
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};
const MAX_BYTES: u64 = 512 * 1024 * 1024;
#[derive(Deserialize)]
struct Manifest {
    format: String,
    files: Vec<RuntimeEntry>,
}
#[derive(Deserialize)]
struct RuntimeEntry {
    path: String,
    bytes: u64,
    sha256: String,
}
fn safe_name(name: &str) -> Result<()> {
    if name.is_empty()
        || !name.is_ascii()
        || name.split('/').any(|part| {
            let stem = part.split('.').next().unwrap_or("").to_ascii_uppercase();
            part.is_empty()
                || part == "."
                || part == ".."
                || part.ends_with(['.', ' '])
                || ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"].contains(&stem.as_str())
                || ["COM", "LPT"].iter().any(|prefix| {
                    stem.strip_prefix(prefix)
                        .is_some_and(|v| ["1", "2", "3", "4", "5", "6", "7", "8", "9"].contains(&v))
                })
                || part
                    .chars()
                    .any(|v| v.is_control() || "<>:\"\\|?*".contains(v))
        })
    {
        return Err("Unsafe runtime path".into());
    }
    Ok(())
}
fn verify(root: &Path, files: &BTreeMap<String, Vec<u8>>) -> Result<()> {
    fn walk(root: &Path, directory: &Path, names: &mut BTreeSet<String>) -> Result<()> {
        normal(directory)?;
        for entry in fs::read_dir(directory)? {
            let path = entry?.path();
            normal(&path)?;
            if path.is_dir() {
                walk(root, &path, names)?;
            } else {
                names.insert(
                    path.strip_prefix(root)?
                        .to_string_lossy()
                        .replace('\\', "/"),
                );
                if names.len() > 8192 {
                    return Err("Runtime inventory bound".into());
                }
            }
        }
        Ok(())
    }
    let mut actual = BTreeSet::new();
    walk(root, root, &mut actual)?;
    if actual != files.keys().cloned().collect() {
        return Err("Unlisted runtime files".into());
    }
    for (name, bytes) in files {
        let path = root.join(name);
        for part in path.ancestors() {
            if part.exists() {
                normal(part)?;
            }
        }
        if fs::metadata(&path)?.len() != bytes.len() as u64
            || digest(&fs::read(path)?) != digest(bytes)
        {
            return Err("Packaged runtime bytes changed".into());
        }
    }
    Ok(())
}
pub fn ensure(bytes: &[u8], parent: &Path) -> Result<PathBuf> {
    if !parent.is_absolute() {
        return Err("Absolute runtime cache required".into());
    }
    for part in parent.ancestors() {
        if part.exists() {
            normal(part)?;
        }
    }
    let mut archive = zip::ZipArchive::new(Cursor::new(bytes))?;
    if archive.len() > 8192 {
        return Err("Runtime file count bound".into());
    }
    let mut files = BTreeMap::new();
    let mut names = BTreeSet::new();
    let mut total = 0u64;
    for index in 0..archive.len() {
        let mut file = archive.by_index(index)?;
        let name = file.name().to_owned();
        safe_name(&name)?;
        if file.is_dir() || file.unix_mode().is_some_and(|m| m & 0o170000 == 0o120000) {
            return Err("Linked or directory runtime entry".into());
        }
        total = total
            .checked_add(file.size())
            .ok_or("Runtime size overflow")?;
        if total > MAX_BYTES
            || file.size() > 128 * 1024 * 1024
            || !names.insert(name.to_ascii_lowercase())
        {
            return Err("Runtime byte bound or duplicate path".into());
        }
        let mut raw = Vec::new();
        file.read_to_end(&mut raw)?;
        files.insert(name, raw);
    }
    let manifest: Manifest = serde_json::from_slice(
        files
            .get("runtime.json")
            .ok_or("Missing runtime manifest")?,
    )?;
    if manifest.format != "rikui-local-runtime-v1" || manifest.files.len() + 1 != files.len() {
        return Err("Runtime inventory mismatch".into());
    }
    let mut inventory = BTreeMap::new();
    for row in manifest.files {
        safe_name(&row.path)?;
        if row.path == "runtime.json"
            || inventory
                .insert(
                    row.path.clone(),
                    Entry {
                        bytes: row.bytes,
                        sha256: row.sha256,
                    },
                )
                .is_some()
        {
            return Err("Duplicate runtime manifest row".into());
        }
    }
    for (name, row) in inventory {
        let body = files.get(&name).ok_or("Missing runtime file")?;
        if body.len() as u64 != row.bytes || digest(body) != row.sha256 {
            return Err("Runtime source hash mismatch".into());
        }
    }
    for required in [
        "python/python.exe",
        "node/node.exe",
        "extractor/TACTTool.exe",
        "tools/local_assembly.py",
    ] {
        if !files.contains_key(required) {
            return Err("Incomplete preparation runtime".into());
        }
    }
    fs::create_dir_all(parent)?;
    let root = parent.join(digest(bytes));
    if root.exists() {
        if verify(&root, &files).is_ok() {
            return Ok(root);
        }
        normal(&root)?;
        let retained = parent.join(format!(
            "retained-{}",
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
        ));
        if root.parent() != Some(parent) || retained.parent() != Some(parent) {
            return Err("Runtime retention boundary".into());
        }
        fs::rename(&root, retained)?;
    }
    let stage = parent.join(format!(
        "stage-{}",
        SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos()
    ));
    fs::create_dir(&stage)?;
    for (name, body) in &files {
        let target = stage.join(name);
        fs::create_dir_all(target.parent().ok_or("Invalid runtime destination")?)?;
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(target)?;
        file.write_all(body)?;
        file.sync_all()?;
    }
    verify(&stage, &files)?;
    fs::rename(stage, &root)?;
    verify(&root, &files)?;
    Ok(root)
}
