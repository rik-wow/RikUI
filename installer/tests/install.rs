use rikui_installer::{
    bundle::{Bundle, digest, safe_name},
    transaction::Installer,
};
use std::{
    collections::BTreeMap,
    fs,
    io::{Cursor, Write},
};
use zip::{ZipWriter, write::SimpleFileOptions};

fn archive(entries: Vec<(String, Vec<u8>)>) -> Vec<u8> {
    let mut zip = ZipWriter::new(Cursor::new(Vec::new()));
    for (name, data) in entries {
        zip.start_file(name, SimpleFileOptions::default()).unwrap();
        zip.write_all(&data).unwrap();
    }
    zip.finish().unwrap().into_inner()
}
fn files(version: &str) -> BTreeMap<String, Vec<u8>> {
    [
        ("RikUI/RikUI.toc", version),
        ("RikUI/LICENSE", "MIT"),
        ("RikUI/generated/index.xml", "<Ui/>"),
    ]
    .into_iter()
    .map(|(k, v)| (k.to_string(), v.as_bytes().to_vec()))
    .collect()
}
fn bundle_bytes(files: BTreeMap<String, Vec<u8>>) -> Vec<u8> {
    let inventory: BTreeMap<_, _> = files
        .iter()
        .map(|(k, v)| (k, serde_json::json!({"bytes":v.len(),"sha256":digest(v)})))
        .collect();
    let manifest =
        serde_json::json!({"format":1,"version":"0.1.0","components":["RikUI"],"files":inventory});
    let mut entries: Vec<_> = files.into_iter().collect();
    entries.push(("bundle.json".into(), serde_json::to_vec(&manifest).unwrap()));
    archive(entries)
}
fn bundle(version: &str) -> Bundle {
    Bundle::read(&bundle_bytes(files(version))).unwrap()
}
fn game() -> tempfile::TempDir {
    let dir = tempfile::tempdir().unwrap();
    fs::write(dir.path().join("WowB.exe"), "fixture").unwrap();
    dir
}
#[test]
fn rejects_windows_path_aliases_and_escapes() {
    for path in [
        "../RikUI/x",
        "RikUI/../x",
        "RikUI/a:b",
        "RikUI/NUL.txt",
        "RikUI/COM1",
        "RikUI/a.",
        "RikUI/a ",
        "RikUI/a\\b",
        "RikUI//x",
        "OtherAddon/x",
        "RikUI/é.lua",
    ] {
        assert!(safe_name(path).is_err(), "{path}");
    }
    assert!(safe_name("RikUIQuestRoads_W0_P003/patch.lua").is_ok());
}
#[test]
fn rejects_case_collisions() {
    let mut source = files("one");
    source.insert("RikUI/license".into(), b"other".to_vec());
    assert!(Bundle::read(&bundle_bytes(source)).is_err());
}
#[test]
fn rejects_file_directory_collisions() {
    let mut source = files("one");
    source.insert("RikUI/generated".into(), b"file".to_vec());
    assert!(Bundle::read(&bundle_bytes(source)).is_err());
}
#[test]
fn rejects_wrong_hash_or_missing_payload() {
    let mut entries: Vec<_> = files("one").into_iter().collect();
    let inventory: BTreeMap<_, _> = entries
        .iter()
        .map(|(k, v)| (k, serde_json::json!({"bytes":v.len(),"sha256":"wrong"})))
        .collect();
    let metadata = serde_json::json!({"format":1,"version":"1","components":[],"files":inventory});
    entries.push(("bundle.json".into(), serde_json::to_vec(&metadata).unwrap()));
    assert!(Bundle::read(&archive(entries)).is_err());
    assert!(Bundle::read(&archive(vec![("bundle.json".into(), b"{}".to_vec())])).is_err());
}
#[test]
fn fresh_install_and_update_preserve_data_and_other_addons() {
    let dir = game();
    let installer = Installer::open(dir.path()).unwrap();
    installer.install(&bundle("one")).unwrap();
    let root = dir.path().join("Interface/AddOns");
    fs::create_dir_all(root.join("RikUI/generated/corpus")).unwrap();
    fs::write(root.join("RikUI/generated/corpus/data.lua"), "keep corpus").unwrap();
    fs::create_dir_all(root.join("Other")).unwrap();
    fs::write(root.join("Other/settings.lua"), "keep settings").unwrap();
    let receipt = installer.install(&bundle("two")).unwrap();
    assert_eq!(
        fs::read_to_string(root.join("RikUI/RikUI.toc")).unwrap(),
        "two"
    );
    assert_eq!(
        fs::read_to_string(root.join("RikUI/generated/corpus/data.lua")).unwrap(),
        "keep corpus"
    );
    assert_eq!(
        fs::read_to_string(root.join("Other/settings.lua")).unwrap(),
        "keep settings"
    );
    assert_eq!(
        fs::read_to_string(receipt.join("previous/RikUI/RikUI.toc")).unwrap(),
        "one"
    );
    installer.rollback().unwrap();
    assert_eq!(
        fs::read_to_string(root.join("RikUI/RikUI.toc")).unwrap(),
        "one"
    );
    assert_eq!(
        fs::read_to_string(root.join("RikUI/generated/corpus/data.lua")).unwrap(),
        "keep corpus"
    );
}
#[test]
fn concurrent_installer_is_rejected() {
    let dir = game();
    let _owner = Installer::open(dir.path()).unwrap();
    assert!(Installer::open(dir.path()).is_err());
}
#[test]
fn invalid_game_directory_is_rejected() {
    let dir = tempfile::tempdir().unwrap();
    assert!(Installer::open(dir.path()).is_err());
}
#[test]
fn recovery_restores_interrupted_directory_swap() {
    let dir = game();
    {
        Installer::open(dir.path())
            .unwrap()
            .install(&bundle("original"))
            .unwrap();
    }
    let tx = dir
        .path()
        .join("Interface/RikUI-backups/99999999999999999999");
    fs::create_dir_all(tx.join("stage")).unwrap();
    fs::create_dir_all(tx.join("previous")).unwrap();
    fs::write(tx.join("journal.json"), r#"{"roots":[["RikUI",true]]}"#).unwrap();
    fs::write(tx.join("ready"), "1").unwrap();
    let target = dir.path().join("Interface/AddOns/RikUI");
    fs::rename(&target, tx.join("previous/RikUI")).unwrap();
    fs::create_dir(&target).unwrap();
    fs::write(target.join("RikUI.toc"), "interrupted new").unwrap();
    let _installer = Installer::open(dir.path()).unwrap();
    assert_eq!(
        fs::read_to_string(target.join("RikUI.toc")).unwrap(),
        "original"
    );
    assert_eq!(
        fs::read_to_string(tx.join("interrupted/RikUI/RikUI.toc")).unwrap(),
        "interrupted new"
    );
    assert!(tx.join("recovered").is_file());
}
#[test]
fn first_install_rollback_preserves_files() {
    let dir = game();
    let installer = Installer::open(dir.path()).unwrap();
    installer.install(&bundle("one")).unwrap();
    assert!(installer.rollback().is_err());
    assert!(
        dir.path()
            .join("Interface/AddOns/RikUI/RikUI.toc")
            .is_file()
    );
}
#[test]
fn preparation_failure_keeps_existing_installation() {
    let dir = game();
    let installer = Installer::open(dir.path()).unwrap();
    installer.install(&bundle("original")).unwrap();
    let path = dir.path().join("Interface/AddOns/RikUI/media");
    fs::write(&path, "user file conflicting with directory").unwrap();
    let mut data = files("replacement");
    data.insert("RikUI/media/font.ttf".into(), b"font".to_vec());
    assert!(
        installer
            .install(&Bundle::read(&bundle_bytes(data)).unwrap())
            .is_err()
    );
    assert_eq!(
        fs::read_to_string(dir.path().join("Interface/AddOns/RikUI/RikUI.toc")).unwrap(),
        "original"
    );
}
#[test]
fn installs_multiple_owned_roots() {
    let dir = game();
    let mut data = files("one");
    data.insert("RikUIQuestRoads_W0_P003/patch.lua".into(), b"road".to_vec());
    Installer::open(dir.path())
        .unwrap()
        .install(&Bundle::read(&bundle_bytes(data)).unwrap())
        .unwrap();
    assert_eq!(
        fs::read_to_string(
            dir.path()
                .join("Interface/AddOns/RikUIQuestRoads_W0_P003/patch.lua")
        )
        .unwrap(),
        "road"
    );
}
#[test]
fn installed_byte_verification_detects_changes() {
    let dir = game();
    let installer = Installer::open(dir.path()).unwrap();
    let payload = bundle("one");
    installer.install(&payload).unwrap();
    installer.verify(&payload).unwrap();
    fs::write(
        dir.path().join("Interface/AddOns/RikUI/RikUI.toc"),
        "tampered",
    )
    .unwrap();
    assert!(installer.verify(&payload).is_err());
}
#[test]
fn rollback_retires_roots_introduced_by_the_update_into_backup() {
    let dir = game();
    let installer = Installer::open(dir.path()).unwrap();
    installer.install(&bundle("one")).unwrap();
    let mut data = files("two");
    data.insert("RikUIQuestRoads_W0_P003/patch.lua".into(), b"road".to_vec());
    installer
        .install(&Bundle::read(&bundle_bytes(data)).unwrap())
        .unwrap();
    let rollback = installer.rollback().unwrap();
    assert!(
        !dir.path()
            .join("Interface/AddOns/RikUIQuestRoads_W0_P003")
            .exists()
    );
    assert_eq!(
        fs::read(rollback.join("previous/RikUIQuestRoads_W0_P003/patch.lua")).unwrap(),
        b"road"
    );
    assert_eq!(
        fs::read(dir.path().join("Interface/AddOns/RikUI/RikUI.toc")).unwrap(),
        b"one"
    );
}
#[test]
fn release_executable_name_does_not_require_the_beta_layout() {
    let dir = tempfile::tempdir().unwrap();
    fs::write(dir.path().join("Wow.exe"), b"fixture").unwrap();
    let installer = Installer::open(dir.path()).unwrap();
    installer.install(&bundle("one")).unwrap();
}
