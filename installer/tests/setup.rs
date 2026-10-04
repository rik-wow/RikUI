use rikui_installer::setup;
use std::fs;

fn completed_cache(profile: &std::path::Path) -> (std::path::PathBuf, Vec<u8>) {
    let cache = profile.join("cache");
    fs::create_dir_all(&cache).unwrap();
    let bundle = cache.join("completed.zip");
    let bytes = b"retained completed local bundle".to_vec();
    fs::write(&bundle, &bytes).unwrap();
    let sha = rikui_installer::bundle::digest(&bytes);
    let inputs = serde_json::json!({"base":"base","corpus":"corpus","roads":"roads"});
    setup::atomic_json(
        &bundle.with_extension("receipt.json"),
        &serde_json::json!({"sha256":sha,"inputs":inputs}),
    )
    .unwrap();
    setup::atomic_json(
        &cache.join("latest.json"),
        &serde_json::json!({
            "format":"rikui-local-assembly-v1","bundle":bundle,"bundleSHA256":sha,
            "bundleInputs":inputs,"corpus":cache.join("corpus"),
            "resolution":{"fingerprint":"preserved-input-identity"}
        }),
    )
    .unwrap();
    (cache, bytes)
}
#[test]
fn changing_drives_carries_completed_bundle_and_receipts_without_relabeling_inputs() {
    let profile = tempfile::tempdir().unwrap();
    let drive = tempfile::tempdir().unwrap();
    let (old, bytes) = completed_cache(profile.path());
    let original = fs::read(old.join("latest.json")).unwrap();
    setup::pause(profile.path()).unwrap();
    setup::choose_cache(profile.path(), drive.path()).unwrap();
    let target = setup::cache(profile.path()).unwrap();
    let next: serde_json::Value =
        serde_json::from_slice(&fs::read(target.join("latest.json")).unwrap()).unwrap();
    let bundle = std::path::Path::new(next["bundle"].as_str().unwrap());
    assert!(bundle.starts_with(&target));
    assert_eq!(fs::read(bundle).unwrap(), bytes);
    assert!(bundle.with_extension("receipt.json").is_file());
    assert_eq!(next["corpus"], serde_json::json!(old.join("corpus")));
    assert_eq!(
        next["resolution"]["fingerprint"],
        "preserved-input-identity"
    );
    assert_eq!(fs::read(old.join("latest.json")).unwrap(), original);
    assert!(old.join("cancel").is_file());
    assert!(target.join("cancel").is_file());
}
#[test]
fn changing_drives_preserves_existing_destination_and_unrelated_files() {
    let profile = tempfile::tempdir().unwrap();
    let drive = tempfile::tempdir().unwrap();
    let (old, _) = completed_cache(profile.path());
    let target = drive.path().join("RikUI-preparation");
    fs::create_dir_all(&target).unwrap();
    fs::write(target.join("latest.json"), b"existing receipt").unwrap();
    fs::write(drive.path().join("unrelated"), b"private").unwrap();
    setup::choose_cache(profile.path(), drive.path()).unwrap();
    assert_eq!(
        fs::read(target.join("latest.json")).unwrap(),
        b"existing receipt"
    );
    assert_eq!(
        fs::read(drive.path().join("unrelated")).unwrap(),
        b"private"
    );
    assert!(old.join("latest.json").is_file());
}
#[test]
fn corrupt_completed_bundle_does_not_change_preparation_preferences() {
    let profile = tempfile::tempdir().unwrap();
    let drive = tempfile::tempdir().unwrap();
    let (old, _) = completed_cache(profile.path());
    fs::write(old.join("completed.zip"), b"corrupted").unwrap();
    assert!(setup::choose_cache(profile.path(), drive.path()).is_err());
    assert_eq!(setup::cache(profile.path()).unwrap(), old);
    assert!(!profile.path().join("preferences.json").exists());
}
#[test]
fn active_setup_refuses_preparation_folder_changes() {
    let profile = tempfile::tempdir().unwrap();
    let drive = tempfile::tempdir().unwrap();
    let lock = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(profile.path().join("setup.lock"))
        .unwrap();
    lock.try_lock().unwrap();
    assert!(setup::choose_cache(profile.path(), drive.path()).is_err());
    assert!(!profile.path().join("preferences.json").exists());
}
#[test]
fn incomplete_work_is_retained_and_pause_is_carried_when_changing_drives() {
    let profile = tempfile::tempdir().unwrap();
    let drive = tempfile::tempdir().unwrap();
    setup::pause(profile.path()).unwrap();
    let old = setup::cache(profile.path()).unwrap();
    fs::write(old.join("preparing.json"), b"incomplete work receipt").unwrap();
    setup::choose_cache(profile.path(), drive.path()).unwrap();
    assert_eq!(
        fs::read(old.join("preparing.json")).unwrap(),
        b"incomplete work receipt"
    );
    assert!(
        setup::cache(profile.path())
            .unwrap()
            .join("cancel")
            .is_file()
    );
}
#[test]
fn preparation_folder_and_pause_preserve_existing_data() {
    let profile = tempfile::tempdir().unwrap();
    let drive = tempfile::tempdir().unwrap();
    fs::write(drive.path().join("unrelated"), "preserve").unwrap();
    setup::choose_cache(profile.path(), drive.path()).unwrap();
    let cache = setup::cache(profile.path()).unwrap();
    assert_eq!(cache, drive.path().join("RikUI-preparation"));
    setup::pause(profile.path()).unwrap();
    assert!(cache.join("cancel").is_file());
    assert_eq!(
        fs::read_to_string(drive.path().join("unrelated")).unwrap(),
        "preserve"
    );
    let details = setup::details(profile.path()).unwrap();
    let text = fs::read_to_string(details).unwrap();
    assert!(text.contains("has not produced a verified installation"));
    assert!(text.contains(&cache.display().to_string()));
    assert!(setup::choose_cache(profile.path(), std::path::Path::new("relative")).is_err());
}
#[test]
fn details_explains_verified_coverage_without_dumping_ids() {
    let profile = tempfile::tempdir().unwrap();
    setup::atomic_json(&profile.path().join("installed.json"),&serde_json::json!({
        "resolution":{"inputs":{"identity":{"build":"current-fixture"}}},
        "game":"fixture game","backup":"fixture backup",
        "coverage":{"questCounts":{"quests":50},"clientUniverse":{"clientOnly":3},
            "worlds":[{"worldMapID":0},{"worldMapID":1}],"limits":["Unknown floors remain explicit."]}
    })).unwrap();
    let text = fs::read_to_string(setup::details(profile.path()).unwrap()).unwrap();
    assert!(text.contains("50 quests have provider information"));
    assert!(text.contains("3 current client quest IDs have membership only"));
    assert!(text.contains("0, 1"));
    assert!(text.contains("Unknown floors remain explicit."));
    let mut installed: serde_json::Value =
        serde_json::from_slice(&fs::read(profile.path().join("installed.json")).unwrap()).unwrap();
    installed["coverage"]["regions"] = serde_json::json!([
        {"mapID":0,"name":"Current Coast"},
        {"mapID":1,"name":"Map 1 (name unavailable)"}
    ]);
    setup::atomic_json(&profile.path().join("installed.json"), &installed).unwrap();
    let named = fs::read_to_string(setup::details(profile.path()).unwrap()).unwrap();
    assert!(named.contains("Navigation regions prepared: Current Coast, Map 1 (name unavailable)"));
    assert!(!named.contains("Navigation regions prepared (game map IDs)"));
    assert!(named.contains("Unknown floors remain explicit."));
}
