#!/usr/bin/env python3
"""Deterministic implementation auditor for AdaCraft.

Source of truth: ``Adacraft.txt`` (the frozen specification committed verbatim
in the repository root). The auditor parses that file into discrete
requirement units, maps each unit to the codebase via static text search,
classifies the result, and emits a deterministic Markdown report at
``docs/audits/implementation-gap-analysis.md``.

The output is reproducible: given the same commit of ``Adacraft.txt`` and the
same commit of the source tree, two consecutive runs produce byte-identical
files. Run ``tools/test_audit_determinism.sh`` to verify.
"""

from __future__ import annotations

import hashlib
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SPEC_PATH = REPO_ROOT / "Adacraft.txt"
REPORT_PATH = REPO_ROOT / "docs" / "audits" / "implementation-gap-analysis.md"

# Paths whose contents are not considered "implementation" for the purpose of
# this audit. The spec file itself, generated JSON, build output, the audit
# report, and tools/ are excluded so the auditor does not score itself.
EXCLUDED_DIRS = {
    ".git",
    "docs/audits",
    "generated",  # generated JSON reports and the generated .ads catalog
}
EXCLUDED_TOP_FILES = {
    "Adacraft.txt",
    "implementation-gap-analysis.md",
}
EXCLUDED_SUFFIXES = {
    ".json",
    ".toml",
}

# A small stopword list keeps the keyword extraction cheap and the search
# focused. Entries are lowercase.
STOPWORDS = {
    "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from",
    "has", "have", "in", "into", "is", "it", "its", "of", "on", "or", "that",
    "the", "their", "there", "this", "to", "was", "were", "will", "with",
    "not", "no", "may", "must", "should", "can", "could", "would", "shall",
    "all", "any", "each", "every", "such", "than", "then", "these", "those",
    "they", "them", "we", "our", "you", "your", "i", "me", "my", "he", "she",
    "his", "her", "if", "else", "when", "where", "while", "how", "what",
    "which", "who", "whom", "whose", "why", "do", "does", "did", "done",
    "being", "been", "also", "only", "just", "very", "more", "most", "less",
    "least", "same", "other", "another", "one", "two", "three", "four",
    "five", "six", "seven", "eight", "nine", "ten", "first", "second",
    "third", "fourth", "last", "next", "previous", "above", "below", "up",
    "down", "out", "over", "under", "again", "further", "once", "here",
    "there", "both", "either", "neither", "many", "much", "some", "few",
    "own", "so", "too", "still", "now", "after", "before", "until", "since",
    "about", "between", "through", "during", "against", "along", "across",
    "behind", "beyond", "within", "without", "around", "among",
}


@dataclass
class Requirement:
    """A single requirement unit extracted from ``Adacraft.txt``."""

    rid: str
    title: str
    body: str
    keywords: tuple[str, ...]
    refs: list[tuple[str, int]] = field(default_factory=list)

    @property
    def status(self) -> str:
        if not self.refs:
            return "Not Implemented"
        # Body files (.adb) indicate actual implementation. Specification-only
        # matches (.ads, .md, .toml) indicate partial coverage.
        has_body = any(path.endswith(".adb") for path, _ in self.refs)
        if has_body:
            return "Implemented"
        return "Partially Implemented"


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

# Header styles, tried in order. The first regex that yields any sections wins.
HEADER_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("numbered", re.compile(r"^(?:\*\*)?(\d{1,3})\.(?:\*\*)?\s+([^\n]+)")),
    ("markdown", re.compile(r"^#{1,6}\s+(?:\*\*)?(\d{1,3})\.(?:\*\*)?\s+([^\n]+)")),
    ("section", re.compile(r"^Section\s+(\d{1,3})\.\s+([^\n]+)", re.IGNORECASE)),
)

BACKTICK_IDENT = re.compile(r"`([A-Za-z][A-Za-z0-9_]*)`")
WORD = re.compile(r"[A-Za-z][A-Za-z0-9_]{3,}")


def detect_header_pattern(text: str) -> tuple[str, re.Pattern[str]]:
    """Return the first header regex that yields multiple matches in ``text``."""
    counts = {}
    for name, pattern in HEADER_PATTERNS:
        counts[name] = len(pattern.findall(text))
    best = max(counts, key=lambda name: counts[name])
    if counts[best] < 2:
        # No structured headers: fall back to the most permissive option so we
        # still produce a report, even if coarse.
        best = HEADER_PATTERNS[0][0]
    for name, pattern in HEADER_PATTERNS:
        if name == best:
            return name, pattern
    raise RuntimeError("unreachable")


def parse_requirements(spec_text: str) -> list[Requirement]:
    """Parse ``Adacraft.txt`` into an ordered list of ``Requirement`` records."""
    style, pattern = detect_header_pattern(spec_text)
    lines = spec_text.splitlines(keepends=True)
    header_lines: list[tuple[int, int, str, str]] = []
    for index, line in enumerate(lines):
        match = pattern.match(line.rstrip("\n"))
        if match:
            header_lines.append((index, int(match.group(1)), match.group(2).strip(), style))

    # Build the body slice for each header.
    requirements: list[Requirement] = []
    for position, (line_no, number, title, _style) in enumerate(header_lines):
        body_start = line_no + 1
        body_end = header_lines[position + 1][0] if position + 1 < len(header_lines) else len(lines)
        body = "".join(lines[body_start:body_end])
        rid = f"{number:03d}"
        keywords = extract_keywords(title, body)
        requirements.append(
            Requirement(rid=rid, title=title, body=body, keywords=tuple(sorted(keywords)))
        )
    return requirements


def extract_keywords(title: str, body: str) -> set[str]:
    """Extract searchable keywords from a requirement's title and body."""
    words: set[str] = set()
    # Backtick identifiers always count.
    for ident in BACKTICK_IDENT.findall(title + "\n" + body):
        words.add(ident.lower())
    # Title words, normalized.
    for word in WORD.findall(title):
        lowered = word.lower()
        if lowered not in STOPWORDS:
            words.add(lowered)
    # Body words are capped so the search stays fast and the matches stay
    # selective. We prefer rarer words (longer first).
    body_words = [w.lower() for w in WORD.findall(body) if w.lower() not in STOPWORDS]
    body_words.sort(key=lambda w: (-len(w), w))
    for word in body_words[:25]:
        words.add(word)
    return words


# ---------------------------------------------------------------------------
# Static mapping
# ---------------------------------------------------------------------------

def iter_source_files() -> list[Path]:
    """Yield every file under the repo root that the auditor should scan."""
    files: list[Path] = []
    for path in sorted(REPO_ROOT.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(REPO_ROOT).as_posix()
        if rel in EXCLUDED_TOP_FILES:
            continue
        if any(part in EXCLUDED_DIRS for part in path.relative_to(REPO_ROOT).parts):
            continue
        if path.suffix.lower() in EXCLUDED_SUFFIXES:
            continue
        if path.name.startswith("."):
            continue
        files.append(path)
    return files


def scan_keywords(file_index: dict[Path, list[str]]) -> dict[str, set[tuple[str, int]]]:
    """Build a keyword → set of (relpath, line_no) reverse index.

    The index is keyword-sensitive but case-insensitive on lookup.
    """
    keyword_hits: dict[str, set[tuple[str, int]]] = {}
    for path, lines in file_index.items():
        rel = path.relative_to(REPO_ROOT).as_posix()
        for line_no, line in enumerate(lines, start=1):
            lowered = line.lower()
            for word in WORD.findall(lowered):
                keyword_hits.setdefault(word, set()).add((rel, line_no))
            # Backtick identifiers as they appear (case preserved).
            for ident in BACKTICK_IDENT.findall(line):
                keyword_hits.setdefault(ident.lower(), set()).add((rel, line_no))
    return keyword_hits


def build_file_index() -> tuple[dict[Path, list[str]], dict[str, set[tuple[str, int]]]]:
    files = iter_source_files()
    file_index: dict[Path, list[str]] = {}
    for path in files:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        file_index[path] = text.splitlines()
    return file_index, scan_keywords(file_index)


def map_requirement(req: Requirement, index: dict[str, set[tuple[str, int]]]) -> None:
    """Populate ``req.refs`` with deterministic (relpath, line) tuples."""
    seen: set[tuple[str, int]] = set()
    for keyword in req.keywords:
        for ref in index.get(keyword, ()):
            seen.add(ref)
    # Sort for determinism.
    req.refs = sorted(seen)


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

STATUS_EMOJI = {
    "Implemented": "[Implemented]",
    "Partially Implemented": "[Partial]",
    "Not Implemented": "[Missing]",
}


def render_report(requirements: list[Requirement], spec_sha256: str, spec_bytes: int) -> str:
    counts = {"Implemented": 0, "Partially Implemented": 0, "Not Implemented": 0}
    for req in requirements:
        counts[req.status] += 1

    lines: list[str] = []
    lines.append("# Implementation Gap Analysis")
    lines.append("")
    lines.append(
        "Static mapping from the frozen `Adacraft.txt` specification to the "
        "current repository. Generated by `tools/audit_implementation.py`."
    )
    lines.append("")
    lines.append(f"- Specification: `Adacraft.txt` ({spec_bytes} bytes)")
    lines.append(f"- Specification SHA-256: `{spec_sha256}`")
    lines.append(
        f"- Requirements parsed: **{len(requirements)}** "
        f"(Implemented: {counts['Implemented']}, "
        f"Partial: {counts['Partially Implemented']}, "
        f"Missing: {counts['Not Implemented']})"
    )
    lines.append("- Mapping basis: case-insensitive keyword + identifier search across the repository")
    lines.append("- Status rules:")
    lines.append("  - `Implemented`: at least one match in a body file (`*.adb`).")
    lines.append("  - `Partially Implemented`: matches exist only in declaration files (`*.ads`) or documentation.")
    lines.append("  - `Not Implemented`: no source-tree matches.")
    lines.append("")
    lines.append("| ID | Requirement | Status | File / Line References |")
    lines.append("|----|-------------|--------|------------------------|")
    for req in requirements:
        status = STATUS_EMOJI[req.status]
        title = req.title.replace("|", "\\|").strip()
        if req.refs:
            refs = "<br>".join(
                f"`{path}`:{line}" for path, line in req.refs
            )
        else:
            refs = "—"
        lines.append(f"| {req.rid} | {title} | {status} | {refs} |")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    total = max(len(requirements), 1)
    for status, count in counts.items():
        pct = 100.0 * count / total
        lines.append(f"- {status}: {count} ({pct:.1f}%)")
    lines.append("")
    lines.append("## Reproduction")
    lines.append("")
    lines.append("```")
    lines.append("python3 tools/audit_implementation.py")
    lines.append("bash   tools/test_audit_determinism.sh")
    lines.append("```")
    lines.append("")
    # Trailing newline keeps diffs stable across editors.
    return "\n".join(lines) + "\n"


def spec_digest(path: Path) -> tuple[str, int]:
    data = path.read_bytes()
    return hashlib.sha256(data).hexdigest(), len(data)


def main() -> int:
    if not SPEC_PATH.is_file():
        print(f"missing spec: {SPEC_PATH}", file=sys.stderr)
        return 1
    spec_text = SPEC_PATH.read_text(encoding="utf-8", errors="replace")
    requirements = parse_requirements(spec_text)
    _file_index, keyword_index = build_file_index()
    for req in requirements:
        map_requirement(req, keyword_index)
    sha, size = spec_digest(SPEC_PATH)
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(render_report(requirements, sha, size), encoding="utf-8")
    print(
        f"wrote {REPORT_PATH.relative_to(REPO_ROOT)}: "
        f"{len(requirements)} requirements, "
        f"{sum(1 for r in requirements if r.refs)} with matches"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
