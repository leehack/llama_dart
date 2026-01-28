#!/bin/bash
set -e

# build_apple.sh <platform> [clean]
# Example: ./scripts/build_apple.sh macos
# Example: ./scripts/build_apple.sh ios

PLATFORM=$1
CLEAN=$2

if [ "$PLATFORM" == "macos" ]; then
    echo "========================================"
    echo "Building for macOS (Universal)..."
    echo "========================================"
    BUILD_DIR="build-macos"
    if [ "$CLEAN" == "clean" ]; then rm -rf "$BUILD_DIR"; fi
    
    mkdir -p "$BUILD_DIR"
    cmake -S src/native/llama_cpp -B "$BUILD_DIR" \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON \
      -DLLAMA_BUILD_COMMON=OFF \
      -DLLAMA_BUILD_TESTS=OFF \
      -DLLAMA_BUILD_EXAMPLES=OFF \
      -DLLAMA_BUILD_SERVER=OFF \
      -DLLAMA_BUILD_TOOLS=OFF \
      -DGGML_METAL=ON \
      -DGGML_METAL_USE_BF16=ON \
      -DGGML_METAL_EMBED_LIBRARY=ON \
      -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
    
    cmake --build "$BUILD_DIR" --config Release -j $(sysctl -n hw.logicalcpu)
    
    # Artifacts
    MAC_FRAMEWORKS_DIR="macos/Frameworks"
    # Clean and recreate to ensure no leftovers (like libllama_cpp)
    rm -rf "$MAC_FRAMEWORKS_DIR"
    mkdir -p "$MAC_FRAMEWORKS_DIR"
    
    echo "Copying libraries to $MAC_FRAMEWORKS_DIR (cleaning leftovers)..."
    # Copy only the main .dylib files, avoid versioned aliases (e.g. libllama.0.dylib or libllama.0.0.7865.dylib)
    # The pattern excludes any file that has a dot followed immediately by a digit
    find "$BUILD_DIR" -name "*.dylib" ! -name "*.[0-9]*.dylib" -exec cp -L {} "$MAC_FRAMEWORKS_DIR/" \;

    echo "Patching dylib IDs and dependencies..."
    # 1. Update IDs for all dylibs to be just @rpath/libname.dylib
    for dylib in "$MAC_FRAMEWORKS_DIR"/*.dylib; do
        if [ -f "$dylib" ]; then
            filename=$(basename "$dylib")
            install_name_tool -id "@rpath/$filename" "$dylib"
        fi
    done

    # 2. Update dependencies between dylibs to point to the clean names
    # This fixes libllama.dylib looking for libggml.0.dylib, etc.
    for dylib in "$MAC_FRAMEWORKS_DIR"/*.dylib; do
        if [ -f "$dylib" ]; then
            # Get list of dependencies
            deps=$(otool -L "$dylib" | grep "@rpath" | awk '{print $1}')
            for dep in $deps; do
                # If dependency has a version number (e.g. @rpath/libggml.0.dylib)
                if [[ "$dep" =~ \.[0-9]+\.dylib$ ]]; then
                    # Create clean name (e.g. @rpath/libggml.dylib)
                    clean_dep=$(echo "$dep" | sed -E 's/\.[0-9]+\.dylib$/.dylib/')
                    
                    # If we have the clean file in our frameworks dir, update the linkage
                    clean_filename=$(basename "$clean_dep")
                    if [ -f "$MAC_FRAMEWORKS_DIR/$clean_filename" ]; then
                        install_name_tool -change "$dep" "$clean_dep" "$dylib"
                        echo "  Updated $dep -> $clean_dep in $(basename "$dylib")"
                    fi
                fi
            done
        fi
    done
    
    echo "macOS build complete: $MAC_FRAMEWORKS_DIR"

elif [ "$PLATFORM" == "ios" ]; then
    echo "========================================"
    echo "Building for iOS (using llama.cpp/build-xcframework.sh)..."
    echo "========================================"
    
    LLAMA_CPP_DIR="src/native/llama_cpp"
    OUTPUT_DIR="ios/Frameworks"
    
    # Run the official script from its directory
    pushd "$LLAMA_CPP_DIR" > /dev/null
    ./build-xcframework.sh
    popd > /dev/null
    
    # Copy/Move the result to our expected location
    mkdir -p "$OUTPUT_DIR"
    rm -rf "$OUTPUT_DIR/llama.xcframework"
    # Copy without renaming
    cp -r "$LLAMA_CPP_DIR/build-apple/llama.xcframework" "$OUTPUT_DIR/llama.xcframework"
    
    echo "iOS XCFramework update complete: $OUTPUT_DIR/llama.xcframework"

else
    echo "Error: Invalid platform '$PLATFORM'. Use 'macos' or 'ios'."
    exit 1
fi
