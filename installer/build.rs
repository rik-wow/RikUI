use std::{env, fs, path::PathBuf};
fn main() {
    println!("cargo:rerun-if-changed=app.manifest");
    if env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc") {
        let manifest =
            PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("Cargo manifest directory"))
                .join("app.manifest");
        println!("cargo:rustc-link-arg-bin=rikui-installer=/MANIFEST:EMBED");
        println!(
            "cargo:rustc-link-arg-bin=rikui-installer=/MANIFESTINPUT:{}",
            manifest.display()
        );
    }
    for (variable, name) in [
        ("RIKUI_BUNDLE", "bundle.zip"),
        ("RIKUI_RUNTIME", "runtime.zip"),
    ] {
        println!("cargo:rerun-if-env-changed={variable}");
        let output =
            PathBuf::from(env::var_os("OUT_DIR").expect("Cargo output directory")).join(name);
        if let Some(input) = env::var_os(variable) {
            let input = PathBuf::from(input)
                .canonicalize()
                .expect("Embedded input must exist");
            println!("cargo:rerun-if-changed={}", input.display());
            fs::copy(input, output).expect("Copy embedded package");
        } else {
            fs::write(output, []).expect("Write empty development package");
        }
    }
}
