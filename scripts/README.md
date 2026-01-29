# Build Scripts

This directory contains platform-specific build scripts for compiling native libraries.

## Platform-Specific Scripts

### Android
```bash
./build_android.sh
```
Builds `.so` libraries for Android architectures (`arm64-v8a`, `x86_64`) with Vulkan support.

### iOS / macOS
```bash
./build_apple.sh ios     # Build iOS XCFramework
./build_apple.sh macos   # Build macOS Universal binary
```
Builds frameworks for Apple platforms with Metal acceleration.

### Linux
```bash
./build_linux.sh vulkan [arch] [clean]
```
Builds Linux libraries with Vulkan support. Supports native and cross-compilation for:
- `x86_64` (x64)
- `aarch64` (arm64)

Example:
```bash
./build_linux.sh vulkan x86_64
./build_linux.sh vulkan arm64 clean
```

### Windows

#### Option 1: Native Build (PowerShell on Windows)
```powershell
# Requires Visual Studio 2022 and CMake
.\build_windows.ps1 cpu      # Build CPU-only backend
.\build_windows.ps1 vulkan   # Build with Vulkan support (requires Vulkan SDK)
```

#### Option 2: Cross-Compile from Linux (MinGW)
```bash
# Install MinGW first: sudo apt-get install mingw-w64
./build_windows_mingw.sh cpu      # Build CPU-only backend
# Note: Vulkan backend is not supported via MinGW cross-compilation
# Use the native Windows PowerShell build for Vulkan support
```

**Note**: The CPU backend works without additional dependencies. Vulkan backend requires native Windows build with the [Vulkan SDK](https://vulkan.lunarg.com/).

### Docker Verification (Linux)
```bash
./verify_linux_docker.sh vulkan
```
Builds and tests Linux binaries in a Docker container to ensure compatibility.

## Build Artifacts

Build outputs are placed in platform-specific directories:
- **Android**: `android/src/main/jniLibs/{arch}/libllama.so`
- **iOS**: `ios/Frameworks/llama.xcframework`
- **macOS**: `macos/Frameworks/libllama.dylib`
- **Linux**: `linux/lib/{arch}/libllama.so`
- **Windows**: `windows/lib/libllama.dll`

## Common Options

All scripts support a `clean` argument to remove existing build artifacts:
```bash
./build_linux.sh vulkan x86_64 clean
./build_windows_mingw.sh cpu clean
```

## Requirements

### All Platforms
- CMake 3.14+
- Git (for submodules)

### Platform-Specific
- **Android**: Android NDK 26+
- **iOS/macOS**: Xcode Command Line Tools
- **Linux**: GCC/G++ or Clang, libvulkan-dev (for Vulkan)
- **Windows**: 
  - Native: Visual Studio 2022, Vulkan SDK (for Vulkan)
  - Cross-compile: MinGW-w64 on Linux

## Troubleshooting

### Submodules not initialized
```bash
git submodule update --init --recursive
```

### MinGW compilation errors
Ensure you have MinGW-w64 version 11+ and GCC 13+:
```bash
dpkg -l | grep mingw
x86_64-w64-mingw32-gcc --version
```

### Vulkan not found
- **Linux**: Install `libvulkan-dev`
- **Windows**: Install the [Vulkan SDK](https://vulkan.lunarg.com/)
- **Cross-compile**: Windows Vulkan SDK must be available to MinGW

For more detailed instructions, see [CONTRIBUTING.md](../CONTRIBUTING.md).
