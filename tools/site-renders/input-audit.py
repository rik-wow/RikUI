"""Inspect generated input provenance without using payloads as current evidence."""
import re
from pathlib import Path
root=Path(__file__).resolve().parents[2]
for name in ("generated/corpus/catalog.lua","generated/roads/manifest.json","generated/roads/roads.lua","generated/roads/roads.xml"):
 path=root/name
 if not path.exists():continue
 text=path.read_text(encoding="utf-8")
 print(name,"bytes",path.stat().st_size)
 for pattern in (r".{0,60}(?:build|Build|version|Version|provenance|client|Client|source|Source).{0,180}",):
  matches=re.findall(pattern,text)
  print("\n".join(matches[:12]))
