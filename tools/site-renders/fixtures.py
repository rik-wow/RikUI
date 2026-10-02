"""Fixture modules and scenario script assembly; standard library only so the gate can rebuild a script.

A capture's Lua script is `fixtures/core.lua`, the fixture modules the scenario reaches (directly or
through other modules), the render preludes, the scenario's fixture calls and its own Lua. A module joins
a script only when the scenario uses a name it defines, so editing one module leaves every other
scenario's script, and therefore its capture, untouched."""
import json
import re
from pathlib import Path

FIXTURES = Path(__file__).resolve().parent
MODULES = FIXTURES / "fixtures"
WORLDS = FIXTURES / "worlds"
CORE = "core"
# Globals the render pipeline defines ahead of the fixtures, not fixture functions.
PRELUDE_NAMES = {"RikRenderWorld", "RikRenderClient"}
NAME = re.compile(r"\bRikRender\w+")
DEFINITION = re.compile(r"^(?:function (RikRender\w+)|(RikRender\w+)\s*=)", re.M)
def scan_lua(text):
    """Split Lua into code and string literals: comments (line and long) are dropped, strings (quoted and
    long-bracket) are collected, and the code keeps a placeholder where each string stood. An apostrophe
    in a comment is a comment, not a string."""
    code, strings, i, n = [], [], 0, len(text)
    while i < n:
        two = text[i:i + 2]
        if two == "--":
            long = re.match(r"--\[(=*)\[", text[i:])
            if long:
                close = text.find("]" + long.group(1) + "]", i + long.end())
                i = n if close < 0 else close + len(long.group(1)) + 2
            else:
                end = text.find("\n", i)
                i = n if end < 0 else end
            continue
        long = re.match(r"\[(=*)\[", text[i:])
        if long:
            close = text.find("]" + long.group(1) + "]", i + long.end())
            end = n if close < 0 else close
            strings.append(text[i + long.end():end])
            code.append('""')
            i = n if close < 0 else close + len(long.group(1)) + 2
            continue
        if text[i] in "\"'":
            quote, j = text[i], i + 1
            while j < n and text[j] != quote:
                j += 2 if text[j] == "\\" else 1
            strings.append(text[i + 1:j])
            code.append('""')
            i = j + 1
            continue
        code.append(text[i])
        i += 1
    return "".join(code), strings

def references(text):
    """Fixture names the code reaches; holder frames are named in string literals, which do not count."""
    return set(NAME.findall(scan_lua(text)[0])) - PRELUDE_NAMES

def holders(text):
    """Frames a script creates by name ("RikRenderBars" in RikRenderGroup) and then reaches as globals."""
    return set(NAME.findall(" ".join(scan_lua(text)[1])))

def holder_providers(modules):
    table = {}
    for module, text in modules.items():
        for name in holders(text):
            table.setdefault(name, module)
    return table

def load_modules():
    """Every fixture module by name, in file order (core first)."""
    modules = {path.stem: path.read_text(encoding="utf-8") for path in sorted(MODULES.glob("*.lua"))}
    if CORE not in modules:
        raise RuntimeError("Fixture module core.lua is missing")
    return modules

def definitions(text):
    return {a or b for a, b in DEFINITION.findall(text)}

def providers(modules):
    table = {}
    for module, text in modules.items():
        for name in definitions(text):
            if name in table:
                raise RuntimeError(f"Fixture {name} is defined in both {table[name]} and {module}")
            table[name] = module
    return table

def scenario_text(case):
    return "\n".join([*case.get("fixtures", []), case.get("lua", ""), case.get("assertLua", ""),
                      (case.get("sequence") or {}).get("apply", "")])

def resolve(case, modules):
    """The modules a scenario needs, in file order: core, then the transitive closure of every fixture it names."""
    table, created = providers(modules), holder_providers(modules)
    text = scenario_text(case)
    own = holders(text)
    wanted, queue = {CORE}, []
    for name in sorted(references(text)):
        if name in table:
            queue.append(table[name])
        elif name in created:
            queue.append(created[name])
        elif name not in own:
            raise RuntimeError(f"{case.get('id', '?')}: unknown fixture {name}")
    while queue:
        module = queue.pop()
        if module in wanted:
            continue
        wanted.add(module)
        for name in references(modules[module]):
            provider = table.get(name) or created.get(name)
            if provider and provider not in wanted:
                queue.append(provider)
    return [name for name in modules if name in wanted]

def lua_literal(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'

def client_prelude(client_version):
    """The verified installed client, so fixtures can answer its build where the simulator answers its own."""
    if not client_version:
        return "RikRenderClient = nil\n"
    version, build = client_version.rsplit(".", 1)
    return "RikRenderClient = { version = %s, build = %s }\n" % (lua_literal(version), lua_literal(build))

def world_prelude(case):
    """The plate's named creatures and their screen positions, so fixtures can put plates over them."""
    if not case.get("world"):
        return "RikRenderWorld = nil\n"
    record = json.loads((WORLDS / (case["world"]["plate"] + ".json")).read_text(encoding="utf-8"))
    actors = []
    for actor in record.get("actors", []):
        flags = ", ".join(f'{flag} = true' for flag in actor.get("flags", []))
        actors.append("{ name = %s, level = %s, kind = %s, x = %d, y = %d, distance = %.1f%s }" % (
            lua_literal(actor.get("name") or ""), actor.get("level") or "nil", lua_literal(actor.get("kind", "creature")),
            actor["screen"]["x"], actor["screen"]["y"], actor.get("distance", 0), (", " + flags) if flags else ""))
    return ("RikRenderWorld = { plate = %s, width = %d, height = %d, actors = {\n    %s\n} }\n"
            % (lua_literal(record["name"]), record["width"], record["height"], ",\n    ".join(actors)))

def scenario_script(case, modules, client_version, value=None):
    """The complete Lua a capture runs. The same inputs always give the same text, so its digest is the
    capture's script provenance."""
    common = "\n\n".join(modules[name] for name in resolve(case, modules))
    fixtures = client_prelude(client_version) + world_prelude(case) + "\n".join(case.get("fixtures", []))
    body = case.get("lua", "")
    if case.get("profile") is not None:
        body = "-- Startup profile: " + json.dumps(case["profile"], sort_keys=True) + "\n" + body
    # The setting is applied first, so the scenario composes its frame the way a player would see it.
    if value is not None:
        body = case["sequence"]["apply"].replace("VALUE", lua_literal(value)) + "\n" + body
    root = (case.get("sequence") or {}).get("frames", {}).get(str(value), case["frame"])
    checks = case.get("assertLua", "") + "\nRikRenderCheck(" + root + ")\n"
    return common + "\n" + fixtures + "\n" + body + "\nC_Timer.After(0, function()\n" + checks + "end)\n"
