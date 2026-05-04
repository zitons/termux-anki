#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
printf '[INFO] This installer now uses VNC. Delegating to install-termux-anki-vnc.sh\n'
exec "$script_dir/install-termux-anki-vnc.sh" "$@"
