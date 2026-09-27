"""Required source and UI evidence checks for the project."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
for script in ("tests/check_manifest.py", "tools/site-renders/check.py"):
    subprocess.run([sys.executable, script], cwd=root, check=True)

