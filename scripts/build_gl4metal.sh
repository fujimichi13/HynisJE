#!/bin/bash
set -euo pipefail

source_dir=$1
output_dir=$2
sdk=$3
configuration=$4
jobs=$5
library=${6:-}
mkdir -p "$output_dir"

if [[ -z "$library" ]]; then
    if [[ ! -f "$source_dir/external/glslang/CMakeLists.txt" || ! -f "$source_dir/external/SPIRV-Cross/CMakeLists.txt" ]]; then
        echo 'Initialize gl4metal and its dependencies with git submodule update --init --recursive.' >&2
        exit 1
    fi
    cmake -S "$source_dir" -B "$output_dir/gl4metal" \
        -DCMAKE_BUILD_TYPE="$configuration" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
        -DCMAKE_C_COMPILER_TARGET=arm64-apple-ios14.0 \
        -DCMAKE_CXX_COMPILER_TARGET=arm64-apple-ios14.0 \
        -DCMAKE_OSX_SYSROOT="$sdk" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
        -DCMAKE_INSTALL_NAME_DIR=@rpath \
        -DCMAKE_BUILD_WITH_INSTALL_NAME_DIR=ON \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    cmake --build "$output_dir/gl4metal" --config "$configuration" --target gl4metal -j "$jobs"
    library="$output_dir/gl4metal/libgl4metal.dylib"
fi

"${PYTHON:-python3}" "$(dirname "$0")/validate_gl4metal.py" "$library"
# Stage where the existing payload recipe copies and signs all renderer dylibs.
if [[ ! "$library" -ef "$output_dir/libgl4metal.dylib" ]]; then
    cp "$library" "$output_dir/libgl4metal.dylib"
fi
