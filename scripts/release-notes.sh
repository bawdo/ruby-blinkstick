#!/bin/sh
# Prints the CHANGELOG.md section for one version, without its heading, for
# use as GitHub release notes. Fails if the section is missing or empty, so a
# release never goes out with blank notes.
#
#   sh scripts/release-notes.sh 0.1.1
set -eu

version="${1:?usage: release-notes.sh <version>}"
# An exported CDPATH would make cd print the directory into root.
root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)

# index() rather than a regex, so the dots in the version match only dots.
notes=$(awk -v h="## [$version]" '
  index($0, h) == 1 { f = 1; next }
  /^## \[/ { f = 0 }
  f
' "$root/CHANGELOG.md")

if [ -z "$(printf '%s' "$notes" | tr -d '[:space:]')" ]; then
  echo "release-notes: no CHANGELOG.md section for $version" >&2
  exit 1
fi
printf '%s\n' "$notes"
