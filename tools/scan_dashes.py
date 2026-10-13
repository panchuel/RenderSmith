"""Check that no long dash or emoji creeps back into the sources.

Two forms matter, and the second is the one that bites. The literal
characters, and the \\x escape sequences the Lua sources use, which render as
the same glyph but are invisible to a search for the character itself. The
first cleanup pass missed ten of those for exactly that reason.

Exempt: the box-drawing glyphs that draw the hierarchy tree in gui.lua and
the file tree in README.md. Those are structure, not decoration. A tool that
always reports a problem stops being read.
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent / "RenderSmith"
DOCS = pathlib.Path(__file__).resolve().parent.parent

LITERAL = {
    "—": "em dash",
    "–": "en dash",
    "─": "box drawing",
}

# As they appear in Lua source: a backslash, an x, then two hex digits.
ESCAPED = {
    r"\xe2\x80\x94": "escaped em dash",
    r"\xe2\x80\x93": "escaped en dash",
    r"\xe2\x94\x80": "escaped box drawing",
}

# A line that also carries a corner or tee is drawing a tree, not decorating.
TREE_GLYPHS = (r"\xe2\x94\x94", r"\xe2\x94\x9c", "└", "├")

EMOJI_RANGES = [
    (0x1F000, 0x1FAFF),
    (0x2600, 0x27BF),
    (0x2B00, 0x2BFF),
]


def is_tree(line):
    return any(g in line for g in TREE_GLYPHS)


files = sorted(
    list(ROOT.glob("*.lua"))
    + list(ROOT.glob("src/*.lua"))
    + list(DOCS.glob("*.md"))
)

issues = []
for path in files:
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")

    for needle, name in list(LITERAL.items()) + list(ESCAPED.items()):
        hits = [i for i, line in enumerate(lines, 1)
                if needle in line and not is_tree(line)]
        if hits:
            issues.append(f"{path.name}: {name} on line(s) {hits}")

    for i, line in enumerate(lines, 1):
        for ch in line:
            cp = ord(ch)
            if any(lo <= cp <= hi for lo, hi in EMOJI_RANGES):
                issues.append(f"{path.name}:{i}: emoji U+{cp:04X}")
                break

print(f"scanned {len(files)} files")
if issues:
    for issue in issues:
        print("  " + issue)
    print(f"  {len(issues)} issue(s)")
else:
    print("  clean: no long dashes in either form, no emoji")
