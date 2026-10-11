#!/usr/bin/env bash
# Run this build, or its installed sibling, with an optional Qt backend override.
set -Eeuo pipefail

backend=inherit
while (( $# )); do
    case "$1" in
        --backend)
            (( $# >= 2 )) || { echo '--backend needs inherit, auto, wayland or xcb' >&2; exit 2; }
            backend="$2"
            shift 2
            ;;
        --help|-h)
            cat <<'EOF'
Usage: run-flameshot.sh [--backend inherit|auto|wayland|xcb] [Flameshot arguments]
Installed name: flameshot-local

  run-flameshot.sh gui                     Capture with the inherited Qt backend
  run-flameshot.sh --backend wayland gui   Test native Wayland
  run-flameshot.sh --backend xcb gui       Test X11/XWayland
  run-flameshot.sh                         Start the local tray daemon
  run-flameshot.sh gui --daemon            Reuse that daemon for a plain capture

auto clears QT_QPA_PLATFORM so Qt chooses its backend. Explicit overrides apply
only to the launched process. Use plain gui (without --daemon) for backend tests.
Inherited Snap toolkit paths are cleared for this native Ubuntu executable.
The --daemon option returns after the daemon accepts the request. If no matching
daemon exists, or other capture options are supplied, capture runs locally with
the usual wait/output behavior. No system settings or startup entries are changed.
EOF
            exit 0
            ;;
        --) shift; break ;;
        *) break ;;
    esac
done

case "$backend" in
    inherit) ;;
    auto) unset QT_QPA_PLATFORM ;;
    wayland|xcb) export QT_QPA_PLATFORM="$backend" ;;
    *) printf 'Invalid backend: %s\n' "$backend" >&2; exit 2 ;;
esac
# Terminals inside a Snap editor can export incompatible GTK/Qt libraries and
# schemas. Keep those overrides out of this native build, without changing the
# caller's environment or overriding paths unrelated to Snap.
for variable in LD_LIBRARY_PATH LD_PRELOAD GTK_PATH GTK_MODULES GIO_EXTRA_MODULES \
                QT_PLUGIN_PATH QT_QPA_PLATFORM_PLUGIN_PATH GSETTINGS_SCHEMA_DIR; do
    if [[ "${!variable-}" == */snap/* ]]; then
        unset "$variable"
    fi
done
launcher_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -x "$launcher_dir/flameshot" ]]; then
    executable="$launcher_dir/flameshot"
else
    executable="$launcher_dir/build/src/flameshot"
fi
[[ -x "$executable" ]] || { printf 'Build Flameshot first: %s\n' "$executable" >&2; exit 1; }
exec "$executable" "$@"
