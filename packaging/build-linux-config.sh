#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: build-linux-config.sh \
  --source-root PATH \
  --common-config-root PATH \
  --platform-patch PATH \
  --output-directory PATH \
  --version VERSION \
  [--python-executable PATH \
   --vapoursynth-wheel PATH \
   --k7sfunc-wheel PATH \
   --ort-wheel PATH \
   --mvtools-wheel PATH \
   --models-archive PATH \
   --contrib-models-archive PATH \
   [--include-cuda --cuda-wheel PATH]]
EOF
}

SOURCE_ROOT=
COMMON_CONFIG_ROOT=
PLATFORM_PATCH=
OUTPUT_DIRECTORY=
VERSION=
PYTHON_EXECUTABLE=python3
VAPOURSYNTH_WHEEL=
K7SFUNC_WHEEL=
ORT_WHEEL=
MVTOOLS_WHEEL=
MODELS_ARCHIVE=
CONTRIB_MODELS_ARCHIVE=
CUDA_WHEEL=
INCLUDE_CUDA=false

while (($# > 0)); do
    case "$1" in
        --source-root) SOURCE_ROOT=$2; shift 2 ;;
        --common-config-root|--standard-config-root) COMMON_CONFIG_ROOT=$2; shift 2 ;;
        --platform-patch) PLATFORM_PATCH=$2; shift 2 ;;
        --output-directory) OUTPUT_DIRECTORY=$2; shift 2 ;;
        --version) VERSION=$2; shift 2 ;;
        --python-executable) PYTHON_EXECUTABLE=$2; shift 2 ;;
        --vapoursynth-wheel) VAPOURSYNTH_WHEEL=$2; shift 2 ;;
        --k7sfunc-wheel) K7SFUNC_WHEEL=$2; shift 2 ;;
        --ort-wheel) ORT_WHEEL=$2; shift 2 ;;
        --mvtools-wheel) MVTOOLS_WHEEL=$2; shift 2 ;;
        --models-archive) MODELS_ARCHIVE=$2; shift 2 ;;
        --contrib-models-archive) CONTRIB_MODELS_ARCHIVE=$2; shift 2 ;;
        --cuda-wheel) CUDA_WHEEL=$2; shift 2 ;;
        --include-cuda) INCLUDE_CUDA=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z "$SOURCE_ROOT" || -z "$COMMON_CONFIG_ROOT" || -z "$PLATFORM_PATCH" || -z "$OUTPUT_DIRECTORY" || -z "$VERSION" ]]; then
    usage >&2
    exit 2
fi

runtime_values=(
    "$VAPOURSYNTH_WHEEL"
    "$K7SFUNC_WHEEL"
    "$ORT_WHEEL"
    "$MVTOOLS_WHEEL"
    "$MODELS_ARCHIVE"
    "$CONTRIB_MODELS_ARCHIVE"
)
runtime_enabled=false
for value in "${runtime_values[@]}"; do
    if [[ -n "$value" ]]; then
        runtime_enabled=true
        break
    fi
done
if [[ "$runtime_enabled" == true ]]; then
    for value in "${runtime_values[@]}"; do
        if [[ -z "$value" ]]; then
            echo 'All Linux runtime wheel and model arguments are required together' >&2
            usage >&2
            exit 2
        fi
    done
fi
if [[ "$INCLUDE_CUDA" == true && -z "$CUDA_WHEEL" ]]; then
    echo '--include-cuda requires --cuda-wheel' >&2
    exit 2
fi
if [[ "$INCLUDE_CUDA" == true && "$runtime_enabled" != true ]]; then
    echo '--include-cuda requires the Linux runtime arguments' >&2
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
if ! command -v sha256sum >/dev/null 2>&1; then
    echo 'sha256sum is required to write release checksums' >&2
    exit 1
fi
if [[ "$runtime_enabled" == true ]]; then
    if [[ "$PYTHON_EXECUTABLE" == */* ]]; then
        if [[ ! -x "$PYTHON_EXECUTABLE" ]]; then
            echo "The Python executable is not executable: $PYTHON_EXECUTABLE" >&2
            exit 1
        fi
    else
        PYTHON_EXECUTABLE=$(command -v "$PYTHON_EXECUTABLE" || true)
        if [[ -z "$PYTHON_EXECUTABLE" ]]; then
            echo 'A Python 3.12+ executable is required for the Linux runtime package' >&2
            exit 1
        fi
    fi
    if ! "$PYTHON_EXECUTABLE" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 12) else 1)'; then
        echo 'A Python 3.12+ executable is required for the Linux runtime package' >&2
        exit 1
    fi
    if ! command -v 7z >/dev/null 2>&1; then
        echo '7z is required to extract the Linux model archives' >&2
        exit 1
    fi
    for asset in "${runtime_values[@]}"; do
        if [[ ! -f "$asset" ]]; then
            echo "Linux runtime asset does not exist: $asset" >&2
            exit 1
        fi
    done
    if [[ "$INCLUDE_CUDA" == true && ! -f "$CUDA_WHEEL" ]]; then
        echo "Linux CUDA wheel does not exist: $CUDA_WHEEL" >&2
        exit 1
    fi
fi

WORK_DIRECTORY="$OUTPUT_DIRECTORY/_work/linux-config/mpv-lazy"
rm -rf "$OUTPUT_DIRECTORY/_work"
mkdir -p "$WORK_DIRECTORY"

copy_package_files() {
    local package_root=$1
    cp -a "$COMMON_CONFIG_ROOT/portable_config" "$package_root/portable_config"
    cp -a "$SOURCE_ROOT/packaging/linux/README.txt" "$package_root/README.txt"
    cp -a "$SOURCE_ROOT/LICENSE.MD" "$package_root/LICENSE.MD"
    if [[ -f "$COMMON_CONFIG_ROOT/EXTERNAL-SOURCES.txt" ]]; then
        cp -a "$COMMON_CONFIG_ROOT/EXTERNAL-SOURCES.txt" "$package_root/EXTERNAL-SOURCES.txt"
    fi
    for cache_name in icc shader usubs watch_later; do
        mkdir -p "$package_root/portable_config/_cache/$cache_name"
    done
}

apply_linux_patch() {
    local package_root=$1
    (
        cd -- "$package_root/portable_config"
        patch --batch --forward --strip=1 < "$PLATFORM_PATCH"
    )
}

copy_package_files "$WORK_DIRECTORY"
apply_linux_patch "$WORK_DIRECTORY"

if [[ "$runtime_enabled" == true ]]; then
    RUNTIME_WORK_DIRECTORY="$OUTPUT_DIRECTORY/_work/linux-vs"
    RUNTIME_ROOT="$RUNTIME_WORK_DIRECTORY/mpv-lazy"
    mkdir -p "$RUNTIME_WORK_DIRECTORY"
    cp -a "$WORK_DIRECTORY" "$RUNTIME_ROOT"

    PYTHON_ROOT="$RUNTIME_ROOT/python"
    "$PYTHON_EXECUTABLE" -m pip install \
        --disable-pip-version-check \
        --no-warn-script-location \
        --no-cache-dir \
        --no-deps \
        --target "$PYTHON_ROOT" \
        "$VAPOURSYNTH_WHEEL" "$K7SFUNC_WHEEL" "$ORT_WHEEL" "$MVTOOLS_WHEEL"

    VS_ROOT="$PYTHON_ROOT/vapoursynth"
    ORT_MODEL_ROOT="$VS_ROOT/plugins/ort/models"
    mkdir -p "$ORT_MODEL_ROOT/rife"
    7z e -y "$MODELS_ARCHIVE" 'models/rife/rife_v4.6.onnx' "-o$ORT_MODEL_ROOT/rife" >/dev/null
    7z e -y "$CONTRIB_MODELS_ARCHIVE" 'models/RealESRGANv2/animejanaiV2L1.onnx' "-o$ORT_MODEL_ROOT" >/dev/null
    if [[ ! -f "$ORT_MODEL_ROOT/rife/rife_v4.6.onnx" || ! -f "$ORT_MODEL_ROOT/animejanaiV2L1.onnx" ]]; then
        echo 'The required Linux model files were not found in the supplied archives' >&2
        exit 1
    fi

    mkdir -p "$RUNTIME_ROOT/bin"
    for launcher in run-vapoursynth mpv-lazy vspipe; do
        cp -a "$SOURCE_ROOT/packaging/linux/bin/$launcher" "$RUNTIME_ROOT/bin/$launcher"
        chmod 0755 "$RUNTIME_ROOT/bin/$launcher"
    done

    tar -C "$(dirname -- "$RUNTIME_ROOT")" \
        --sort=name \
        --mtime='UTC 1970-01-01' \
        --owner=0 --group=0 --numeric-owner \
        -czf "$OUTPUT_DIRECTORY/mpv-lazy-$VERSION-linux-vs.tar.gz" \
        mpv-lazy

    if [[ "$INCLUDE_CUDA" == true ]]; then
        CUDA_WORK_DIRECTORY="$OUTPUT_DIRECTORY/_work/linux-cuda"
        CUDA_ROOT="$CUDA_WORK_DIRECTORY/mpv-lazy"
        mkdir -p "$CUDA_ROOT/python"
        "$PYTHON_EXECUTABLE" -m pip install \
            --disable-pip-version-check \
            --no-warn-script-location \
            --no-cache-dir \
            --target "$CUDA_ROOT/python" \
            "$CUDA_WHEEL"

        CUDA_PROVIDER="$CUDA_ROOT/python/vapoursynth/plugins/ort/libonnxruntime_providers_cuda.so"
        if [[ ! -f "$CUDA_PROVIDER" ]]; then
            echo 'The CUDA provider was not found in the supplied wheel' >&2
            exit 1
        fi
        mkdir -p "$CUDA_ROOT/bin"
        cp -a "$SOURCE_ROOT/packaging/linux/bin/mpv-lazy-cuda" "$CUDA_ROOT/bin/mpv-lazy-cuda"
        chmod 0755 "$CUDA_ROOT/bin/mpv-lazy-cuda"
        cat > "$CUDA_ROOT/CUDA-README.txt" <<'EOF'
This is an overlay for the matching mpv-lazy Linux VapourSynth package.
Extract it into the same directory as the CPU package, then launch
bin/mpv-lazy-cuda instead of bin/mpv-lazy.

The NVIDIA display driver must be installed by the host system. The overlay
contains the ONNX Runtime CUDA provider and its redistributable CUDA libraries.
EOF

        tar -C "$CUDA_WORK_DIRECTORY" \
            --sort=name \
            --mtime='UTC 1970-01-01' \
            --owner=0 --group=0 --numeric-owner \
            -czf "$OUTPUT_DIRECTORY/mpv-lazy-$VERSION-linux-vs-cuda.tar.gz" \
            mpv-lazy
    fi
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
)
if [[ "$runtime_enabled" == true ]]; then
    metadata+=(
        'contents=portable_config plus VapourSynth/K7sfunc/VS-MLRT runtime'
        'runtime=PyPI wheels staged under python/'
        "vapoursynth_wheel=$(basename -- "$VAPOURSYNTH_WHEEL")"
        "k7sfunc_wheel=$(basename -- "$K7SFUNC_WHEEL")"
        "vapoursynth_mlrt_ort_wheel=$(basename -- "$ORT_WHEEL")"
        "vapoursynth_mvtools_wheel=$(basename -- "$MVTOOLS_WHEEL")"
        'models=rife_v4.6.onnx,animejanaiV2L1.onnx'
        "include_cuda=$INCLUDE_CUDA"
    )
    if [[ "$INCLUDE_CUDA" == true ]]; then
        metadata+=("vapoursynth_mlrt_ort_cuda_wheel=$(basename -- "$CUDA_WHEEL")")
    fi
else
    metadata+=(
        'contents=portable_config-only'
        'runtime=provided-by-user'
    )
fi
printf '%s\n' "${metadata[@]}" > "$OUTPUT_DIRECTORY/BUILD-METADATA-linux.txt"

(
    cd -- "$OUTPUT_DIRECTORY"
    find . -maxdepth 1 -type f \
        ! -name 'SHA256SUMS-linux.txt' \
        -printf '%f\n' | sort | xargs sha256sum
) > "$OUTPUT_DIRECTORY/SHA256SUMS-linux.txt"

rm -rf "$OUTPUT_DIRECTORY/_work"
echo "Built Linux configuration assets in $OUTPUT_DIRECTORY"
