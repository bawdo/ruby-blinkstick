#!/bin/sh
# Builds the gem, installs it into a scratch GEM_HOME and requires it from
# outside the repository, catching a gem that builds and passes its tests
# but will not install or load.
set -eu

# An exported CDPATH would make cd print the directory into root.
root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/blinkstick-smoke.XXXXXX")
trap 'rm -rf "$work"' EXIT

(cd "$root" && gem build ruby-blinkstick.gemspec --output "$work/ruby-blinkstick.gem")
GEM_HOME="$work/gems" GEM_PATH="$work/gems" gem install --local --no-document "$work/ruby-blinkstick.gem"

# Out of the repository, and with GEM_PATH pinned to the scratch gems, so
# neither its lib/ nor any other installed copy can satisfy the require.
cd "$work"
GEM_HOME="$work/gems" GEM_PATH="$work/gems" ruby -e 'require "blinkstick"; puts "smoke: ruby-blinkstick #{Blinkstick::VERSION} loads"'
