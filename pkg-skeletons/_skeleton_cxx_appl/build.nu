#!/usr/bin/env nu
# External build script for complex C++ application builds
# This script is used when the build process is too complex for inline YAML
# Place this file next to recipe.yaml and reference it with:
#   build:
#     script: build.nu

# Build configuration
let config = {
    # Determine platform-specific settings
    install_prefix: (if ($nu.os-info.name == "windows") { $env.LIBRARY_PREFIX } else { $env.PREFIX })
    bin_dir: (if ($nu.os-info.name == "windows") {
        ($env.LIBRARY_PREFIX | path join "bin")
    } else {
        ($env.PREFIX | path join "bin")
    })
    lib_dir: (if ($nu.os-info.name == "windows") {
        ($env.LIBRARY_PREFIX | path join "lib")
    } else {
        ($env.PREFIX | path join "lib")
    })
    include_dir: (if ($nu.os-info.name == "windows") {
        ($env.LIBRARY_PREFIX | path join "include")
    } else {
        ($env.PREFIX | path join "include")
    })
    is_windows: ($nu.os-info.name == "windows")
    is_macos: ($nu.os-info.name == "macos")
    is_linux: ($nu.os-info.name == "linux")

    # Build options (can be overridden by environment variables)
    build_tests: ($env.BUILD_TESTS? | default false | into bool)
    build_examples: ($env.BUILD_EXAMPLES? | default false | into bool)
    build_docs: ($env.BUILD_DOCS? | default false | into bool)
    build_type: ($env.CMAKE_BUILD_TYPE? | default "Release")

    # Compiler settings
    use_clang: ($env.USE_CLANG? | default false | into bool)
    enable_lto: ($env.ENABLE_LTO? | default false | into bool)
    enable_static: ($env.ENABLE_STATIC? | default false | into bool)

    # Number of parallel jobs
    job_count: ($env.CPU_COUNT? | default (sys | get cpu | length) | into int)
}

# Logging functions
def "log info" [message: string] {
    print $"[($env.PKG_NAME)] INFO: ($message)"
}

def "log warning" [message: string] {
    print $"[(ansi yellow)($env.PKG_NAME)] WARNING: ($message)(ansi reset)"
}

def "log error" [message: string] {
    print $"[(ansi red)($env.PKG_NAME)] ERROR: ($message)(ansi reset)"
}

def "log success" [message: string] {
    print $"[(ansi green)($env.PKG_NAME)] SUCCESS: ($message)(ansi reset)"
}

# Function to detect build system
def detect-build-system [] {
    # Priority order for build system detection
    let build_systems = [
        {file: "CMakeLists.txt", name: "cmake"}
        {file: "meson.build", name: "meson"}
        {file: "configure.ac", name: "autotools"}
        {file: "configure", name: "configure"}
        {file: "Makefile", name: "make"}
        {file: "SConstruct", name: "scons"}
        {file: "build.zig", name: "zig"}
        {file: "Cargo.toml", name: "cargo"}  # For mixed Rust/C++ projects
    ]

    for system in $build_systems {
        if ($system.file | path exists) {
            return $system.name
        }
    }

    return null
}

# Build with CMake
def build-cmake [] {
    log info "Building with CMake..."

    # Create build directory
    mkdir build
    cd build

    # Base CMake arguments
    mut cmake_args = [
        $"-DCMAKE_INSTALL_PREFIX=($config.install_prefix)"
        $"-DCMAKE_BUILD_TYPE=($config.build_type)"
        $"-DCMAKE_PREFIX_PATH=($config.install_prefix)"
    ]

    # Platform-specific generator
    if $config.is_windows {
        if (which cl | length) > 0 {
            # MSVC detected
            $cmake_args = (["cmake", "-G", "Visual Studio 17 2022"] | append $cmake_args)
        } else {
            # MinGW or other
            $cmake_args = (["cmake", "-GNinja"] | append $cmake_args)
        }
    } else {
        # Unix-like systems prefer Ninja if available
        if (which ninja | length) > 0 {
            $cmake_args = (["cmake", "-GNinja"] | append $cmake_args)
        } else {
            $cmake_args = (["cmake", "-G", "Unix Makefiles"] | append $cmake_args)
        }
    }

    # Add common options
    $cmake_args = ($cmake_args | append [
        $"-DBUILD_TESTING=($config.build_tests | into string | str upcase)"
        $"-DBUILD_EXAMPLES=($config.build_examples | into string | str upcase)"
        "-DBUILD_SHARED_LIBS=ON"
    ])

    # Compiler options
    if $config.use_clang {
        $cmake_args = ($cmake_args | append "-DCMAKE_C_COMPILER=clang")
        $cmake_args = ($cmake_args | append "-DCMAKE_CXX_COMPILER=clang++")
    }

    # LTO (Link Time Optimization)
    if $config.enable_lto {
        $cmake_args = ($cmake_args | append "-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON")
    }

    # Static build
    if $config.enable_static {
        $cmake_args = ($cmake_args | append "-DBUILD_SHARED_LIBS=OFF")
        $cmake_args = ($cmake_args | append "-DCMAKE_FIND_LIBRARY_SUFFIXES=.a")
    }

    # Platform-specific options
    if $config.is_macos {
        if ($env.MACOSX_DEPLOYMENT_TARGET? != null) {
            $cmake_args = ($cmake_args | append $"-DCMAKE_OSX_DEPLOYMENT_TARGET=($env.MACOSX_DEPLOYMENT_TARGET)")
        }
    } else if $config.is_linux {
        # Enable RPATH handling
        $cmake_args = ($cmake_args | append "-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON")
        $cmake_args = ($cmake_args | append "-DCMAKE_BUILD_RPATH_USE_ORIGIN=ON")
    }

    # Add any extra CMAKE_ARGS from environment
    if ($env.CMAKE_ARGS? != null) and (($env.CMAKE_ARGS? | str trim | str length) > 0) {
        $cmake_args = ($cmake_args | append ($env.CMAKE_ARGS | split row " " | where {|x| ($x | str trim | str length) > 0}))
    }

    # Add source directory
    $cmake_args = ($cmake_args | append $env.SRC_DIR)

    # Configure
    log info $"Configuring with: ($cmake_args | str join ' ')"
    run-external ...$cmake_args

    # Build
    log info $"Building with ($config.job_count) parallel jobs..."
    run-external cmake "--build" "." "--parallel" ($config.job_count | into string)

    # Run tests if enabled
    if $config.build_tests {
        log info "Running tests..."
        run-external ctest "--output-on-failure" "--parallel" ($config.job_count | into string)
    }

    # Install
    log info "Installing..."
    run-external cmake "--install" "."

    # Install strip if in Release mode
    if $config.build_type == "Release" and not $config.is_windows {
        log info "Stripping binaries..."
        run-external cmake "--install" "." "--strip"
    }

    cd ..
}

# Build with Meson
def build-meson [] {
    log info "Building with Meson..."

    # Meson setup arguments
    mut meson_args = [
        "setup"
        "builddir"
        $"--prefix=($config.install_prefix)"
        $"--buildtype=($config.build_type | str downcase)"
        "--default-library=shared"
    ]

    # Add options based on config
    if not $config.build_tests {
        $meson_args = ($meson_args | append "-Dtests=false")
    }

    if not $config.build_examples {
        $meson_args = ($meson_args | append "-Dexamples=false")
    }

    if $config.enable_static {
        $meson_args = ($meson_args | filter {|x| $x != "--default-library=shared"})
        $meson_args = ($meson_args | append "--default-library=static")
    }

    # Configure
    log info $"Configuring with: meson ($meson_args | str join ' ')"
    run-external meson ...$meson_args

    # Build
    log info $"Building with ($config.job_count) parallel jobs..."
    run-external meson "compile" "-C" "builddir" "-j" ($config.job_count | into string)

    # Test if enabled
    if $config.build_tests {
        log info "Running tests..."
        run-external meson "test" "-C" "builddir"
    }

    # Install
    log info "Installing..."
    run-external meson "install" "-C" "builddir"

    # Strip binaries if in release mode
    if $config.build_type == "release" and not $config.is_windows {
        run-external meson "install" "-C" "builddir" "--strip"
    }
}

# Build with Autotools
def build-autotools [] {
    log info "Building with Autotools..."

    # Run autoreconf if configure doesn't exist
    if not ("configure" | path exists) and ("configure.ac" | path exists) {
        log info "Running autoreconf..."
        run-external autoreconf "-fiv"
    }

    # Configure arguments
    mut configure_args = [
        $"--prefix=($config.install_prefix)"
    ]

    # Add common options
    if not $config.build_tests {
        $configure_args = ($configure_args | append "--disable-tests")
    }

    if $config.enable_static {
        $configure_args = ($configure_args | append "--enable-static")
        $configure_args = ($configure_args | append "--disable-shared")
    } else {
        $configure_args = ($configure_args | append "--disable-static")
        $configure_args = ($configure_args | append "--enable-shared")
    }

    # Platform-specific options
    if $config.is_windows {
        $configure_args = ($configure_args | append "--host=x86_64-w64-mingw32")
    }

    # Configure
    log info $"Configuring with: ./configure ($configure_args | str join ' ')"
    run-external sh "-c" $"./configure ($configure_args | str join ' ')"

    # Build
    log info $"Building with ($config.job_count) parallel jobs..."
    run-external make "-j" ($config.job_count | into string)

    # Test if enabled
    if $config.build_tests and (open Makefile | str contains "check:") {
        log info "Running tests..."
        run-external make "check"
    }

    # Install
    log info "Installing..."
    run-external make "install"

    # Strip if in release mode
    if $config.build_type == "Release" and not $config.is_windows {
        run-external make "install-strip"
    }
}

# Build with Make
def build-make [] {
    log info "Building with Make..."

    # Check if we need to run configure first
    if ("configure" | path exists) {
        build-autotools
        return
    }

    # Prepare make arguments
    mut make_args = [
        $"PREFIX=($config.install_prefix)"
        "DESTDIR="
        $"-j($config.job_count)"
    ]

    # Add compiler flags for release builds
    if $config.build_type == "Release" {
        $make_args = ($make_args | append "CFLAGS=-O3 -DNDEBUG")
        $make_args = ($make_args | append "CXXFLAGS=-O3 -DNDEBUG")
    }

    # Build
    log info $"Building with: make ($make_args | str join ' ')"
    run-external make ...$make_args

    # Install
    log info "Installing..."
    run-external make "install" $"PREFIX=($config.install_prefix)" "DESTDIR="
}

# Validate installation
def validate-installation [] {
    log info "Validating installation..."

    # Check for executables
    if ($config.bin_dir | path exists) {
        let executables = if $config.is_windows {
            ls $config.bin_dir | where type == "file" | where name =~ '\.exe$'
        } else {
            ls $config.bin_dir | where type == "file"
        }

        if ($executables | length) == 0 {
            log warning "No executables found in bin directory"
        } else {
            log success $"Found ($executables | length) executables:"
            for exe in $executables {
                log info $"  - ($exe.name | path basename)"

                # Check if executable is properly linked (Unix only)
                if not $config.is_windows {
                    let exe_path = $exe.name
                    if (which ldd | length) > 0 {
                        let ldd_output = (run-external ldd $exe_path | complete)
                        if ($ldd_output.stdout | str contains "not found") {
                            log warning $"Missing libraries for ($exe.name | path basename)"
                        }
                    } else if (which otool | length) > 0 and $config.is_macos {
                        let otool_output = (run-external otool "-L" $exe_path | complete)
                        if ($otool_output.exit_code != 0) {
                            log warning $"Failed to check libraries for ($exe.name | path basename)"
                        }
                    }
                }
            }
        }
    }

    # Check for libraries
    if ($config.lib_dir | path exists) {
        let libraries = if $config.is_windows {
            ls $config.lib_dir | where type == "file" | where name =~ '\.(dll|lib)$'
        } else if $config.is_macos {
            ls $config.lib_dir | where type == "file" | where name =~ '\.(dylib|a)$'
        } else {
            ls $config.lib_dir | where type == "file" | where name =~ '\.(so|a)$'
        }

        if ($libraries | length) > 0 {
            log success $"Found ($libraries | length) libraries"
        }
    }

    # Check for pkg-config files
    let pc_dir = ($config.install_prefix | path join "share" "pkgconfig")
    let pc_dir_alt = ($config.lib_dir | path join "pkgconfig")

    for dir in [$pc_dir, $pc_dir_alt] {
        if ($dir | path exists) {
            let pc_files = (ls $dir | where type == "file" | where name =~ '\.pc$')
            if ($pc_files | length) > 0 {
                log success $"Found ($pc_files | length) pkg-config files"
            }
        }
    }

    # Check total installation size
    let all_files = (ls $config.install_prefix --all | where type == "file")
    if ($all_files | length) > 0 {
        let total_size = ($all_files | get size | math sum)
        let size_mb = (($total_size / 1048576) | math round --precision 2)
        log info $"Total installation size: ($size_mb) MB"
    }
}

# Post-installation fixes
def post-install-fixes [] {
    log info "Applying post-installation fixes..."

    # Fix RPATH on Linux
    if $config.is_linux and (which patchelf | length) > 0 {
        log info "Fixing RPATH for Linux binaries..."
        let binaries = (ls $config.bin_dir | where type == "file")

        for bin in $binaries {
            run-external patchelf "--set-rpath" "$ORIGIN/../lib" $bin.name
        }
    }

    # Fix install names on macOS
    if $config.is_macos and (which install_name_tool | length) > 0 {
        log info "Fixing install names for macOS..."
        # This is a simplified example - real implementation would be more complex
    }

    # Generate wrapper scripts if needed
    if ($env.GENERATE_WRAPPERS? | default false | into bool) {
        log info "Generating wrapper scripts..."
        # Implementation depends on specific application needs
    }
}

# Main build process
def main [] {
    log info $"Building ($env.PKG_NAME) version ($env.PKG_VERSION)"
    log info $"Platform: ($nu.os-info.name) ($nu.os-info.arch)"
    log info $"Install prefix: ($config.install_prefix)"
    log info $"Build configuration:"
    log info $"  - Build type: ($config.build_type)"
    log info $"  - Parallel jobs: ($config.job_count)"
    log info $"  - Build tests: ($config.build_tests)"
    log info $"  - Build examples: ($config.build_examples)"
    log info $"  - Static build: ($config.enable_static)"

    # Save current directory
    let original_dir = (pwd)

    try {
        # Detect and execute build method
        let build_system = (detect-build-system)

        if $build_system == null {
            error make {msg: "No recognized build system found"}
        }

        log info $"Detected build system: ($build_system)"

        match $build_system {
            "cmake" => { build-cmake }
            "meson" => { build-meson }
            "autotools" => { build-autotools }
            "configure" => { build-autotools }
            "make" => { build-make }
            _ => {
                error make {msg: $"Build system '($build_system)' not yet supported"}
            }
        }

        # Apply post-installation fixes
        post-install-fixes

        # Validate installation
        validate-installation

        log success "Build completed successfully!"

    } catch { |e|
        log error $"Build failed: ($e.msg)"
        cd $original_dir
        exit 1
    }

    # Return to original directory
    cd $original_dir
}

# Run main
main
