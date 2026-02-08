#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage:
  coverage-gate.sh <path-to.xcresult> [min_percent] [target_name]

Examples:
  coverage-gate.sh /tmp/tests.xcresult 20 GPhotoPaper
  MIN_COVERAGE_PERCENT=15 coverage-gate.sh /tmp/tests.xcresult "" GPhotoPaper

Notes:
  - Uses `xcrun xccov` to read coverage from an Xcode result bundle.
  - `min_percent` is a percentage (e.g. 20 means 20%).
  - If `target_name` is omitted, the overall report coverage is used when available.
EOF
}

xcresult_path="${1:-}"
if [[ -z "${xcresult_path}" ]]; then
  usage
  exit 2
fi

if [[ ! -d "${xcresult_path}" ]]; then
  echo "ERROR: xcresult bundle not found: ${xcresult_path}" >&2
  exit 2
fi

min_percent="${2:-${MIN_COVERAGE_PERCENT:-0}}"
target_name="${3:-${COVERAGE_TARGET:-}}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "ERROR: xcrun not found (Xcode command line tools required)" >&2
  exit 2
fi

xcrun xccov view --report --json "${xcresult_path}" | python3 -c '
import json
import sys

min_percent_raw = sys.argv[1]
target_name = sys.argv[2].strip()

try:
    min_percent = float(min_percent_raw) if min_percent_raw.strip() else 0.0
except ValueError:
    print(f"ERROR: invalid min_percent: {min_percent_raw!r}", file=sys.stderr)
    sys.exit(2)

raw = sys.stdin.read()

# Some Xcode versions can emit non-JSON warnings to stdout before the JSON payload.
starts = [i for i in (raw.find("{"), raw.find("[")) if i != -1]
if not starts:
    print("ERROR: xccov did not emit JSON output.", file=sys.stderr)
    sys.exit(2)

data = json.loads(raw[min(starts):])

def to_percent(value):
    if value is None:
        return None
    value = float(value)
    # xccov typically emits [0,1] fractions, but be defensive.
    if 0.0 <= value <= 1.0:
        return value * 100.0
    return value

targets = data.get("targets") if isinstance(data, dict) else None
overall = data.get("lineCoverage") if isinstance(data, dict) else None

selected_percent = None
selected_label = None

if target_name:
    if not isinstance(targets, list):
        print("ERROR: coverage JSON did not include per-target data; cannot select target.", file=sys.stderr)
        sys.exit(2)

    wanted = [target_name]
    if not target_name.endswith(".app"):
        wanted.append(target_name + ".app")
    if not target_name.endswith(".xctest"):
        wanted.append(target_name + ".xctest")

    match = None
    for name in wanted:
        match = next((t for t in targets if isinstance(t, dict) and t.get("name") == name), None)
        if match is not None:
            if name != target_name:
                target_name = name
            break

    if match is None:
        # As a last resort, accept a unique prefix match (e.g. "GPhotoPaper" -> "GPhotoPaper.app").
        prefix_matches = [
            t for t in targets
            if isinstance(t, dict)
            and isinstance(t.get("name"), str)
            and t.get("name").startswith(target_name + ".")
        ]
        if len(prefix_matches) == 1:
            match = prefix_matches[0]
            target_name = match.get("name")

    if match is None:
        available = [t.get("name") for t in targets if isinstance(t, dict) and t.get("name")]
        print(f"ERROR: target {target_name!r} not found in coverage report.", file=sys.stderr)
        if available:
            print("Available targets:", file=sys.stderr)
            for name in available:
                print(f"  - {name}", file=sys.stderr)
        sys.exit(2)

    selected_percent = to_percent(match.get("lineCoverage"))
    selected_label = f"target:{target_name}"
else:
    selected_percent = to_percent(overall)
    selected_label = "overall"

if selected_percent is None:
    print("ERROR: could not read line coverage from xccov JSON.", file=sys.stderr)
    sys.exit(2)

print(f"Unit test line coverage ({selected_label}): {selected_percent:.2f}%")
print(f"Minimum required: {min_percent:.2f}%")

if selected_percent + 1e-9 < min_percent:
    print("ERROR: coverage is below the required minimum.", file=sys.stderr)
    sys.exit(1)
' "${min_percent}" "${target_name}"
