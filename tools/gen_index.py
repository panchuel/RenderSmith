"""Generate the ReaPack index.xml for RenderSmith from the script's own
@provides block.

The old hand-written index drifted badly: it declared 13 sources while 20
modules were on disk, so ReaPack users installed a build that did not match
the README. Deriving it from @provides and cross-checking against src/ makes
that drift impossible. Re-run this for every release.
"""
import pathlib
import re
import sys
import datetime

# Resolved from this file's own location, so the tools keep working
# wherever the repo lives.
PROD = pathlib.Path(__file__).resolve().parent.parent / "RenderSmith"
OUT = pathlib.Path(__file__).resolve().parent.parent / "index.xml"

# GitHub names the first branch of a new repo "main"; the previous repo used
# "master". Every source URL below is pinned to one of them, so pass the right
# one rather than editing 24 URLs by hand:
#     python tools/gen_index.py main
BRANCH = sys.argv[1] if len(sys.argv) > 1 else "master"

RAW = f"https://raw.githubusercontent.com/panchuel/RenderSmith/{BRANCH}/RenderSmith/"
SITE = "https://github.com/panchuel/RenderSmith"

entry = (PROD / "RenderSmith.lua").read_text(encoding="utf-8")

version = re.search(r"^--@version\s+(\S+)", entry, re.M).group(1)
provides = re.findall(r"^--\s+(?:\[main\]\s+)?(\S+\.lua)\s*$", entry, re.M)

# Cross-check: @provides must name exactly the entry script plus every module
# that is actually on disk.
declared = set(provides)
on_disk = {"RenderSmith.lua"} | {"src/" + p.name for p in (PROD / "src").glob("*.lua")}
if declared != on_disk:
    print("ABORT, @provides does not match the files on disk:")
    print("  only in @provides:", sorted(declared - on_disk))
    print("  only on disk:     ", sorted(on_disk - declared))
    sys.exit(1)

DESCRIPTION = """RenderSmith turns a REAPER session into delivered game-audio assets.

It finds the individual sounds inside your track folders, names them from the
folder hierarchy or the UCS 8.2 standard, and renders each one to its own file
in an organised output tree.

Free for 7 days with every feature unlocked, then it needs a license key: a
one-time purchase that does not expire. The key is emailed the moment you buy.

Features:
- Gap clustering: one region per sound, so twenty gunshots in one folder
  become twenty files
- Cluster preview before you create anything, with a live count on the button
- NameSwitch markers: one folder can hold many differently named sounds
- Isolated renders: overlapping folders never bleed into each other's files
- Direct render engine, writing WAV without opening REAPER's render window
- UCS 8.2 naming per audio type, with the full 82-category catalog built in
- Custom wildcards, custom audio types and custom per-type fields
- Per-track overrides that travel inside the .rpp
- Overwrite protection before anything is replaced

Requires Lokasenna_GUI v2, which ReaPack can install for you."""

CHANGELOG = """RegionForge is now RenderSmith. The name follows what the tool
actually does: regions were only ever the intermediate step.

- Gap clustering, so a folder yields one region per sound instead of one
  region per folder
- Cluster preview drawn on a temporary track, plus a live region count on the
  Create Regions button
- NameSwitch markers: rename regions and restart numbering partway through a
  folder, so one folder can hold several different sounds
- Fixed a long-standing audio bug: folders overlapping in time bled into each
  other's rendered files. Each region now renders in isolation, and folder
  routing still survives
- Region identity moved to GUIDs, with per-region metadata in the project
  rather than global state, so hierarchies no longer leak between projects
- Overwrite protection: RenderSmith asks REAPER which files it would write and
  warns before replacing any
- Regions are reused instead of duplicated when one already matches
- Hybrid regions: keep them in the project, or let them exist only for the
  render
- A shared $RF[NAME] wildcard dictionary with global and per-project scope
- Per-track overrides for audio type, output folder and gap
- Mutation journal: every temporary change is undone, and anything you edited
  underneath is left alone
- Tabs reorganised into Main, Config, Render and License
- 7 day trial and license key activation"""


def indent(text, pad):
    return "\n".join(pad + line if line else "" for line in text.split("\n"))


sources = "\n".join(
    f'        <source file="{p}">{RAW}{p}</source>' for p in provides
)

stamp = datetime.date.today().isoformat() + "T00:00:00Z"

xml = f"""<?xml version="1.0" encoding="utf-8"?>
<index version="1" name="RenderSmith">
  <category name="Rendering">
    <reapack name="RenderSmith.lua" type="script"
             desc="RenderSmith - Region naming &amp; batch asset delivery">
      <metadata>
        <description><![CDATA[
{DESCRIPTION}
        ]]></description>
        <link rel="website">{SITE}</link>
      </metadata>
      <version name="{version}" author="Panchuel" time="{stamp}">
        <changelog><![CDATA[
{CHANGELOG}
        ]]></changelog>
{sources}
      </version>
    </reapack>
  </category>
</index>
"""

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(xml, encoding="utf-8")

print(f"wrote {OUT}")
print(f"  version:  {version}")
print(f"  sources:  {len(provides)} (1 entry + {len(provides) - 1} modules)")
print(f"  branch:   {BRANCH}")
print(f"  verified: @provides matches src/ on disk")
