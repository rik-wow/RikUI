use std::{env, fs, path::PathBuf};

fn main() {
    println!("cargo:rerun-if-env-changed=RIKUI_BUNDLE");
    let output = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("bundle.zip");
    if let Some(input) = env::var_os("RIKUI_BUNDLE") {
        let input = PathBuf::from(input)
            .canonicalize()
            .expect("RIKUI_BUNDLE must exist");
        println!("cargo:rerun-if-changed={}", input.display());
        fs::copy(input, output).expect("copy embedded bundle");
    } else {
        fs::write(output, []).expect("write empty development bundle");
    }
}
