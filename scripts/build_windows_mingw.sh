#!/bin/bash
set -e

# build_windows_mingw.sh <backend> [clean]
# Example: ./scripts/build_windows_mingw.sh cpu
# Example: ./scripts/build_windows_mingw.sh vulkan
# Cross-compile Windows binaries on Linux using MinGW-w64

BACKEND=$1
CLEAN=$2

# Validate backend parameter
if [ -z "$BACKEND" ]; then
    echo "Error: Backend parameter is required."
    echo "Usage: $0 <backend> [clean]"
    echo "  backend: 'cpu' or 'vulkan'"
    echo "Example: $0 cpu"
    exit 1
fi

# Check for required MinGW tools
if ! command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
    echo "Error: MinGW-w64 cross-compiler not found."
    echo "Please install it first:"
    echo "  Ubuntu/Debian: sudo apt-get install mingw-w64"
    exit 1
fi

BUILD_DIR="build-windows-$BACKEND"
if [ "$CLEAN" == "clean" ]; then 
    rm -rf "$BUILD_DIR"
fi

CMAKE_ARGS=(
    "-DCMAKE_BUILD_TYPE=Release"
    "-DBUILD_SHARED_LIBS=OFF"
    "-DLLAMA_BUILD_COMMON=OFF"
    "-DLLAMA_BUILD_TESTS=OFF"
    "-DLLAMA_BUILD_EXAMPLES=OFF"
    "-DLLAMA_BUILD_SERVER=OFF"
    "-DLLAMA_BUILD_TOOLS=OFF"
    "-DLLAMA_HTTPLIB=OFF"
    "-DLLAMA_OPENSSL=OFF"
    "-DCMAKE_SYSTEM_NAME=Windows"
    "-DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc"
    "-DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++"
    "-DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres"
    "-DCMAKE_C_FLAGS=-D_WIN32_WINNT=0x0601"
    "-DCMAKE_CXX_FLAGS=-D_WIN32_WINNT=0x0601"
)

if [ "$BACKEND" == "vulkan" ]; then
    echo "============================"
    echo "Building for Windows (Vulkan) with MinGW"
    echo "============================"
    
    # Check for glslc (required for shader compilation)
    if ! command -v glslc >/dev/null 2>&1; then
        echo "Error: glslc shader compiler not found."
        echo "Please install it first:"
        echo "  Ubuntu/Debian: sudo apt-get install glslc libvulkan-dev"
        exit 1
    fi
    
    # Set Vulkan paths for cross-compilation
    # Use the Vulkan-Headers submodule for headers
    VULKAN_HEADERS_DIR="$(pwd)/src/native/Vulkan-Headers/include"
    
    # Create a Windows-compatible Vulkan import library
    VULKAN_MINGW_DIR="/tmp/vulkan-mingw-$BACKEND"
    mkdir -p "$VULKAN_MINGW_DIR"
    
    if [ ! -f "$VULKAN_MINGW_DIR/libvulkan-1.a" ]; then
        echo "Creating Windows Vulkan import library..."
        cat > "$VULKAN_MINGW_DIR/vulkan-1.def" << 'EOFDEF'
LIBRARY vulkan-1.dll
EXPORTS
vkCreateInstance
vkDestroyInstance
vkEnumeratePhysicalDevices
vkGetPhysicalDeviceFeatures
vkGetPhysicalDeviceProperties
vkGetPhysicalDeviceQueueFamilyProperties
vkGetPhysicalDeviceMemoryProperties
vkGetInstanceProcAddr
vkGetDeviceProcAddr
vkCreateDevice
vkDestroyDevice
vkEnumerateInstanceExtensionProperties
vkEnumerateDeviceExtensionProperties
vkGetDeviceQueue
vkQueueSubmit
vkQueueWaitIdle
vkDeviceWaitIdle
vkAllocateMemory
vkFreeMemory
vkMapMemory
vkUnmapMemory
vkBindBufferMemory
vkBindImageMemory
vkGetBufferMemoryRequirements
vkGetImageMemoryRequirements
vkCreateFence
vkDestroyFence
vkResetFences
vkWaitForFences
vkCreateSemaphore
vkDestroySemaphore
vkCreateBuffer
vkDestroyBuffer
vkCreateImage
vkDestroyImage
vkCreateImageView
vkDestroyImageView
vkCreateShaderModule
vkDestroyShaderModule
vkCreateComputePipelines
vkDestroyPipeline
vkCreatePipelineLayout
vkDestroyPipelineLayout
vkCreateDescriptorSetLayout
vkDestroyDescriptorSetLayout
vkCreateDescriptorPool
vkDestroyDescriptorPool
vkAllocateDescriptorSets
vkUpdateDescriptorSets
vkCreateCommandPool
vkDestroyCommandPool
vkAllocateCommandBuffers
vkBeginCommandBuffer
vkEndCommandBuffer
vkCmdBindPipeline
vkCmdBindDescriptorSets
vkCmdDispatch
vkCmdCopyBuffer
vkCmdPipelineBarrier
vkGetPhysicalDeviceFeatures2
vkGetPhysicalDeviceProperties2
vkGetPhysicalDeviceMemoryProperties2
vkBindBufferMemory2
vkBindImageMemory2
vkGetImageMemoryRequirements2
vkGetBufferMemoryRequirements2
EOFDEF
        x86_64-w64-mingw32-dlltool -d "$VULKAN_MINGW_DIR/vulkan-1.def" -l "$VULKAN_MINGW_DIR/libvulkan-1.a" -D vulkan-1.dll
        echo "Created: $VULKAN_MINGW_DIR/libvulkan-1.a"
    fi
    
    # Point CMake to the Windows Vulkan library
    CMAKE_ARGS+=("-DGGML_VULKAN=ON")
    CMAKE_ARGS+=("-DVulkan_INCLUDE_DIR=${VULKAN_HEADERS_DIR}")
    CMAKE_ARGS+=("-DVulkan_LIBRARY=${VULKAN_MINGW_DIR}/libvulkan-1.a")
    CMAKE_ARGS+=("-DVulkan_GLSLC_EXECUTABLE=$(which glslc)")
    
    echo "Using Vulkan headers from: ${VULKAN_HEADERS_DIR}"
    echo "Using Vulkan library: ${VULKAN_MINGW_DIR}/libvulkan-1.a"
    echo "Using glslc from: $(which glslc)"
elif [ "$BACKEND" == "cpu" ]; then
    echo "============================"
    echo "Building for Windows (CPU) with MinGW"
    echo "============================"
else
    echo "Error: Invalid backend '$BACKEND'. Use 'vulkan' or 'cpu'."
    exit 1
fi

mkdir -p "$BUILD_DIR"

# Point to src/native (parent of llama_cpp)
cmake -S src/native -B "$BUILD_DIR" "${CMAKE_ARGS[@]}"
cmake --build "$BUILD_DIR" --config Release -j $(nproc)

# Artifacts
LIB_DIR="windows/lib"
# Clean and recreate to ensure no leftovers
rm -rf "$LIB_DIR"
mkdir -p "$LIB_DIR"

echo "Copying libraries to $LIB_DIR..."
# Find and copy all .dll files
find "$BUILD_DIR" -name "*.dll" -exec cp {} "$LIB_DIR/" \;

# Verify that the expected DLL was created
if [ ! -f "$LIB_DIR/libllama.dll" ]; then
    echo "Error: Expected libllama.dll not found in $LIB_DIR"
    exit 1
fi

echo "Windows build complete: $LIB_DIR"
ls -lh "$LIB_DIR"
