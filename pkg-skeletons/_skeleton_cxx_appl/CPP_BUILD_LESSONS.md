# C++ Build Lessons Learned

This document captures key lessons learned from building C++ applications in conda-forge environments, specifically from the `mumble-voip` package build experience.

## Summary

The `mumble-voip` build initially failed with multiple issues that are common in C++ conda builds. This document details these issues and their solutions, which have been incorporated into the updated C++ skeleton templates.

## Issues Encountered and Solutions

### 1. Boost Library Dependencies

**Problem:**
- Build failed with `fatal error: boost/filesystem.hpp: No such file or directory`
- Initially used `libboost-devel` which didn't provide the correct headers during build

**Solution:**
- Use `boost-cpp` in both `build` and `host` requirements
- Add CMake flags to help find Boost: `-DCMAKE_PREFIX_PATH=$BUILD_PREFIX -DBOOST_ROOT=$BUILD_PREFIX`

**Applied to Skeletons:**
```yaml
requirements:
  build:
    - boost-cpp
  host:
    - boost-cpp
```

### 2. C23 Standard Compatibility Issues

**Problem:**
- Error: `'bool' cannot be defined via 'typedef'` with message `'bool' is a keyword with '-std=c23' onwards`
- Modern conda compilers default to C23 where `bool` is a keyword, breaking legacy code that typedefs it

**Solution:**
- Explicitly use C11 standard: `-std=c11`
- Added to CMake C flags in skeleton

**Applied to Skeletons:**
```yaml
let c_flags = [
    "-Wno-error=cpp",
    "-Wno-cpp", 
    "-std=c11",  # Use C11 to avoid C23 bool conflicts
]
```

### 3. Deprecated C++17 Features

**Problem:**
- Error: `'std::wstring_convert' is deprecated [-Werror=deprecated-declarations]`
- Compilation treats warnings as errors, blocking builds with deprecated C++17 features

**Solution:**
- Add `-Wno-deprecated-declarations` to C++ flags
- Also add general warning suppression flags

**Applied to Skeletons:**
```yaml
let cxx_flags = [
    "-Wno-error=cpp",
    "-Wno-cpp",
    "-Wno-deprecated-declarations",  # Ignore deprecated C++17 features
]
```

### 4. CMake Installation Path Issues

**Problem:**
- CMake install tried to install to `/usr/local/lib64/mumble` requiring admin privileges
- Default CMAKE_INSTALL_PREFIX not set for conda environment

**Solution:**
- Set `-DCMAKE_INSTALL_PREFIX=$PREFIX` to install to conda environment
- Add fallback manual installation if CMake install fails

**Applied to Skeletons:**
```yaml
cmake_args = [
    "-DCMAKE_INSTALL_PREFIX=($install_prefix)",
    "-DCMAKE_PREFIX_PATH=($install_prefix)",
]

# Fallback manual installation
if $install_result.exit_code != 0 {
    # Manual installation patterns documented
}
```

### 5. Abseil Library Versioning

**Problem:**
- Binary linked against `libabsl_log_internal_check_op.so.2501.0.0` but conda package had different version
- Runtime error: "cannot open shared object file: No such file or directory"

**Solution:**
- Add `abseil-cpp` to both `build` and `host` requirements
- Ensure consistent versioning between build and runtime environments

**Applied to Skeletons:**
```yaml
requirements:
  build:
    - abseil-cpp
  host:
    - abseil-cpp
```

### 6. Protocol Buffers Dependencies

**Problem:**
- CMake error: "Protobuf not found" despite having protobuf packages
- Need both static libraries for linking and dynamic for runtime

**Solution:**
- Add both `libprotobuf-static` and `libprotobuf` to build requirements
- Add `libprotobuf` to host requirements
- Add `protobuf` compiler to build requirements

**Applied to Skeletons:**
```yaml
requirements:
  build:
    - protobuf               # Protocol Buffers compiler
    - libprotobuf-static     # Static protobuf libraries for linking
    - libprotobuf            # Dynamic protobuf libraries
  host:
    - libprotobuf            # Protocol Buffers runtime
```

### 7. Test Command Exit Codes

**Problem:**
- Test failed because `mumble --help` exits with code 1 (normal for help commands)
- Test framework expected exit code 0

**Solution:**
- Use `--version` instead of `--help` for basic functionality tests
- Document that `--help` often exits with code 1

**Applied to Skeletons:**
```yaml
tests:
  - script:
      - ${{ name }} --version  # Use --version instead of --help
```

## Best Practices for C++ Conda Builds

### 1. Compiler Flags

Always include these defensive compiler flags:

```cmake
-DCMAKE_CXX_FLAGS="-Wno-error=cpp -Wno-cpp -Wno-deprecated-declarations"
-DCMAKE_C_FLAGS="-Wno-error=cpp -Wno-cpp -std=c11"
```

### 2. CMake Configuration

Standard CMake flags for conda builds:

```cmake
-DCMAKE_BUILD_TYPE=Release
-DCMAKE_INSTALL_PREFIX=$PREFIX
-DCMAKE_PREFIX_PATH=$BUILD_PREFIX
-DBOOST_ROOT=$BUILD_PREFIX  # If using Boost
```

### 3. Dependency Patterns

For libraries that need both build-time and runtime components:

```yaml
requirements:
  build:
    - library-name           # Compiler/headers
    - library-name-static    # Static linking (if available)
  host:
    - library-name           # Runtime libraries
```

### 4. Manual Installation Fallback

Always provide manual installation as fallback:

```nushell
if $install_result.exit_code != 0 {
    print "CMake install failed, attempting manual installation..."
    mkdir ($install_prefix | path join "bin")
    cp main_executable ($install_prefix | path join "bin" $env.PKG_NAME)
}
```

### 5. Test Strategy

1. Use `--version` for basic executable tests
2. Check shared library dependencies with `ldd` (Unix)
3. Test actual functionality, not just help output
4. Validate installation directory contents

### 6. Common Dependencies

Modern C++ applications often need:

**Core Libraries:**
- `boost-cpp` - Boost C++ libraries
- `abseil-cpp` - Google Abseil libraries
- `fmt` - Modern C++ formatting
- `nlohmann_json` - JSON library

**System Libraries:**
- `openssl` - Cryptography
- `libcurl` - HTTP client
- `libprotobuf` - Protocol Buffers

**UI Libraries:**
- `qt-main` or `qt6-main` - Qt framework
- `gtk3` or `gtk4` - GTK framework

**Audio/Media:**
- `libopus`, `libsndfile`, `libogg`, `libvorbis`
- `alsa-lib` (Linux audio)

## Files Updated

The following skeleton files were updated with these lessons:

1. **`_skeleton_cxx_appl/recipe.yaml`** - Complete C++ application skeleton
   - Added defensive compiler flags
   - Comprehensive dependency examples
   - Manual installation fallback
   - Improved testing strategy

2. **`_skeleton_cxx_hdr/recipe.yaml`** - Header-only library skeleton
   - Updated build configuration
   - Better dependency documentation
   - Improved compilation tests

## References

- Original failing build: `mumble-voip` package
- Build logs and error messages in meso-forge project
- Conda-forge documentation for C++ packages
- CMake best practices for conda environments