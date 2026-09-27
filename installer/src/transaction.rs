use crate::{
    Result,
    bundle::{Bundle, valid_root},
};
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};
#[derive(Serialize, Deserialize)]
struct Journal {
    roots: Vec<(String, bool)>,
}
pub fn normal(path: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(path)?;
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        if metadata.file_attributes() & 0x400 != 0 {
            return Err(format!("Junction/reparse point: {}", path.display()).into());
        }
    }
    if metadata.file_type().is_symlink() {
        return Err(format!("Symlink: {}", path.display()).into());
    }
    Ok(())
}
fn ancestors(path: &Path) -> Result<()> {
    for part in path.ancestors() {
        if part.exists() {
            normal(part)?;
        }
    }
    Ok(())
}
pub fn game_root(path: &Path) -> Result<PathBuf> {
    if !path.is_absolute() {
        return Err("Choose an absolute game folder".into());
    }
    ancestors(path)?;
    if !path.join("WowB.exe").is_file() {
        return Err("Select the Forever client folder containing WowB.exe".into());
    }
    normal(&path.join("WowB.exe"))?;
    Ok(path.canonicalize()?)
}
fn write_new(path: &Path, bytes: &[u8]) -> Result<()> {
    let mut file = OpenOptions::new().write(true).create_new(true).open(path)?;
    file.write_all(bytes)?;
    file.sync_all()?;
    Ok(())
}
fn copy_tree(source: &Path, destination: &Path) -> Result<()> {
    normal(source)?;
    fs::create_dir(destination)?;
    for entry in fs::read_dir(source)? {
        let entry = entry?;
        let path = entry.path();
        normal(&path)?;
        let target = destination.join(entry.file_name());
        if path.is_dir() {
            copy_tree(&path, &target)?;
        } else if path.is_file() {
            fs::copy(&path, &target)?;
            OpenOptions::new().write(true).open(&target)?.sync_all()?;
        } else {
            return Err("Unsupported filesystem entry".into());
        }
    }
    Ok(())
}
pub struct Installer {
    addons: PathBuf,
    history: PathBuf,
    _lock: File,
}
impl Installer {
    pub fn open(game: &Path) -> Result<Self> {
        let game = game_root(game)?;
        let addons = game.join("Interface/AddOns");
        let history = game.join("Interface/RikUI-backups");
        ancestors(&addons)?;
        ancestors(&history)?;
        fs::create_dir_all(&addons)?;
        fs::create_dir_all(&history)?;
        let lock_path = history.join("installer.lock");
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
            .map_err(|_| "Another RikUI installer is using this game folder")?;
        let installer = Self {
            addons,
            history,
            _lock: lock,
        };
        installer.recover()?;
        Ok(installer)
    }
    pub fn install(&self, bundle: &Bundle) -> Result<PathBuf> {
        let (transaction, journal) = self.begin(bundle.roots().into_iter().collect())?;
        let stage = transaction.join("stage");
        for (root, existed) in &journal.roots {
            if *existed {
                copy_tree(&self.addons.join(root), &stage.join(root))?;
            } else {
                fs::create_dir(stage.join(root))?;
            }
        }
        for (name, bytes) in &bundle.files {
            let path = stage.join(name);
            fs::create_dir_all(path.parent().ok_or("Invalid destination")?)?;
            if path.exists() {
                normal(&path)?;
            }
            let mut output = File::create(path)?;
            output.write_all(bytes)?;
            output.sync_all()?;
        }
        write_new(
            &transaction.join("bundle.json"),
            &serde_json::to_vec_pretty(&bundle.manifest)?,
        )?;
        self.commit(&transaction, &journal)?;
        Ok(transaction)
    }
    fn begin(&self, roots: Vec<String>) -> Result<(PathBuf, Journal)> {
        let mut entries = Vec::new();
        for root in roots {
            if !valid_root(&root) {
                return Err("Invalid transaction root".into());
            }
            let path = self.addons.join(&root);
            if path.exists() {
                normal(&path)?;
            }
            entries.push((root, path.exists()));
        }
        let id = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
        let transaction = self.history.join(format!("{id:020}"));
        fs::create_dir(&transaction)?;
        fs::create_dir(transaction.join("stage"))?;
        fs::create_dir(transaction.join("previous"))?;
        let journal = Journal { roots: entries };
        write_new(
            &transaction.join("journal.json"),
            &serde_json::to_vec(&journal)?,
        )?;
        Ok((transaction, journal))
    }
    fn commit(&self, transaction: &Path, journal: &Journal) -> Result<()> {
        write_new(&transaction.join("ready"), b"1")?;
        if let Err(error) = self.swap(transaction, journal) {
            self.restore(transaction, journal).map_err(|recovery| {
                format!(
                    "Install failed: {error}. Recovery failed: {recovery}. Keep {}",
                    transaction.display()
                )
            })?;
            return Err(error);
        }
        Ok(())
    }
    fn swap(&self, transaction: &Path, journal: &Journal) -> Result<()> {
        for (root, existed) in &journal.roots {
            let target = self.addons.join(root);
            if *existed {
                fs::rename(&target, transaction.join("previous").join(root))?;
            }
            fs::rename(transaction.join("stage").join(root), target)?;
        }
        write_new(&transaction.join("complete"), b"1")
    }
    fn restore(&self, transaction: &Path, journal: &Journal) -> Result<()> {
        let failed = transaction.join("interrupted");
        fs::create_dir_all(&failed)?;
        for (root, existed) in journal.roots.iter().rev() {
            let target = self.addons.join(root);
            let previous = transaction.join("previous").join(root);
            let staged = transaction.join("stage").join(root);
            if !staged.exists() && target.exists() && (!*existed || previous.exists()) {
                fs::rename(&target, failed.join(root))?;
            }
            if previous.exists() {
                fs::rename(previous, target)?;
            }
        }
        write_new(&transaction.join("recovered"), b"1")?;
        Ok(())
    }
    fn journal(&self, transaction: &Path) -> Result<Journal> {
        normal(transaction)?;
        let path = transaction.join("journal.json");
        normal(&path)?;
        let journal: Journal = serde_json::from_slice(&fs::read(path)?)?;
        if journal.roots.is_empty() || journal.roots.iter().any(|(r, _)| !valid_root(r)) {
            return Err("Invalid recovery journal".into());
        }
        for (root, _) in &journal.roots {
            for base in ["stage", "previous", "interrupted"] {
                ancestors(&transaction.join(base).join(root))?;
            }
            ancestors(&self.addons.join(root))?;
        }
        Ok(journal)
    }
    fn recover(&self) -> Result<()> {
        for entry in fs::read_dir(&self.history)? {
            let path = entry?.path();
            if !path.is_dir() {
                continue;
            }
            normal(&path)?;
            if path.join("ready").exists()
                && !path.join("complete").exists()
                && !path.join("recovered").exists()
            {
                self.restore(&path, &self.journal(&path)?)?;
            }
        }
        Ok(())
    }
    pub fn rollback(&self) -> Result<PathBuf> {
        let mut candidates = Vec::new();
        for entry in fs::read_dir(&self.history)? {
            let path = entry?.path();
            if path.join("complete").is_file()
                && !path.join("rolled-back").exists()
                && !path.join("rollback").exists()
            {
                candidates.push(path);
            }
        }
        candidates.sort();
        let original = candidates
            .last()
            .ok_or("No previous installation to restore")?;
        let old = self.journal(original)?;
        let roots: Vec<_> = old
            .roots
            .iter()
            .filter(|(_, existed)| *existed)
            .map(|(r, _)| r.clone())
            .collect();
        if roots.is_empty() {
            return Err("First install: no previous version exists. Files are preserved.".into());
        }
        let (transaction, journal) = self.begin(roots)?;
        write_new(&transaction.join("rollback"), b"1")?;
        for (root, _) in &journal.roots {
            copy_tree(
                &original.join("previous").join(root),
                &transaction.join("stage").join(root),
            )?;
        }
        self.commit(&transaction, &journal)?;
        write_new(&original.join("rolled-back"), b"1")?;
        Ok(transaction)
    }
}
