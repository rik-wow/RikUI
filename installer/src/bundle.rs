use crate::Result;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    io::{Cursor, Read},
    path::Path,
};

const MAX_BYTES: u64 = 2 * 1024 * 1024 * 1024;
const MAX_FILES: usize = 65536;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Entry {
    pub bytes: u64,
    pub sha256: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Manifest {
    pub format: u32,
    pub version: String,
    pub components: Vec<String>,
    pub files: BTreeMap<String, Entry>,
}

pub struct Bundle {
    pub manifest: Manifest,
    pub files: BTreeMap<String, Vec<u8>>,
}

pub fn digest(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

pub fn valid_root(root: &str) -> bool {
    if root == "RikUI" {
        return true;
    }
    let Some(rest) = root.strip_prefix("RikUIQuestRoads_W") else {
        return false;
    };
    let Some((world, page)) = rest.split_once("_P") else {
        return false;
    };
    !world.is_empty()
        && world.bytes().all(|c| c.is_ascii_digit())
        && page.len() == 3
        && page.bytes().all(|c| c.is_ascii_digit())
}

pub fn safe_name(name: &str) -> Result<()> {
    let parts: Vec<_> = name.split('/').collect();
    if parts.len() < 2 || !valid_root(parts[0]) {
        return Err("Unexpected addon path".into());
    }
    for part in parts {
        let stem = part.split('.').next().unwrap_or("").to_ascii_uppercase();
        let reserved = ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"].contains(&stem.as_str())
            || ["COM", "LPT"].iter().any(|prefix| {
                stem.strip_prefix(prefix).is_some_and(|n| {
                    ["1", "2", "3", "4", "5", "6", "7", "8", "9", "¹", "²", "³"].contains(&n)
                })
            });
        if part.is_empty()
            || part == "."
            || part == ".."
            || part.ends_with(['.', ' '])
            || !part.is_ascii()
            || reserved
            || part
                .chars()
                .any(|c| c.is_control() || "<>:\"\\|?*".contains(c))
        {
            return Err(format!("Unsafe package path: {name}").into());
        }
    }
    Ok(())
}

impl Bundle {
    pub fn read(bytes: &[u8]) -> Result<Self> {
        let mut archive = zip::ZipArchive::new(Cursor::new(bytes))?;
        if archive.len() > MAX_FILES {
            return Err("Too many package files".into());
        }
        let mut files = BTreeMap::new();
        let mut folded = BTreeSet::new();
        let mut total = 0u64;
        for index in 0..archive.len() {
            let mut member = archive.by_index(index)?;
            let name = member.name().to_owned();
            if name != "bundle.json" {
                safe_name(&name)?;
            }
            if member.is_dir()
                || member.is_symlink()
                || member.encrypted()
                || member
                    .unix_mode()
                    .is_some_and(|m| m & 0o170000 != 0 && m & 0o170000 != 0o100000)
                || !folded.insert(name.to_ascii_lowercase())
            {
                return Err("Invalid or duplicate archive member".into());
            }
            total = total
                .checked_add(member.size())
                .ok_or("Package size overflow")?;
            if total > MAX_BYTES {
                return Err("Package exceeds 2 GiB".into());
            }
            let limit = member.size() + 1;
            let mut data = Vec::new();
            (&mut member).take(limit).read_to_end(&mut data)?;
            if data.len() as u64 != member.size() {
                return Err("Archive size mismatch".into());
            }
            files.insert(name, data);
        }
        Self::validate(files)
    }

    fn validate(mut files: BTreeMap<String, Vec<u8>>) -> Result<Self> {
        let metadata = files
            .remove("bundle.json")
            .ok_or("Missing bundle manifest")?;
        let manifest: Manifest = serde_json::from_slice(&metadata)?;
        if manifest.format != 1
            || manifest.version.is_empty()
            || manifest.version.len() > 64
            || manifest.files.len() != files.len()
        {
            return Err("Invalid bundle manifest".into());
        }
        let folded: BTreeSet<_> = files.keys().map(|n| n.to_ascii_lowercase()).collect();
        for (name, entry) in &manifest.files {
            safe_name(name)?;
            let data = files.get(name).ok_or("Missing payload")?;
            if entry.bytes != data.len() as u64 || entry.sha256 != digest(data) {
                return Err(format!("Integrity check failed: {name}").into());
            }
            for parent in Path::new(name).ancestors().skip(1) {
                if folded.contains(
                    &parent
                        .to_string_lossy()
                        .replace(std::path::MAIN_SEPARATOR, "/")
                        .to_ascii_lowercase(),
                ) {
                    return Err("Package file/directory collision".into());
                }
            }
        }
        for name in [
            "RikUI/RikUI.toc",
            "RikUI/LICENSE",
            "RikUI/generated/index.xml",
        ] {
            if !files.contains_key(name) {
                return Err(format!("Missing required file: {name}").into());
            }
        }
        Ok(Self { manifest, files })
    }

    pub fn roots(&self) -> BTreeSet<String> {
        self.files
            .keys()
            .map(|p| p.split('/').next().unwrap().to_owned())
            .collect()
    }
}
