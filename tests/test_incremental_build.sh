#!/bin/sh
# A source dependency change must reach a test executable on the next make,
# even when its main is unchanged. Exercise the real Makefile and compiler.
set -eu
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/generated" "$T/tests" "$T/src/protocol" "$T/src/kernel" \
  "$T/src/auth" "$T/src/ingress" "$T/src/network"
cat > "$T/src/protocol/support.ads" <<'ADA'
package Support is
   Value : constant := 1;
end Support;
ADA
cat > "$T/tests/adacraft_tests.adb" <<'ADA'
with Ada.Text_IO;
with Support;
procedure Adacraft_Tests is
begin
   Ada.Text_IO.Put_Line (Integer'Image (Support.Value));
end Adacraft_Tests;
ADA
make -s -C "$T" -f "$ROOT/Makefile" bin/adacraft_tests GNATMAKE="${GNATMAKE:-gnatmake}" >/dev/null
[ "$("$T/bin/adacraft_tests")" = ' 1' ]
python3 - "$T/src/protocol/support.ads" <<'PY'
import os, sys
from pathlib import Path
path = Path(sys.argv[1])
previous = path.stat().st_mtime_ns
path.write_text('package Support is\n   Value : constant := 2;\nend Support;\n')
# GNAT source timestamps have second precision; make the edit unambiguous
# without imposing a sleep on every run of this regression.
os.utime(path, ns=(previous + 2_000_000_000, previous + 2_000_000_000))
PY
make -s -C "$T" -f "$ROOT/Makefile" bin/adacraft_tests GNATMAKE="${GNATMAKE:-gnatmake}" >/dev/null
[ "$("$T/bin/adacraft_tests")" = ' 2' ] || {
  echo 'FAIL: make reused a test executable after an Ada dependency changed' >&2
  exit 1
}
echo 'incremental Ada dependency test passed'
