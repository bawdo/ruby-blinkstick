#!/bin/sh
# Builds the gem, installs it into a scratch GEM_HOME and requires it from
# outside the repository, catching a gem that builds and passes its tests
# but will not install or load. The gem depends on ffi, so the locked ffi is
# fetched and installed first, but only if its sha256 is in the lockfile.
set -eu

# An exported CDPATH would make cd print the directory into root.
root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/blinkstick-smoke.XXXXXX")
trap 'rm -rf "$work"' EXIT

lockfile=${LOCKFILE:-$root/Gemfile.lock}

# The locked version is the four-space indented spec line under GEM, not the
# gemspec constraint line under DEPENDENCIES (six spaces, "~>" and ">=").
ffi_version=$(sed -n 's/^    ffi (\([0-9][0-9.]*\)\(-[^)]*\)\{0,1\})$/\1/p' "$lockfile" | head -n 1)
if [ -z "$ffi_version" ]; then
  echo "smoke: no locked ffi version found in $lockfile" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | cut -d ' ' -f 1; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
else
  echo "smoke: neither sha256sum nor shasum is available" >&2
  exit 1
fi

# Picks the variant for the running platform, into the scratch directory.
(cd "$work" && gem fetch ffi -v "$ffi_version")
ffi_gem=$(ls "$work"/ffi-"$ffi_version"*.gem)
ffi_sha=$(sha256 "$ffi_gem")
# Any platform suffix of the locked version will do, but the digest must be
# one the lockfile lists.
if ! sed -n "s/^  ffi ($ffi_version[^)]*) sha256=//p" "$lockfile" | grep -qx "$ffi_sha"; then
  echo "smoke: ffi checksum mismatch: $(basename "$ffi_gem") has sha256 $ffi_sha, not listed in $lockfile" >&2
  exit 1
fi
GEM_HOME="$work/gems" GEM_PATH="$work/gems" gem install --local --no-document "$ffi_gem"

(cd "$root" && gem build ruby-blinkstick.gemspec --output "$work/ruby-blinkstick.gem")
GEM_HOME="$work/gems" GEM_PATH="$work/gems" gem install --local --no-document "$work/ruby-blinkstick.gem"

# Out of the repository, and with GEM_PATH pinned to the scratch gems, so
# neither its lib/ nor any other installed copy can satisfy the require.
cd "$work"
GEM_HOME="$work/gems" GEM_PATH="$work/gems" ruby -e '
require "blinkstick"
puts "smoke: ruby-blinkstick #{Blinkstick::VERSION} loads"
puts "smoke: Blinkstick.list found #{Blinkstick.list.size}"
if RUBY_PLATFORM.include?("linux") && defined?(FFI)
  warn "smoke: FFI was loaded on Linux, which must not need it"
  exit 1
end
'
