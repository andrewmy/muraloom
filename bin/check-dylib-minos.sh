#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage:
  check-dylib-minos.sh <max_macos_version> <file_or_glob> [more_files...]

Checks the minimum macOS version (minos) encoded in Mach-O binaries via `otool -l`
and fails if any file requires a macOS version greater than <max_macos_version>.

Examples:
  bin/check-dylib-minos.sh 15.5 /opt/homebrew/opt/libraw/lib/libraw*.dylib
  bin/check-dylib-minos.sh 15.5 build/ci/Muraloom.app/Contents/Frameworks/*.dylib

Notes:
  - Prefers LC_BUILD_VERSION minos; falls back to LC_VERSION_MIN_MACOSX "version".
  - Version compare is major.minor (patch ignored).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

max="${1:-}"
shift || true

if [[ -z "$max" || "${#@}" -lt 1 ]]; then
  usage
  exit 2
fi

parse_major_minor() {
  local v="$1"
  if [[ "$v" =~ ^([0-9]+)\.([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

read -r max_major max_minor < <(parse_major_minor "$max")

minos_for() {
  local f="$1"
  # LC_BUILD_VERSION:
  local minos
  minos="$(otool -l "$f" | awk '
    $1=="cmd" && $2=="LC_BUILD_VERSION" {in=1; next}
    in && $1=="minos" {print $2; exit}
  ')"
  if [[ -n "$minos" ]]; then
    echo "$minos"
    return 0
  fi

  # LC_VERSION_MIN_MACOSX:
  minos="$(otool -l "$f" | awk '
    $1=="cmd" && $2=="LC_VERSION_MIN_MACOSX" {in=1; next}
    in && $1=="version" {print $2; exit}
  ')"
  if [[ -n "$minos" ]]; then
    echo "$minos"
    return 0
  fi

  return 1
}

bad=0
for f in "$@"; do
  if [[ ! -e "$f" ]]; then
    echo "error: file not found: $f" >&2
    bad=1
    continue
  fi

  minos="$(minos_for "$f" || true)"
  if [[ -z "$minos" ]]; then
    echo "warning: couldn't parse minos for $f" >&2
    continue
  fi

  if ! read -r file_major file_minor < <(parse_major_minor "$minos"); then
    echo "warning: couldn't parse version '$minos' for $f" >&2
    continue
  fi

  if ((file_major > max_major)) || { ((file_major == max_major)) && ((file_minor > max_minor)); }; then
    echo "ERROR: $f requires macOS $file_major.$file_minor (max allowed $max_major.$max_minor)" >&2
    bad=1
  else
    echo "OK: $f minos $file_major.$file_minor <= $max_major.$max_minor"
  fi
done

exit "$bad"

