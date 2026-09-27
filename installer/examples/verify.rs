use rikui_installer::{
    bundle::{Bundle, digest},
    transaction::Installer,
};
fn main() {
    if let Err(error) = verify() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
fn verify() -> rikui_installer::Result<()> {
    let path = std::env::args()
        .nth(1)
        .ok_or("bundle ZIP argument required")?;
    let bytes = std::fs::read(path)?;
    let bundle = Bundle::read(&bytes)?;
    println!(
        "Verified {} files in {} addon folders: {}",
        bundle.files.len(),
        bundle.roots().len(),
        bundle.manifest.components.join(", ")
    );
    if std::env::args().any(|arg| arg == "--install-test") {
        let game = tempfile::tempdir()?;
        std::fs::write(game.path().join("WowB.exe"), "isolated fixture")?;
        Installer::open(game.path())?.install(&bundle)?;
        for (name, entry) in &bundle.manifest.files {
            let bytes = std::fs::read(game.path().join("Interface/AddOns").join(name))?;
            if bytes.len() as u64 != entry.bytes || digest(&bytes) != entry.sha256 {
                return Err(format!("Installed file differs: {name}").into());
            }
        }
        println!("Complete isolated installation matches every payload hash.");
    }
    Ok(())
}
