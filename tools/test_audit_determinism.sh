#!/usr/bin/env bash
# Verifies that tools/audit_implementation.py is deterministic: two runs
# against the same commit must produce byte-identical reports.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORT="$ROOT/docs/audits/implementation-gap-analysis.md"
FIRST="$(mktemp)"
SECOND="$(mktemp)"
trap 'rm -f "$FIRST" "$SECOND"' EXIT

cd "$ROOT"
python3 tools/audit_implementation.py >/dev/null
cp "$REPORT" "$FIRST"

python3 tools/audit_implementation.py >/dev/null
cp "$REPORT" "$SECOND"

if ! cmp -s "$FIRST" "$SECOND"; then
    echo "FAIL: audit report is not deterministic" >&2
    diff -u "$FIRST" "$SECOND" >&2 || true
    exit 1
fi

# Also confirm the report references the spec that is actually on disk.
SHA=$(sha256sum "$ROOT/Adacraft.txt" | awk '{print $1}')
if ! grep -q "$SHA" "$REPORT"; then
    echo "FAIL: report does not embed the live spec SHA-256" >&2
    exit 1
fi

echo "audit determinism ok ($(wc -c <"$REPORT") bytes)"
END

FILE: tools/test_audit_determinism.sh
<<<<<<< SEARCH
#!/usr/bin/env bash
# Verifies that tools/audit_implementation.py is deterministic: two runs
# against the same commit must produce byte-identical reports.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORT="$ROOT/docs/audits/implementation-gap-analysis.md"
FIRST="$(mktemp)"
SECOND="$(mktemp)"
trap 'rm -f "$FIRST" "$SECOND"' EXIT

cd "$ROOT"
python3 tools/audit_implementation.py >/dev/null
cp "$REPORT" "$FIRST"

python3 tools/audit_implementation.py >/dev/null
cp "$REPORT" "$SECOND"

if ! cmp -s "$FIRST" "$SECOND"; then
    echo "FAIL: audit report is not deterministic" >&2
    diff -u "$FIRST" "$SECOND" >&2 || true
    exit 1
fi

# Also confirm the report references the spec that is actually on disk.
SHA=$(sha256sum "$ROOT/Adacraft.txt" | awk '{print $1}')
if ! grep -q "$SHA" "$REPORT"; then
    echo "FAIL: report does not embed the live spec SHA-256" >&2
    exit 1
fi

echo "audit determinism ok ($(wc -c <"$REPORT") bytes)"
=======
#!/usr/bin/env bash
# Verifies that tools/audit_implementation.py is deterministic: two runs
# against the same commit must produce byte-identical reports.
#
# Pass criterion (acceptance criterion #5):
#   running the auditor twice against the same commit yields the same report.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORT="$ROOT/docs/audits/implementation-gap-analysis.md"
FIRST="$(mktemp)"
SECOND="$(mktemp)"
trap 'rm -f "$FIRST" "$SECOND"' EXIT

cd "$ROOT"

# Run #1.
python3 tools/audit_implementation.py >/dev/null
cp "$REPORT" "$FIRST"

# Run #2.
python3 tools/audit_implementation.py >/dev/null
cp "$REPORT" "$SECOND"

if ! cmp -s "$FIRST" "$SECOND"; then
    echo "FAIL: audit report is not deterministic across consecutive runs" >&2
    diff -u "$FIRST" "$SECOND" >&2 || true
    exit 1
fi

# The report must embed the SHA-256 of the spec file currently on disk, so a
# spec change is detectable from the report header without diffing it.
EXPECTED_SHA="$(python3 -c 'import hashlib,sys; sys.stdout.write(hashlib.sha256(open("'"$ROOT"'/Adacraft.txt","rb").read()).hexdigest())')"
if ! grep -q "$EXPECTED_SHA" "$REPORT"; then
    echo "FAIL: report does not embed the live Adacraft.txt SHA-256" >&2
    exit 1
fi

echo "audit determinism ok ($(wc -c <"$REPORT") bytes)"
