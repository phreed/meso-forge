#!/usr/bin/env nu

# Test a built package using the conda manifest
# Usage: nu test_package.nu <package> [--target-platform <platform>]

use manifest_utils.nu *
use std repeat

def main [
    package: string,                         # Package name to test
    --target-platform: string = "linux-64",  # Target platform
    --manifest: string = "./pkgs-out/conda-manifest.json",  # Path to manifest file
    --verbose                               # Enable verbose output
] {
    print $"🧪 Testing package: ($package) for platform: ($target_platform)"
    print ""

    # Check if manifest exists
    if not ($manifest | path exists) {
        print -e $"❌ Manifest file not found: ($manifest)"
        print -e "   No packages have been built yet. Run `pixi run build` first."
        exit 1
    }

    # Get package info from manifest
    let package_info = get-package-info $package --platform $target_platform --manifest $manifest

    if $package_info == null {
        print -e $"❌ Package '($package)' not found in manifest for platform '($target_platform)'"
        print -e ""
        print -e "Available packages:"

        let available = list-packages --manifest $manifest

        if ($available | length) > 0 {
            $available | select platform package | to md
        } else {
            print -e "  No packages found in manifest"
        }

        print -e ""
        print -e $"Hint: Run `pixi run build ($package) ($target_platform)` first"
        exit 1
    }

    # Check if package file exists
    let conda_file = $package_info.path
    if not ($conda_file | path exists) {
        print -e $"❌ Package file not found: ($conda_file)"
        print -e "   The file may have been deleted. Try rebuilding the package."
        exit 1
    }

    print $"📦 Found package: ($conda_file | path basename)"
    print $"   Size: (($package_info.size / 1024 / 1024) | math round -p 2) MB"
    print $"   Built: ($package_info.build_time)"
    print $"   Status: ($package_info.status)"
    print ""

    # Build the test command arguments
    let verbosity = if $verbose { ["-vvv"] } else { ["-v"] }
    let cmd_args = (["test", "--package-file", $conda_file, "--channel", "conda-forge"] | append $verbosity)

    print $"🚀 Running: rattler-build (($cmd_args | str join ' '))"
    print ("─" | repeat 80 | str join "")

    # Execute the test
    let start_time = date now
    let result = (^rattler-build ...$cmd_args | complete)
    let duration = ((date now) - $start_time)

    print ("─" | repeat 80 | str join "")
    print ""

    if $result.exit_code == 0 {
        print $"✅ Tests passed for ($package)!"
        print $"⏱️  Duration: ($duration)"

        # Show test summary if available in output
        let output_lines = $result.stdout | lines
        let test_lines = $output_lines | where { |line|
            ($line | str contains "test") or ($line | str contains "PASSED") or ($line | str contains "SUCCESS")
        }

        if ($test_lines | length) > 0 {
            print ""
            print "Test summary:"
            $test_lines | each { |line| print $"  ($line)" }
        }
    } else {
        print -e $"❌ Tests failed for ($package)!"
        print -e $"⏱️  Duration: ($duration)"

        if not ($result.stderr | is-empty) {
            print -e ""
            print -e "Error output:"
            print -e $result.stderr
        }

        # Try to extract specific failure information
        let all_output = $result.stdout + "\n" + $result.stderr
        let failure_lines = $all_output | lines | where { |line|
            ($line | str contains "FAILED") or ($line | str contains "ERROR") or ($line | str contains "error:") or ($line | str contains "Failed")
        }

        if ($failure_lines | length) > 0 {
            print -e ""
            print -e "Failure details:"
            $failure_lines | first 10 | each { |line| print -e $"  ($line)" }

            if ($failure_lines | length) > 10 {
                print -e $"  ... and (($failure_lines | length) - 10) more error lines"
            }
        }

        exit 1
    }
}

# Helper function to test all packages for a platform
export def test-each [
    --platform: string = "linux-64",         # Target platform
    --manifest: string = "./pkgs-out/conda-manifest.json",  # Path to manifest file
    --continue-on-error                      # Continue testing even if some fail
] {
    let packages = list-packages --platform $platform --manifest $manifest

    if ($packages | length) == 0 {
        print $"No packages found for platform ($platform)"
        return
    }

    print $"🧪 Testing ($packages | length) packages for platform ($platform)"
    print ("=" | repeat 80 | str join "")
    print ""

    mut passed = 0
    mut failed = 0
    mut results = []

    for pkg in $packages {
        print $"Testing ($pkg.package)..."

        let result = (try {
            main $pkg.package --target-platform $platform --manifest $manifest
            {exit_code: 0}
        } catch {
            {exit_code: 1}
        })

        if $result.exit_code == 0 {
            $passed = $passed + 1
            $results = ($results | append {
                package: $pkg.package,
                status: "✅ PASSED"
            })
        } else {
            $failed = $failed + 1
            $results = ($results | append {
                package: $pkg.package,
                status: "❌ FAILED"
            })

            if not $continue_on_error {
                print -e ""
                print -e "Stopping due to test failure. Use --continue-on-error to test remaining packages."
                break
            }
        }

        print ""
        print ("─" | repeat 80 | str join "")
        print ""
    }

    # Print summary
    print "Test Summary:"
    print "============="
    $results | to md
    print ""
    print $"Total: ($packages | length) | Passed: ($passed) | Failed: ($failed)"

    if $failed > 0 {
        exit 1
    }
}

# Helper function to show test status for all packages
export def test-status [
    --manifest: string = "./pkgs-out/conda-manifest.json"  # Path to manifest file
] {
    print "Package Test Status"
    print "==================="
    print ""

    let packages = list-packages --manifest $manifest

    if ($packages | length) == 0 {
        print "No packages found in manifest"
        return
    }

    # Group by platform
    let by_platform = $packages | group-by platform

    for platform in ($by_platform | columns | sort) {
        let plat_packages = $by_platform | get $platform
        print $"Platform: ($platform)"
        print $"  Packages: ($plat_packages | length)"

        # Note: We can't know test status without running tests
        # This just shows which packages are available for testing
        $plat_packages | select package size build_time | to md
        print ""
    }
}
