"""Static checks on gui.lua.

gui.lua cannot be loaded outside REAPER: it needs Lokasenna and a real gfx
window. These checks read it as text instead, and each one exists because the
matching bug actually happened.
"""
import re
import pathlib
import sys

# Resolved from this file's own location, so the tools keep working
# wherever the repo lives.
ROOT = pathlib.Path(__file__).resolve().parent.parent / "RenderSmith"
GUI = (ROOT / "src" / "gui.lua").read_text(encoding="utf-8")
LINES = GUI.split("\n")

passed, failed = 0, 0


def check(cond, label):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print("FAIL: " + label)


def body_of(func_name, text):
    """The body of a column-0 function, up to its column-0 `end`.

    Stopping at the first column-0 `end` matters: an earlier version ran to
    the next column-0 `function`, which swallowed everything in between and
    made the reachability check pass when it should have failed.
    """
    lines = text.split("\n")
    start = None
    for i, line in enumerate(lines):
        if re.match(rf"^(?:local\s+)?function\s+{re.escape(func_name)}\s*\(", line):
            start = i
            break
    if start is None:
        return None
    out = []
    for line in lines[start + 1:]:
        if line == "end":
            break
        out.append(line)
    return "\n".join(out)


# 1. Element names must be unique. GUI.New silently DELETES an element with a
# duplicate name (Core.lua:747), and deleting one created before the gfx
# window exists calls GUI.FreeBuffer(nil), which crashes at Core.lua:660.

static_names = re.findall(r'GUI\.New\(\s*"([^"]+)"', GUI)
dupes = {n for n in static_names if static_names.count(n) > 1}
check(not dupes, f"element names are unique (duplicates: {sorted(dupes)})")

# 2. A dynamically built name must not collide with a static one. This is how
# a generated lbl_wc<n> once shadowed another element and crashed the window.

dynamic_prefixes = re.findall(r'GUI\.New\(\s*"([^"]+)"\s*\.\.', GUI)
collisions = []
for prefix in set(dynamic_prefixes):
    for name in static_names:
        if name != prefix and name.startswith(prefix):
            rest = name[len(prefix):]
            if rest.isdigit():
                collisions.append((prefix, name))
check(not collisions,
      f"no generated name shadows a static one (collisions: {collisions})")

# 3. The tab strip's label count must equal the number of z-sets. Tabs
# update_sets does `for _, z in pairs(z_sets[state])`, so a 4th tab with only
# 3 sets indexes nil and throws the same "bad argument to 'for iterator'".

tab_opts = re.search(r'GUI\.New\(\s*"tabs"\s*,\s*"Tabs".*?"([^"]+)"\s*,\s*\d+\s*\)', GUI)
check(tab_opts is not None, "the tab strip is declared")
labels = tab_opts.group(1).split(",") if tab_opts else []

sets_call = re.search(r"update_sets\(\s*\{(.*?)\}\s*\)", GUI, re.S)
check(sets_call is not None, "update_sets is called")
z_sets = re.findall(r"\{([^{}]*)\}", sets_call.group(1)) if sets_call else []

check(len(labels) == len(z_sets),
      f"tab labels match z-sets ({len(labels)} labels, {len(z_sets)} sets)")

# 4. Every z-layer named in a z-set must actually hold elements, and every
# layer holding elements must be reachable: either in a set, or driven
# explicitly through GUI.elms_hide.

declared_z = set()
for m in re.finditer(r'GUI\.New\(\s*"[^"]+"\s*,\s*"[^"]+"\s*,\s*(\d+)', GUI):
    declared_z.add(int(m.group(1)))

set_z = set()
for s in z_sets:
    for n in re.findall(r"\d+", s):
        set_z.add(int(n))

check(set_z <= declared_z,
      f"every z-set layer has elements (missing: {sorted(set_z - declared_z)})")

hidden_z = {int(n) for n in re.findall(r"GUI\.elms_hide\[(\d+)\]", GUI)}
# z=1 is the always-visible tab bar, so it belongs to neither group.
unreachable = declared_z - set_z - hidden_z - {1}
check(not unreachable,
      f"no z-layer is unreachable (orphans: {sorted(unreachable)})")

check(14 in declared_z, "the License tab's layer (z=14) holds elements")
check(14 in set_z, "the License tab's layer is in a tab set")

# 5. Every refresh_* helper must be reachable at startup. A control created
# with a placeholder caption stays blank until its refresh runs, which is how
# the UCS button drew empty until it was clicked.

start_body = body_of("gui_start", GUI)
check(start_body is not None, "gui_start is found")
def block_after(marker, text):
    """Text from `marker` to the next column-0 `end`, exclusive.

    Slicing to end of file instead swallowed gui_start, so "called somewhere
    in GUI.func" matched helpers that in fact only ran at startup, and the
    startup-reachability check stopped meaning anything.
    """
    if marker not in text:
        return ""
    rest = text[text.index(marker):].split("\n")
    out = []
    for line in rest[1:]:
        if line == "end":
            break
        out.append(line)
    return "\n".join(out)


func_body = block_after("GUI.func = function()", GUI)
check(func_body != "" and "gui_start" not in func_body,
      "GUI.func's body is cut at its own end, not at end of file")

refreshers = set(re.findall(r"^(?:local\s+)?function\s+(refresh_\w+)\s*\(", GUI, re.M))
check(len(refreshers) > 0, "refresh_* helpers exist")

unreached = []
for name in sorted(refreshers):
    in_start = start_body is not None and (name + "(") in start_body
    in_func = (name + "(") in func_body
    # Reached indirectly by another helper that is itself reached at startup.
    indirect = False
    for other in refreshers:
        if other == name:
            continue
        ob = body_of(other, GUI)
        if ob and (name + "(") in ob and start_body and (other + "(") in start_body:
            indirect = True
    if not (in_start or in_func or indirect):
        unreached.append(name)
check(not unreached, f"every refresh_* runs at startup (never reached: {unreached})")

check(start_body is not None and "refresh_license()" in start_body,
      "refresh_license runs at startup, not only on click")
check(start_body is not None and "license_tick()" in start_body,
      "license_tick runs at startup")

# 6. A GUI.New callback created before a file-level `local` is declared closes
# over a nil global and fails only when clicked.

local_decls = {}
for i, line in enumerate(LINES):
    m = re.match(r"^local\s+(?:function\s+)?(\w+)", line)
    if m and m.group(1) not in local_decls:
        local_decls[m.group(1)] = i

early_use = []
for name, decl_line in local_decls.items():
    if len(name) < 3:
        continue
    for i, line in enumerate(LINES[:decl_line]):
        if line.lstrip().startswith("--"):
            continue
        if re.search(rf"\b{re.escape(name)}\b", line):
            early_use.append((name, i + 1, decl_line + 1))
            break
check(not early_use,
      f"no file-local is referenced before its declaration ({early_use})")

# 7. The rename left nothing behind.

check("open_in_file_browser" not in GUI, "open_in_file_browser is fully renamed")
check("open_external" in GUI, "open_external exists")
check("RegionForge" not in GUI, "gui.lua no longer names the old product")
check('GUI.name   = RC.PRODUCT_NAME' in GUI, "the window title reads the config constant")

# 8. The license gate must sit on every action entry point.

regions = (ROOT / "src" / "regions.lua").read_text(encoding="utf-8")
render = (ROOT / "src" / "render.lua").read_text(encoding="utf-8")

cr = body_of("create_regions", regions)
check(cr is not None and "license_require()" in cr,
      "create_regions is gated")

rff = body_of("render_from_folders", render)
check(rff is not None and "license_require()" in rff,
      "render_from_folders is gated")
# Gated before it creates anything: refusing later would leave stray regions.
check(rff is not None
      and rff.index("license_require()") < rff.index("create_regions_from_selection"),
      "render_from_folders is gated before it creates regions")

rq = body_of("render_queue", render)
check(rq is not None and "license_require()" in rq,
      "render_queue is gated as the backstop")

check("license_state().status" in GUI, "GUI.func checks the license state")
check(re.search(r'GUI\.Val\("tabs",\s*4\)', GUI) is not None,
      "the gate pins the window to the License tab")

# 9. The entry script must load the three new modules, in a workable order.

entry = (ROOT / "RenderSmith.lua").read_text(encoding="utf-8")
provides = re.findall(r"^--\s+(?:\[main\]\s+)?(\S+\.lua)", entry, re.M)
load_list = re.findall(r'^\s+"(\w+\.lua)",', entry, re.M)

provides_bare = {p.split("/")[-1] for p in provides}
check(set(load_list) | {"RenderSmith.lua"} == provides_bare,
      f"the @provides list and the load list agree "
      f"(only in provides: {sorted(provides_bare - set(load_list) - {'RenderSmith.lua'})}, "
      f"only in loader: {sorted(set(load_list) - provides_bare)})")

on_disk = {p.name for p in (ROOT / "src").glob("*.lua")}
check(set(load_list) == on_disk,
      f"the load list matches src/ on disk "
      f"(missing: {sorted(on_disk - set(load_list))}, "
      f"extra: {sorted(set(load_list) - on_disk)})")

check(load_list[0] == "config.lua", "config.lua loads first")
check(load_list[-1] == "gui.lua", "gui.lua loads last")
for m in ("json.lua", "net.lua", "license.lua"):
    check(m in load_list and load_list.index(m) > load_list.index("config.lua"),
          f"{m} loads after config.lua")
    check(load_list.index(m) < load_list.index("gui.lua"),
          f"{m} loads before gui.lua")

print(f"\ntest_gui_static: {passed} passed, {failed} failed")
sys.exit(0 if failed == 0 else 1)
