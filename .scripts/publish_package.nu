#!/usr/bin/env nu

# Publish built packages using the conda manifest
# Usage: nu publish_package.nu <package> [--method <pd|s3>] [--target-platform <platform>]

use manifest_utils.nu *

def main [
    package: string,                         # Package name to publish
    --method: string = "pd",                 # Publishing method: "pd" for prefix.dev, "s3" for S3
    --target-platform: string = "linux-64",  # Target platform
    --manifest: string = "./pkgs-out/conda-manifest.json",  # Path to manifest file
    --dry-run,                              # Show command without executing
    --verbose                               # Enable verbose output
] {
    print $"📦 Publishing package: ($package) via ($method) for platform: ($target_platform)"
    print ""

    # Validate method
    if $method not-in ["pd", "s3"] {
        print -e "❌ Invalid method: ($method). Use 'pd' or 's3'"
        exit 1
    }

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

    print $"📄 Found package: ($conda_file | path basename)"
    print $"   Size: (($package_info.size / 1024 / 1024) | math round -p 2) MB"
    print $"   Built: ($package_info.build_time)"
    print $"   Status: ($package_info.status)"
    print ""

    # Check authentication
    if ($method == "pd" or $method == "s3") and ($env.RATTLER_AUTH_FILE? | is-empty) {
        print -e "⚠️  Warning: RATTLER_AUTH_FILE environment variable not set"
        print -e "   Publishing may fail without proper authentication"
        print ""
    }

    # Build the publish command
    let cmd = if $method == "pd" {
        let verbosity = if $verbose { "-vvv" } else { "-v" }
        $"rattler-build upload prefix --skip-existing ($verbosity) --channel meso-forge ($conda_file)"
    } else if $method == "s3" {
        let verbosity = if $verbose { "-vvv" } else { "-v" }
        let url = "https://minio.isis.vanderbilt.edu"
        let channel = "s3://pixi/meso-forge"
        $"rattler-build upload s3 --channel '($channel)' --region auto --endpoint-url '($url)' --force-path-style ($verbosity) ($conda_file)"
    } else {
        print -e $"❌ Unsupported method: ($method)"
        exit 1
    }

    if $dry_run {
        print $"🔍 Dry run - would execute:"
        print $"   ($cmd)"
        exit 0
    }

    print $"🚀 Publishing via ($method)..."
    print $"   Command: ($cmd)"
    print "─" * 80

    # Execute the publish
    let start_time = date now
    let result = (do { bash -c $cmd } | complete)
    let duration = ((date now) - $start_time)

    print "─" * 80
    print ""

    if $result.exit_code == 0 {
        print $"✅ Successfully published ($package) via ($method)!"
        print $"⏱️  Duration: ($duration)"

        # Show relevant output
        if not ($result.stdout | is-empty) {
            let output_lines = $result.stdout | lines
            let success_lines = $output_lines | where { |line|
                ($line | str contains "uploaded") or ($line | str contains "SUCCESS") or ($line | str contains "published")
            }

            if ($success_lines | length) > 0 {
                print ""
                print "Upload details:"
                $success_lines | each { |line| print $"  ($line)" }
            }
        }
    } else {
        print -e $"❌ Failed to publish ($package) via ($method)!"
        print -e $"⏱️  Duration: ($duration)"

        if not ($result.stderr | is-empty) {
            print -e ""
            print -e "Error output:"
            print -e $result.stderr
        }

        # Try to extract specific error information
        let all_output = $result.stdout + "\n" + $result.stderr
        let error_lines = $all_output | lines | where { |line|
            ($line | str contains "error") or ($line | str contains "Error") or ($line | str contains "failed") or ($line | str contains "Failed")
        }

        if ($error_lines | length) > 0 {
            print -e ""
            print -e "Error details:"
            $error_lines | first 5 | each { |line| print -e $"  ($line)" }

            if ($error_lines | length) > 5 {
                print -e $"  ... and (($error_lines | length) - 5) more error lines"
            }
        }

        exit 1
    }
}

# Helper function to publish all packages using a specific method
export def publish-all [
    --method: string = "pd",                 # Publishing method: "pd" for prefix.dev, "s3" for S3
    --platform: string = "linux-64",         # Target platform
    --manifest: string = "./pkgs-out/conda-manifest.json",  # Path to manifest file
    --continue-on-error,                     # Continue publishing even if some fail
    --dry-run                               # Show what would be published without executing
] {
    let packages = list-packages --platform $platform --manifest $manifest

    if ($packages | length) == 0 {
        print $"No packages found for platform ($platform)"
        return
    }

    print $"📦 Publishing ($packages | length) packages via ($method) for platform ($platform)"
    if $dry_run {
        print "🔍 DRY RUN - no actual publishing will occur"
    }
    print "=" * 80
    print ""

    mut published = 0
    mut failed = 0
    mut results = []

    for pkg in $packages {
        print $"Publishing ($pkg.package)..."

        let result = (do {
            main $pkg.package --method $method --target-platform $platform --manifest $manifest --dry-run=$dry_run
        } | complete)

        if $result.exit_code == 0 {
            $published = $published + 1
            $results = ($results | append {
                package: $pkg.package,
                status: "✅ PUBLISHED"
            })
        } else {
            $failed = $failed + 1
            $results = ($results | append {
                package: $pkg.package,
                status: "❌ FAILED"
            })

            if not $continue_on_error {
                print -e ""
                print -e "Stopping due to publish failure. Use --continue-on-error to publish remaining packages."
                break
            }
        }

        print ""
        print "─" * 80
        print ""
    }

    # Print summary
    let action = if $dry_run { "Would publish" } else { "Publish" }
    print $"($action) Summary:"
    print "=" * 15
    $results | to md
    print ""
    print $"Total: ($packages | length) | Published: ($published) | Failed: ($failed)"

    if $failed > 0 and not $dry_run {
        exit 1
    }
}

# Helper function to show publish status
export def publish-status [
    --manifest: string = "./pkgs-out/conda-manifest.json"  # Path to manifest file
] {
    print "Package Publish Status"
    print "======================"
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

        # Show packages available for publishing
        $plat_packages | select package size build_time status | to md
        print ""
    }

    print "Authentication status:"
    if ($env.RATTLER_AUTH_FILE? | is-empty) {
        print "  ❌ RATTLER_AUTH_FILE not set - publishing will likely fail"
        print "     Set this environment variable to your rattler auth file path"
    } else {
        let auth_file = $env.RATTLER_AUTH_FILE
        if ($auth_file | path exists) {
            print $"  ✅ RATTLER_AUTH_FILE set and file exists: ($auth_file)"
        } else {
            print $"  ⚠️  RATTLER_AUTH_FILE set but file not found: ($auth_file)"
        }
    }
}

# Helper function to show available publish methods
export def publish-help [] {
    print "=== Package Publishing Help ==="
    print ""
    print "Available commands:"
    print "  main <pkg> --method <pd|s3>   - Publish a specific package"
    print "  publish-all --method <pd|s3>  - Publish all built packages"
    print "  publish-status                - Show packages available for publishing"
    print ""
    print "Publishing methods:"
    print "  pd  - Publish to prefix.dev (requires RATTLER_AUTH_FILE)"
    print "  s3  - Publish to S3/MinIO (requires RATTLER_AUTH_FILE)"
    print ""
    print "Environment variables:"
    print "  RATTLER_AUTH_FILE - Path to rattler authentication file"
    print ""
    print "Example usage:"
    print "  use .scripts/publish_package.nu *"
    print "  main pwgen --method pd"
    print "  main fd --method s3 --dry-run"
    print "  publish-all --method pd --continue-on-error"
    print "  publish-status"
}
