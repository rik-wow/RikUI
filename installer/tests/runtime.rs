use rikui_installer::{bundle::digest, runtime};
use std::{
    collections::BTreeMap,
    fs,
    io::{Cursor, Write},
};
use zip::{ZipWriter, write::SimpleFileOptions};
fn payload(extra: Option<(&str, &[u8])>) -> Vec<u8> {
    let mut files: BTreeMap<String, Vec<u8>> = [
        "python/python.exe",
        "node/node.exe",
        "extractor/TACTTool.exe",
        "tools/local_assembly.py",
    ]
    .into_iter()
    .map(|name| (name.to_owned(), b"fixture".to_vec()))
    .collect();
    if let Some((name, body)) = extra {
        files.insert(name.into(), body.to_vec());
    }
    let rows:Vec<_>=files.iter().map(|(path,body)|serde_json::json!({"path":path,"bytes":body.len(),"sha256":digest(body)})).collect();
    files.insert(
        "runtime.json".into(),
        serde_json::to_vec(&serde_json::json!({"format":"rikui-local-runtime-v1","files":rows}))
            .unwrap(),
    );
    let mut zip = ZipWriter::new(Cursor::new(Vec::new()));
    for (name, body) in files {
        zip.start_file(name, SimpleFileOptions::default()).unwrap();
        zip.write_all(&body).unwrap();
    }
    zip.finish().unwrap().into_inner()
}
#[test]
fn extracts_and_reuses_verified_bytes() {
    let dir = tempfile::tempdir().unwrap();
    let bytes = payload(None);
    let one = runtime::ensure(&bytes, dir.path()).unwrap();
    assert_eq!(runtime::ensure(&bytes, dir.path()).unwrap(), one);
    assert_eq!(fs::read(one.join("python/python.exe")).unwrap(), b"fixture");
}
#[test]
fn changed_runtime_is_retained_and_replaced() {
    let dir = tempfile::tempdir().unwrap();
    let bytes = payload(None);
    let root = runtime::ensure(&bytes, dir.path()).unwrap();
    fs::write(root.join("python/python.exe"), "changed").unwrap();
    runtime::ensure(&bytes, dir.path()).unwrap();
    assert_eq!(
        fs::read(root.join("python/python.exe")).unwrap(),
        b"fixture"
    );
    let old = fs::read_dir(dir.path())
        .unwrap()
        .map(|row| row.unwrap().path())
        .find(|path| {
            path.file_name()
                .unwrap()
                .to_string_lossy()
                .starts_with("retained-")
        })
        .unwrap();
    assert_eq!(fs::read(old.join("python/python.exe")).unwrap(), b"changed");
}
#[test]
fn unlisted_runtime_code_is_rejected_on_reuse() {
    let dir = tempfile::tempdir().unwrap();
    let bytes = payload(None);
    let root = runtime::ensure(&bytes, dir.path()).unwrap();
    fs::write(root.join("python/unlisted.pth"), "unexpected").unwrap();
    runtime::ensure(&bytes, dir.path()).unwrap();
    assert!(!root.join("python/unlisted.pth").exists());
    assert!(fs::read_dir(dir.path()).unwrap().count() > 1);
}
#[test]
fn unsafe_aliases_and_case_collisions_fail_before_extraction() {
    for name in [
        "../escape",
        "python/NUL.txt",
        "python/name.",
        "python/a:b",
        "python/PYTHON.exe",
    ] {
        let dir = tempfile::tempdir().unwrap();
        assert!(
            runtime::ensure(&payload(Some((name, b"x"))), dir.path()).is_err(),
            "{name}"
        );
        assert_eq!(fs::read_dir(dir.path()).unwrap().count(), 0);
    }
}
