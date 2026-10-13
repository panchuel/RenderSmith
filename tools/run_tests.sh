#!/bin/sh
# Full verification for RenderSmith. Run from anywhere:  sh tools/run_tests.sh
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROD="$HERE/../RenderSmith"

fail=0
for f in "$PROD/RenderSmith.lua" "$PROD"/src/*.lua; do
    luac -p "$f" || { echo "PARSE FAIL: $f"; fail=1; }
done
[ $fail -eq 0 ] && echo "parse:              1 entry + $(ls "$PROD"/src/*.lua | wc -l) modules OK"

# The licence suite writes its file store under APPDATA; point that at a
# scratch folder so a test run never touches a real activation record.
TMPSTORE=$(mktemp -d 2>/dev/null || echo "${TMP:-/tmp}/rs_test_$$")
mkdir -p "$TMPSTORE/Scripts"
APPDATA="$TMPSTORE" lua "$HERE/test_license.lua" | tail -1
rm -rf "$TMPSTORE"

python "$HERE/test_gui_static.py" | tail -1
python "$HERE/scan_dashes.py" | tail -1
