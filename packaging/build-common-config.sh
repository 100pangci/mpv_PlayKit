#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: build-common-config.sh \
  --source-root PATH \
  --standard-config-root PATH \
  --output-directory PATH \
  --uosc-repository OWNER/REPOSITORY \
  [--uosc-release TAG|latest]
EOF
}

SOURCE_ROOT=
STANDARD_CONFIG_ROOT=
OUTPUT_DIRECTORY=
UOSC_REPOSITORY=
UOSC_RELEASE=latest

while (($# > 0)); do
    case "$1" in
        --source-root) SOURCE_ROOT=$2; shift 2 ;;
        --standard-config-root) STANDARD_CONFIG_ROOT=$2; shift 2 ;;
        --output-directory) OUTPUT_DIRECTORY=$2; shift 2 ;;
        --uosc-repository) UOSC_REPOSITORY=$2; shift 2 ;;
        --uosc-release) UOSC_RELEASE=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z "$SOURCE_ROOT" || -z "$STANDARD_CONFIG_ROOT" || -z "$OUTPUT_DIRECTORY" || -z "$UOSC_REPOSITORY" ]]; then
    usage >&2
    exit 2
fi

SOURCE_ROOT=$(cd -- "$SOURCE_ROOT" && pwd)
STANDARD_CONFIG_ROOT=$(cd -- "$STANDARD_CONFIG_ROOT" && pwd)
OUTPUT_DIRECTORY=$(mkdir -p "$OUTPUT_DIRECTORY" && cd -- "$OUTPUT_DIRECTORY" && pwd)

if [[ ! -d "$STANDARD_CONFIG_ROOT" ]]; then
    echo "The common portable_config is missing: $STANDARD_CONFIG_ROOT" >&2
    exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
    echo 'gh is required to resolve external release assets' >&2
    exit 1
fi
if ! command -v unzip >/dev/null 2>&1; then
    echo 'unzip is required to extract the uosc release asset' >&2
    exit 1
fi

rm -rf "$OUTPUT_DIRECTORY"
mkdir -p "$OUTPUT_DIRECTORY"
cp -a "$STANDARD_CONFIG_ROOT" "$OUTPUT_DIRECTORY/portable_config"

download_directory="$OUTPUT_DIRECTORY/_downloads"
mkdir -p "$download_directory"

release_arguments=(release download --repo "$UOSC_REPOSITORY" --pattern 'uosc.zip' --dir "$download_directory" --clobber)
if [[ "$UOSC_RELEASE" != latest ]]; then
    release_arguments=(release download "$UOSC_RELEASE" --repo "$UOSC_REPOSITORY" --pattern 'uosc.zip' --dir "$download_directory" --clobber)
fi
gh "${release_arguments[@]}"

uosc_archive=$(find "$download_directory" -maxdepth 1 -type f -name 'uosc.zip' -print -quit)
if [[ -z "$uosc_archive" ]]; then
    echo 'uosc.zip was not downloaded' >&2
    exit 1
fi

if [[ "$UOSC_RELEASE" == latest ]]; then
    uosc_release_tag=$(gh release view --repo "$UOSC_REPOSITORY" --json tagName --jq '.tagName')
else
    uosc_release_tag=$(gh release view "$UOSC_RELEASE" --repo "$UOSC_REPOSITORY" --json tagName --jq '.tagName')
fi
uosc_root="$OUTPUT_DIRECTORY/portable_config/scripts/uosc/bin"
mkdir -p "$uosc_root"

# The Lua files in the fork are intentionally preserved. Only the platform
# helper binaries are refreshed from the original uosc project.
for member in scripts/uosc/bin/ziggy-windows.exe scripts/uosc/bin/ziggy-linux; do
    unzip -p "$uosc_archive" "$member" > "$uosc_root/${member##*/}"
done

cat > "$OUTPUT_DIRECTORY/EXTERNAL-SOURCES.txt" <<EOF
common_config_source=$SOURCE_ROOT/packaging/portable_config
uosc_repository=$UOSC_REPOSITORY
uosc_release=$uosc_release_tag
uosc_asset=uosc.zip
uosc_copied=ziggy-windows.exe,ziggy-linux
EOF

rm -rf "$download_directory"
echo "Built common configuration in $OUTPUT_DIRECTORY"
