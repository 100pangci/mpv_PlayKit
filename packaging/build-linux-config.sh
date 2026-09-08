#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: build-linux-config.sh \
  --source-root PATH \
  --common-config-root PATH \
  --platform-patch PATH \
  --output-directory PATH \
  --version VERSION
EOF
}

SOURCE_ROOT=
COMMON_CONFIG_ROOT=
PLATFORM_PATCH=
OUTPUT_DIRECTORY=
VERSION=

while (($# > 0)); do
    case "$1" in
        --source-root) SOURCE_ROOT=$2; shift 2 ;;
        --common-config-root|--standard-config-root) COMMON_CONFIG_ROOT=$2; shift 2 ;;
        --platform-patch) PLATFORM_PATCH=$2; shift 2 ;;
        --output-directory) OUTPUT_DIRECTORY=$2; shift 2 ;;
        --version) VERSION=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z "$SOURCE_ROOT" || -z "$COMMON_CONFIG_ROOT" || -z "$PLATFORM_PATCH" || -z "$OUTPUT_DIRECTORY" || -z "$VERSION" ]]; then
    usage >&2
    exit 2
fi

SOURCE_ROOT=$(cd -- "$SOURCE_ROOT" && pwd)
COMMON_CONFIG_ROOT=$(cd -- "$COMMON_CONFIG_ROOT" && pwd)
PLATFORM_PATCH=$(cd -- "$(dirname -- "$PLATFORM_PATCH")" && pwd)/$(basename -- "$PLATFORM_PATCH")
OUTPUT_DIRECTORY=$(mkdir -p "$OUTPUT_DIRECTORY" && cd -- "$OUTPUT_DIRECTORY" && pwd)

if [[ ! -d "$COMMON_CONFIG_ROOT/portable_config" ]]; then
    echo "The common portable_config was not found: $COMMON_CONFIG_ROOT/portable_config" >&2
    exit 1
fi
if [[ ! -f "$PLATFORM_PATCH" ]]; then
    echo "The Linux platform patch was not found: $PLATFORM_PATCH" >&2
    exit 1
fi
if [[ ! -f "$SOURCE_ROOT/packaging/linux/README.txt" ]]; then
    echo 'Linux packaging README is missing' >&2
    exit 1
fi
if ! command -v patch >/dev/null 2>&1; then
    echo 'patch is required to apply the Linux configuration patch' >&2
    exit 1
fi

WORK_DIRECTORY="$OUTPUT_DIRECTORY/_work/linux-config/mpv-lazy"
rm -rf "$OUTPUT_DIRECTORY/_work"
mkdir -p "$WORK_DIRECTORY"

cp -a "$COMMON_CONFIG_ROOT/portable_config" "$WORK_DIRECTORY/portable_config"
(
    cd -- "$WORK_DIRECTORY/portable_config"
    patch --batch --forward --strip=1 < "$PLATFORM_PATCH"
)
cp -a "$SOURCE_ROOT/packaging/linux/README.txt" "$WORK_DIRECTORY/README.txt"
cp -a "$SOURCE_ROOT/LICENSE.MD" "$WORK_DIRECTORY/LICENSE.MD"
if [[ -f "$COMMON_CONFIG_ROOT/EXTERNAL-SOURCES.txt" ]]; then
    cp -a "$COMMON_CONFIG_ROOT/EXTERNAL-SOURCES.txt" "$WORK_DIRECTORY/EXTERNAL-SOURCES.txt"
fi

tar -C "$(dirname -- "$WORK_DIRECTORY")" \
    --sort=name \
    --mtime='UTC 1970-01-01' \
    --owner=0 --group=0 --numeric-owner \
    -czf "$OUTPUT_DIRECTORY/mpv-lazy-$VERSION-linux-config.tar.gz" \
    mpv-lazy

metadata=(
    "release=$VERSION"
    "source_commit=$(git -C "$SOURCE_ROOT" rev-parse HEAD)"
    'common_config=packaging/portable_config plus external source overlay'
    'platform_patch=packaging/linux.patch'
    "platform_patch_sha256=$(sha256sum "$PLATFORM_PATCH" | cut -d' ' -f1)"
    'contents=portable_config-only'
    'runtime=provided-by-user'
)
printf '%s\n' "${metadata[@]}" > "$OUTPUT_DIRECTORY/BUILD-METADATA-linux.txt"

(
    cd -- "$OUTPUT_DIRECTORY"
    find . -maxdepth 1 -type f \
        ! -name 'SHA256SUMS-linux.txt' \
        -printf '%f\n' | sort | xargs sha256sum
) > "$OUTPUT_DIRECTORY/SHA256SUMS-linux.txt"

rm -rf "$OUTPUT_DIRECTORY/_work"
echo "Built Linux configuration assets in $OUTPUT_DIRECTORY"
