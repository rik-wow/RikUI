"""Build and verify the public Windows installer from reviewed package inputs."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import build_installer_bundle
import current_refresh
import forever_inputs
import public_installer_manifest

ROOT=Path(str(Path(__file__).resolve().parents[1]).removeprefix("\\\\?\\"))


def build(base,runtime,output,toolchain=None,executable=None):
    resolved=forever_inputs.discover(executable) if executable else forever_inputs.resolve_upstreams()
    base=forever_inputs.regular(base).resolve()
    runtime=Path(runtime).resolve()
    package=build_installer_bundle.verify_bundle(base,public=True)
    manifest=json.loads((runtime/"runtime.json").read_bytes())
    current_refresh.verify_files(runtime,manifest["files"])
    archive=forever_inputs.regular(runtime.parent/"runtime.zip")
    if toolchain and not re.fullmatch(r"\d+\.\d+\.\d+",toolchain):
        raise ValueError("Expected an exact Rust toolchain version")
    command=["cargo",*(["+"+toolchain] if toolchain else []),"build","--release","--locked",
             "--manifest-path",str(ROOT/"installer/Cargo.toml")]
    environment=dict(os.environ,RIKUI_BUNDLE=str(base),RIKUI_RUNTIME=str(archive))
    subprocess.run(command,cwd=ROOT,env=environment,check=True)
    refreshed=forever_inputs.discover(executable) if executable else forever_inputs.resolve_upstreams()
    if (resolved.get("inputs",resolved)!=refreshed.get("inputs",refreshed)):
        raise ValueError("Current inputs changed during the installer build")
    output=Path(output).absolute()
    if output.exists():raise ValueError("Public output must be a new directory")
    output.mkdir(parents=True)
    program=output/"RikUI-Setup.exe"
    shutil.copyfile(ROOT/"installer/target/release/rikui-installer.exe",program)
    return public_installer_manifest.create(package["version"],program,base,runtime,output)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("base","runtime","output"):parser.add_argument("--"+name,required=True)
    parser.add_argument("--toolchain")
    parser.add_argument("--executable")
    args=parser.parse_args()
    print(json.dumps(build(args.base,args.runtime,args.output,args.toolchain,args.executable)))
