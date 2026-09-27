"""Build the native installer and collect dependency license texts alongside it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def build(bundle, output):
    bundle, output = Path(bundle).resolve(), Path(output).absolute()
    if output.exists():
        raise ValueError("Choose a new output directory")
    env = dict(os.environ, RIKUI_BUNDLE=str(bundle))
    manifest = ROOT / "installer/Cargo.toml"
    subprocess.run(["cargo", "run", "--release", "--locked", "--manifest-path", str(manifest),
                    "--example", "verify", "--", str(bundle)], check=True, env=env)
    subprocess.run(["cargo", "build", "--release", "--locked", "--manifest-path", str(manifest)], check=True, env=env)
    metadata = json.loads(subprocess.check_output(
        ["cargo", "metadata", "--locked", "--format-version", "1", "--filter-platform", "x86_64-pc-windows-msvc", "--manifest-path", str(manifest)], env=env))
    nodes = {node["id"]: node for node in metadata["resolve"]["nodes"]}
    included, pending = set(), [metadata["resolve"]["root"]]
    while pending:
        identity = pending.pop()
        if identity in included:
            continue
        included.add(identity)
        pending.extend(dep["pkg"] for dep in nodes[identity]["deps"]
                       if any(kind["kind"] != "dev" for kind in dep["dep_kinds"]))
    notices = []
    for package in sorted(metadata["packages"], key=lambda p: p["name"]):
        if package["source"] is None or package["id"] not in included:
            continue
        root = Path(package["manifest_path"]).parent
        license_files = sorted(p for p in root.iterdir() if p.is_file()
                               and p.name.upper().startswith(("LICENSE", "COPYING", "NOTICE", "UNLICENSE")))
        notices.append("\n## " + package["name"] + " " + package["version"] + "\n")
        notices.append("Declared license: " + (package["license"] or "see source") + "\n")
        notices.append("Source: " + (package.get("repository") or package["source"]) + "\n")
        if not license_files:
            raise ValueError("Missing dependency license text: " + package["name"])
        for path in license_files:
            notices.append("\n### " + path.name + "\n\n" + path.read_text(encoding="utf-8"))
    output.mkdir(parents=True)
    target = output / "RikUI-Setup.exe"
    shutil.copyfile(Path(metadata["target_directory"]) / "release/rikui-installer.exe", target)
    shutil.copyfile(ROOT / "LICENSE", output / "LICENSE.txt")
    shutil.copyfile(ROOT / "docs/corpus-licensing.md", output / "DATA-LICENSING.md")
    (output / "THIRD-PARTY-NOTICES.md").write_text("# Installer dependency licenses\n" + "\n".join(notices), encoding="utf-8")
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    (output / "SHA256SUMS").write_text(digest + "  RikUI-Setup.exe\n", encoding="ascii")
    print(json.dumps({"executable": str(target), "bytes": target.stat().st_size, "sha256": digest,
                      "bundleSHA256": hashlib.sha256(bundle.read_bytes()).hexdigest()}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    build(args.bundle, args.output)
