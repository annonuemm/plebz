#!/bin/bash
#
# Build a Plebz release APK with a fresh, running version number.
#
# Each run increments the pubspec build number before building, so the APK's
# Android versionCode is always higher than the previous one and installs as an
# update rather than being rejected as a downgrade.
#
# One APK per processor architecture rather than one holding both: the
# player's native libraries are ~94% of the download, and a combined APK ships
# the other one to every device that cannot run it. Only the two ARM builds:
# x86_64 (emulators, Chromebooks) is left out at the user's word. Each file is named
# after the devices it is for, so nobody has to know what "arm64-v8a" means.
#
# Usage: scripts/build_apk.sh [--no-bump] [--debug-key]
#
# Plebz ships signed with its own key (scripts/create_release_key.sh writes
# android/key.properties). Without it the build stops: Gradle would fall back to
# the debug key, and an APK signed that way cannot update an installed Plebz.
# --debug-key allows exactly that, for a throwaway test build.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/apk"

bump=1
debug_key=0
for arg in "$@"; do
    case "$arg" in
        --no-bump) bump=0 ;;
        --debug-key) debug_key=1 ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

if ! command -v flutter >/dev/null 2>&1; then
    echo "Error: flutter is not on PATH." >&2
    echo "Add your Flutter SDK's bin directory to PATH and re-run." >&2
    exit 1
fi

cd "$PROJECT_ROOT"

if [ "$debug_key" -eq 0 ] && [ ! -f "$PROJECT_ROOT/android/key.properties" ]; then
    echo "Error: no release key (android/key.properties)." >&2
    echo "Create it once with scripts/create_release_key.sh, or pass --debug-key for a test build." >&2
    exit 1
fi

if [ "$bump" -eq 1 ]; then
    version="$(python3 "$SCRIPT_DIR/bump_build_number.py" "$PROJECT_ROOT/pubspec.yaml")"
    echo "Version bumped to $version"
else
    version="$(python3 "$SCRIPT_DIR/pubspec_version.py" "$PROJECT_ROOT/pubspec.yaml")"
    echo "Building $version without bumping"
fi

flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64

# An unsigned APK cannot be installed on any device, so fail loudly here rather
# than at install time on the TV.
apksigner="$(ls -1 "$HOME/Library/Android/sdk/build-tools"/*/apksigner 2>/dev/null | sort -V | tail -1 || true)"

mkdir -p "$OUTPUT_DIR"
# Stale builds of any architecture would sit next to the fresh ones and get
# installed by mistake — including those from before the rename to Plebz.
rm -f "$OUTPUT_DIR"/Plebz-*.apk "$OUTPUT_DIR"/Plesy-*.apk

# '+' is legal in a filename but confuses some file pickers; keep the build
# number readable instead.
label="${version/+/-build}"

# What each architecture actually means to someone picking a file. The
# architecture name stays in the filename as the precise anchor; the words
# after it are what make it choosable without knowing the term.
abis=(
    "arm64-v8a:arm64-modern-tv-and-phones"
    "armeabi-v7a:arm32-older-devices"
)

built_any=0
for entry in "${abis[@]}"; do
    abi="${entry%%:*}"
    audience="${entry##*:}"
    built="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-$abi-release.apk"
    if [ ! -f "$built" ]; then
        echo "Warning: no APK was built for $abi" >&2
        continue
    fi

    if [ -n "$apksigner" ]; then
        if ! "$apksigner" verify "$built" >/dev/null 2>&1; then
            echo "Error: $built is not signed." >&2
            exit 1
        fi
        if [ "$debug_key" -eq 0 ] && "$apksigner" verify --print-certs "$built" 2>/dev/null | grep -q "CN=Android Debug"; then
            echo "Error: $built is signed with the debug key, not Plebz's own." >&2
            exit 1
        fi
    fi

    output="$OUTPUT_DIR/Plebz-$label-$audience.apk"
    cp "$built" "$output"
    built_any=1
done

if [ "$built_any" -eq 0 ]; then
    echo "Error: no APKs were produced." >&2
    exit 1
fi

if [ -n "$apksigner" ]; then
    echo "Signatures verified"
else
    echo "Warning: apksigner not found; skipping the signature check." >&2
fi

echo "APKs:"
ls -lh "$OUTPUT_DIR"/Plebz-*.apk
