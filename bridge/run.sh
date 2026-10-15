#!/usr/bin/env bash
# Starts the WhatsApp bridge, building it first when there is no binary for
# these sources yet: the first run, or the first after an update. Go comes
# through mise (part of Omarchy), which fetches it the first time; no cgo,
# so no C compiler either. The build's output goes to stderr; stdout carries
# only the bridge's JSON lines (and the build's own state, as such lines).
#
# Usage: run.sh <data dir> <cache dir>
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
data="$1"
cache="$2"
bindir="$data/bin"
mkdir -p "$data"
# What the bridge (and its build) says goes to a log, kept short.
log="$data/bridge.log"
[ -f "$log" ] && [ "$(stat -c%s "$log")" -gt 5000000 ] && mv -f "$log" "$log.1"
exec 2>>"$log"
hash=$(cat "$here"/*.go "$here/go.mod" "$here/go.sum" | sha256sum | cut -c1-16)
bin="$bindir/whatsapp-claude-bridge-$hash"

if [ ! -x "$bin" ]; then
  echo '{"t":"build","state":"start"}'
  mkdir -p "$bindir"
  if command -v mise >/dev/null 2>&1; then
    gocmd=(mise exec go@1.27 -- go)
  elif command -v go >/dev/null 2>&1; then
    gocmd=(go)
  else
    echo '{"t":"build","state":"failed","error":"no_go"}'
    exit 3
  fi
  if ! (cd "$here" && CGO_ENABLED=0 "${gocmd[@]}" build -trimpath -ldflags "-s -w" -o "$bin.tmp" .) >&2; then
    rm -f "$bin.tmp"
    echo '{"t":"build","state":"failed","error":"build"}'
    exit 3
  fi
  mv "$bin.tmp" "$bin"
  find "$bindir" -maxdepth 1 -name 'whatsapp-claude-bridge-*' ! -name "$(basename "$bin")" -delete
  echo '{"t":"build","state":"done"}'
fi

exec "$bin" "$data" "$cache"
