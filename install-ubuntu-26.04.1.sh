#!/usr/bin/env bash
# Build and install this Flameshot v14.0.0 checkout on Ubuntu 26.04.1 LTS.
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: ./install-ubuntu-26.04.1.sh [options]

Run as your normal user from a v14.0.0 checkout. Installs Ubuntu build/runtime
dependencies, builds in ./build, then installs Flameshot under /usr/local.
sudo is used for APT and installation into a protected prefix only.
Internet access is needed for APT and the first CMake dependency download.
Ubuntu 26.04 point releases report VERSION_ID=26.04 and are accepted.
The update checker and Imgur screenshot uploader are compiled out in both
build-only and installation modes.

Options:
  --build-only      Install dependencies and build without installing Flameshot
  --skip-deps       Skip APT (all build/runtime dependencies must already exist)
  --test            Run offscreen rendering/selection regression tests after build
  --prefix PATH     Absolute installation prefix (default: /usr/local)
  --jobs N          Parallel compilation jobs (default: CPU count, capped at 4)
  -h, --help        Show this help

Examples:
  ./install-ubuntu-26.04.1.sh
  ./install-ubuntu-26.04.1.sh --build-only
  ./install-ubuntu-26.04.1.sh --skip-deps --prefix "$HOME/.local"

The install includes the executable, launcher, icons, translations, D-Bus
service, manual and shell completions. This is a source installation, outside
APT; the installed file list is saved in build/src/install_local_manifest.txt.
Wayland screen capture also needs your desktop's working screenshot portal.
The installed flameshot-local helper can select a backend for comparison:
  flameshot-local --backend wayland gui
  flameshot-local --backend xcb gui
Use flameshot-local gui --daemon to reuse this binary's running tray daemon.
Plain flameshot gui and captures with output options retain their usual behavior.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

trap 'printf "Failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
build_dir="$source_dir/build"
prefix=/usr/local
jobs="$(nproc)"
if (( jobs > 4 )); then jobs=4; fi
build_only=false
skip_deps=false
run_tests=false

while (( $# )); do
    case "$1" in
        --build-only) build_only=true; shift ;;
        --skip-deps) skip_deps=true; shift ;;
        --test) run_tests=true; shift ;;
        --prefix)
            (( $# >= 2 )) || die '--prefix requires a path'
            prefix="$2"
            shift 2
            ;;
        --jobs)
            (( $# >= 2 )) || die '--jobs requires a positive integer'
            jobs="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1 (see --help)" ;;
    esac
done

[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die '--jobs must be a positive integer'
[[ "$prefix" = /* && "$prefix" != / ]] || die '--prefix must be an absolute path other than /'
prefix="$(realpath -m -- "$prefix")"
[[ "$prefix" != / ]] || die 'Installing directly into / is not supported'
(( EUID != 0 )) || die 'Run as your normal user; the script invokes sudo when needed'
[[ -r /etc/os-release ]] || die 'Cannot identify the operating system'
# shellcheck source=/etc/os-release
source /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 26.04 ]] ||
    die 'This installer requires Ubuntu 26.04 (including 26.04.1 LTS)'

command -v git >/dev/null || die 'Install git first: sudo apt-get install git'
expected_commit=e408812d77ff1835957f85796c4cf737466bd69d
git -C "$source_dir" merge-base --is-ancestor "$expected_commit" HEAD ||
    die 'This installer requires a branch based on Flameshot v14.0.0'
source_version="$(sed -n 's/^set(FLAMESHOT_VERSION \([^)]*\))$/\1/p' "$source_dir/CMakeLists.txt")"
[[ "$source_version" == 14.0.0 ]] ||
    die 'This installer supports Flameshot 14.0.0, including commits on top of that release'

if ! "$skip_deps"; then
    command -v sudo >/dev/null || die 'sudo is needed to install dependencies'
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends \
        build-essential ca-certificates cmake git ninja-build python3 pkg-config \
        qt6-base-dev qt6-svg-dev qt6-tools-dev qt6-tools-dev-tools \
        qt6-l10n-tools libgl-dev extra-cmake-modules libkf6guiaddons-dev \
        qt6-qpa-plugins qt6-wayland qt6-image-formats-plugins \
        hicolor-icon-theme xdg-desktop-portal
fi

# Use Ubuntu's tools even if a broken Python-installed Ninja shadows them.
[[ -x /usr/bin/cmake && -x /usr/bin/ninja ]] ||
    die 'Missing cmake or ninja-build; rerun without --skip-deps'

/usr/bin/cmake -S "$source_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_MAKE_PROGRAM=/usr/bin/ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_INSTALL_BINDIR=bin \
    -DCMAKE_INSTALL_DATAROOTDIR=share \
    -DUSE_WAYLAND_CLIPBOARD=ON \
    -DUSE_KDSINGLEAPPLICATION=ON \
    -DUSE_BUNDLED_KDSINGLEAPPLICATION=ON \
    -DDISABLE_UPDATE_CHECKER=ON \
    -DENABLE_IMGUR=OFF \
    -DENABLE_CACHE=OFF
# Refresh Qt's generated code when reusing a build with different feature flags.
rm -f -- "$build_dir/src/flameshot_autogen/timestamp"
/usr/bin/cmake --build "$build_dir" --target flameshot --parallel "$jobs"

# Check the executable without requiring a running desktop session.
QT_QPA_PLATFORM=offscreen "$build_dir/src/flameshot" --version

if "$run_tests"; then
    command -v python3 >/dev/null || die '--test requires python3'
    command -v pkg-config >/dev/null || die '--test requires pkg-config'
    python3 "$source_dir/tests/run-performance-tests.py" "$build_dir"
fi

if "$build_only"; then
    printf '\nBuild complete: %s/src/flameshot\n' "$build_dir"
    exit 0
fi

# Install only the application, excluding bundled dependencies' development files.
# CMAKE_INSTALL_LOCAL_ONLY also makes CMake write this subtree's file manifest.
install_parent="$prefix"
while [[ ! -d "$install_parent" ]]; do
    install_parent="$(dirname -- "$install_parent")"
done
if [[ -w "$install_parent" ]]; then
    /usr/bin/cmake -DCMAKE_INSTALL_LOCAL_ONLY=ON -P "$build_dir/src/cmake_install.cmake"
else
    command -v sudo >/dev/null || die 'sudo is needed for this installation prefix'
    sudo /usr/bin/cmake -DCMAKE_INSTALL_LOCAL_ONLY=ON -P "$build_dir/src/cmake_install.cmake"
fi

printf '\nInstalled Flameshot 14.0.0. Launch with: %s/bin/flameshot gui\n' "$prefix"
printf 'Installed file list: %s/src/install_local_manifest.txt\n' "$build_dir"
printf 'Exit any older running Flameshot instance before launching this version.\n'
