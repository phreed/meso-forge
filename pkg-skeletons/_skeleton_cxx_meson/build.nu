#!/usr/bin/env nu

# Example build script for C++ Meson packages
# This script demonstrates best practices for building meson-based C++ packages
# with cross-platform compatibility and robust dependency handling.

def main [
    package: string = "example-cpp-meson",  # Package name
    --target-platform: string = "linux-64", # Target platform
    --force,                                # Force rebuild
    --verbose                              # Enable verbose output
] {
    print $"🔨 Building ($package) for ($target_platform)..."

    # Build configuration
    let recipe_dir = $"./pkgs/($package)"
    let output_dir = "./pkgs-out"

    # Check if recipe exists
    if not ($recipe_dir | path exists) {
        print -e $"❌ Recipe directory not found: ($recipe_dir)"
        print -e "   Available packages:"
        ls ./pkgs | where type == dir | get name | each { |name| print $"     ($name)" }
        exit 1
    }

    # Prepare build arguments
    let skip_existing = if $force { "none" } else { "all" }
    let verbosity = if $verbose { ["-vvv"] } else { ["-v"] }

    let build_args = ([
        "build"
        "--recipe-dir" $recipe_dir
        "--output-dir" $output_dir
        "--skip-existing" $skip_existing
        "--target-platform" $target_platform
        "--channel" "conda-forge"
        "--no-test"  # We'll run tests separately
    ] | append $verbosity)

    print $"🚀 Running: rattler-build (($build_args | str join ' '))"
    print ""

    # Execute build
    let start_time = date now
    let result = (^rattler-build ...$build_args | complete)
    let duration = ((date now) - $start_time)

    if $result.exit_code == 0 {
        print ""
        print $"✅ Build successful! (duration: ($duration))"

        # Find the built package
        let package_pattern = $"($package)-*-*.conda"
        let built_packages = (ls $"($output_dir)/($target_platform)/($package_pattern)" | get name)

        if ($built_packages | length) > 0 {
            let package_file = ($built_packages | first)
            let package_name = ($package_file | path basename)
            print $"📦 Package: ($package_name)"

            # Show package info
            let file_size = (ls $package_file | get size | first)
            let size_mb = ($file_size / 1024 / 1024 | math round -p 2)
            print $"   Size: ($size_mb) MB"
            print $"   Path: ($package_file)"
            print $"  • Install locally: conda install ($package_file)"
            print $"  • Upload: rattler-build upload ($package_file)"
        }

        print ""
        print "Next steps:"
        print $"  • Test: nu build.nu test ($package) ($target_platform)"

    } else {
        print -e ""
        print -e $"❌ Build failed! (duration: ($duration))"

        if not ($result.stderr | is-empty) {
            print -e ""
            print -e "Error output:"
            print -e $result.stderr
        }

        if not ($result.stdout | is-empty) {
            print -e ""
            print -e "Build output:"
            print -e $result.stdout
        }

        print -e ""
        print -e "Common meson build issues:"
        print -e "  • Missing dependencies in host requirements"
        print -e "  • PKG_CONFIG_PATH not set correctly"
        print -e "  • Meson options incompatible with environment"
        print -e "  • Cross-platform path issues"

        exit 1
    }
}

# Test a built package
def "main test" [
    package: string,                         # Package name
    target_platform: string = "linux-64",   # Target platform
    --verbose                               # Enable verbose output
] {
    print $"🧪 Testing ($package) for ($target_platform)..."

    let output_dir = "./pkgs-out"
    let package_pattern = $"($package)-*-*.conda"
    let package_files = (ls $"($output_dir)/($target_platform)/($package_pattern)" 2>/dev/null | get name)

    if ($package_files | length) == 0 {
        print -e $"❌ No built package found for ($package)"
        print -e $"   Expected pattern: ($output_dir)/($target_platform)/($package_pattern)"
        print -e $"   Run build first: nu build.nu ($package) --target-platform ($target_platform)"
        exit 1
    }

    let package_file = ($package_files | first)
    print $"📦 Testing package: ($package_file | path basename)"

    # Build test arguments
    let verbosity = if $verbose { ["-vvv"] } else { ["-v"] }
    let test_args = (["test" "--package-file" $package_file "--channel" "conda-forge"] | append $verbosity)

    print $"🚀 Running: rattler-build (($test_args | str join ' '))"
    print ""

    # Execute test
    let start_time = date now
    let result = (^rattler-build ...$test_args | complete)
    let duration = ((date now) - $start_time)

    if $result.exit_code == 0 {
        print ""
        print $"✅ Tests passed! (duration: ($duration))"

        # Show test summary if available
        let output_lines = $result.stdout | lines
        let test_lines = $output_lines | where { |line|
            ($line | str contains "✔") or ($line | str contains "PASSED") or ($line | str contains "SUCCESS")
        }

        if ($test_lines | length) > 0 {
            print ""
            print "Test summary:"
            $test_lines | each { |line| print $"  ($line)" }
        }

    } else {
        print -e ""
        print -e $"❌ Tests failed! (duration: ($duration))"

        if not ($result.stderr | is-empty) {
            print -e ""
            print -e "Error output:"
            print -e $result.stderr
        }

        # Extract specific failure information
        let all_output = $result.stdout + "\n" + $result.stderr
        let failure_lines = $all_output | lines | where { |line|
            ($line | str contains "❌") or ($line | str contains "FAILED") or ($line | str contains "ERROR")
        }

        if ($failure_lines | length) > 0 {
            print -e ""
            print -e "Failure details:"
            $failure_lines | first 10 | each { |line| print -e $"  ($line)" }
        }

        print -e ""
        print -e "Common meson test issues:"
        print -e "  • Files installed to lib/ instead of lib64/ - check --libdir setting"
        print -e "  • Missing files in package_contents test - verify installation"
        print -e "  • Dependency conflicts - simplify test requirements"
        print -e "  • Cross-platform path issues - use flexible lib*/ patterns"

        exit 1
    }
}

# Clean build artifacts
def "main clean" [
    package: string,                         # Package name
    target_platform: string = "linux-64"    # Target platform
] {
    print $"🧹 Cleaning build artifacts for ($package)..."

    let output_dir = "./pkgs-out"
    let package_pattern = $"($package)-*-*.conda"
    let package_files = (ls $"($output_dir)/($target_platform)/($package_pattern)" 2>/dev/null | get name)

    for file in $package_files {
        print $"  Removing: ($file | path basename)"
        rm $file
    }

    # Clean build cache if it exists
    let cache_pattern = $"bld/rattler-build_($package)_*"
    let cache_dirs = (ls $"($output_dir)/($cache_pattern)" 2>/dev/null | get name)

    for dir in $cache_dirs {
        print $"  Removing cache: ($dir | path basename)"
        rm -rf $dir
    }

    print $"✅ Cleaned ($package_files | length) packages and ($cache_dirs | length) cache directories"
}

# Show package information
def "main info" [
    package: string,                         # Package name
    target_platform: string = "linux-64"    # Target platform
] {
    print $"📋 Package information for ($package)..."

    let recipe_dir = $"./pkgs/($package)"
    let output_dir = "./pkgs-out"

    # Check recipe
    if ($recipe_dir | path exists) {
        print $"📁 Recipe: ($recipe_dir)"
        let recipe_file = $"($recipe_dir)/recipe.yaml"
        if ($recipe_file | path exists) {
            let recipe_content = (open $recipe_file --raw | from yaml)
            if ("package" in $recipe_content) and ("version" in $recipe_content.package) {
                print $"   Version: ($recipe_content.package.version)"
            }
        }
    } else {
        print -e $"❌ Recipe not found: ($recipe_dir)"
    }

    # Check built packages
    let package_pattern = $"($package)-*-*.conda"
    let package_files = (ls $"($output_dir)/($target_platform)/($package_pattern)" 2>/dev/null | get name)

    if ($package_files | length) > 0 {
        print $"📦 Built packages: ($package_files | length)"
        for file in $package_files {
            let stats = (ls $file | first)
            let size_mb = ($stats.size / 1024 / 1024 | math round -p 2)
            print $"   ($stats.name | path basename) - ($size_mb) MB - ($stats.modified)"
        }
    } else {
        print $"📦 No built packages found"
    }
}

# Build all packages (useful for CI)
def "main build-each" [
    target_platform: string = "linux-64",   # Target platform
    --continue-on-error                     # Continue building even if some packages fail
] {
    print $"🔨 Building all meson packages for ($target_platform)..."

    let meson_packages = (ls ./pkgs | where type == dir | get name |
        where { |pkg|
            let recipe_file = $"./pkgs/($pkg)/recipe.yaml"
            if ($recipe_file | path exists) {
                let content = (open $recipe_file --raw)
                ($content | str contains "meson") and ($content | str contains "ninja")
            } else {
                false
            }
        })

    if ($meson_packages | length) == 0 {
        print "No meson packages found"
        return
    }

    print $"Found ($meson_packages | length) meson packages:"
    $meson_packages | each { |pkg| print $"  • ($pkg)" }
    print ""

    mut built = 0
    mut failed = 0
    mut results = []

    for pkg in $meson_packages {
        print $"Building ($pkg)..."

        let result = (try {
            main $pkg --target-platform $target_platform
            {exit_code: 0, package: $pkg}
        } catch {
            {exit_code: 1, package: $pkg}
        })

        if $result.exit_code == 0 {
            $built = $built + 1
            $results = ($results | append {package: $pkg, status: "✅ SUCCESS"})
        } else {
            $failed = $failed + 1
            $results = ($results | append {package: $pkg, status: "❌ FAILED"})

            if not $continue_on_error {
                print -e ""
                print -e "Build failed. Use --continue-on-error to build remaining packages."
                break
            }
        }

        print ""
    }

    # Summary
    print "Build Summary:"
    $results | table
    print ""
    print $"Total: ($meson_packages | length) | Built: ($built) | Failed: ($failed)"

    if $failed > 0 {
        exit 1
    }
}
