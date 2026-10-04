use rikui_installer::setup;
use std::fs;
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
}
