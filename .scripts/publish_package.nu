#!/usr/bin/env nu

# Publish built packages using the conda manifest
# Usage: nu publish_package.nu <package> [--method <pd|s3>] [--target-platform <platform>]

use manifest_utils.nu *
use std repeat

def main [
    package: string,                         # Package name to publish
    --method: string = "pd",                 # Publishing method: "pd" for prefix.dev, "s3" for S3
    --channel: string = "",                  # Channel name (overrides default channels)
    --url: string = "",                      # Endpoint URL for S3 (overrides default URL)
    --target-platform: string = "linux-64",  # Target platform
    --manifest: string = "./pkgs-out/conda-manifest.json",  # Path to manifest file
    --dry-run,                              # Show command without executing
    --verbose,                              # Enable verbose output
    --force                                 # Force upload, overwriting existing packages
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
        let channel_name = if ($channel | is-empty) { "meso-forge" } else { $channel }
        let skip_existing = if $force { "" } else { "--skip-existing" }
        $"rattler-build upload prefix ($skip_existing) ($verbosity) --channel ($channel_name) ($conda_file)"
    } else if $method == "s3" {
        let verbosity = if $verbose { "-vvv" } else { "-v" }
        let endpoint_url = if ($url | is-empty) { "https://minio.isis.vanderbilt.edu" } else { $url }
        let channel_name = if ($channel | is-empty) { "s3://pixi/meso-forge" } else { $channel }
        $"rattler-build upload s3 --channel '($channel_name)' --region auto --endpoint-url '($endpoint_url)' --force-path-style ($verbosity) ($conda_file)"
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

    # Execute the publish
    let start_time = date now
    let result = (do { bash -c $cmd } | complete)
    let duration = ((date now) - $start_time)

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
        # Check if this is an S3 "file already exists" error
        let all_output = $result.stdout + "\n" + $result.stderr
        let is_s3_already_exists = (
            $method == "s3" and (
                ($all_output | str contains "PreconditionFailed") or
                ($all_output | str contains "status: 412")
            )
        )

        if $is_s3_already_exists {
            print $"⚠️  Package ($package) already exists on S3!"
            print $"⏱️  Duration: ($duration)"
            print ""
            print "This is expected if the package was previously uploaded."
            print "The existing package on S3 will be used."
        } else {
            print -e $"❌ Failed to publish ($package) via ($method)!"
            print -e $"⏱️  Duration: ($duration)"

            if not ($result.stderr | is-empty) {
                print -e ""
                print -e "Error output:"
                print -e $result.stderr
            }

            # Try to extract specific error information
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
}

# Helper function to publish all packages using a specific method
export def publish-all [
    --method: string = "pd",                 # Publishing method: "pd" for prefix.dev, "s3" for S3
    --channel: string,                       # Channel name (e.g., "meso-forge" for pd, "s3://pixi/meso-forge" for s3)
    --url: string = "",                      # Endpoint URL for S3 (required when method is "s3")
    --platform: string = "linux-64",         # Target platform
    --manifest: string = "./pkgs-out/conda-manifest.json",  # Path to manifest file
    --continue-on-error,                     # Continue publishing even if some fail
    --dry-run,                              # Show what would be published without executing
    --force                                 # Force upload, overwriting existing packages
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
    print ("=" | repeat 80 | str join)
    print ""

    mut published = 0
    mut failed = 0
    mut results = []

    for pkg in $packages {
        print $"Publishing ($pkg.package)..."

        # Call the publish script directly
        let publish_cmd = if $dry_run {
            if ($channel | is-empty) {
                ["nu", ".scripts/publish_package.nu", $pkg.package, "--method", $method, "--target-platform", $platform, "--manifest", $manifest, "--dry-run"]
            } else if ($method == "s3" and not ($url | is-empty)) {
                ["nu", ".scripts/publish_package.nu", $pkg.package, "--method", $method, "--channel", $channel, "--url", $url, "--target-platform", $platform, "--manifest", $manifest, "--dry-run"]
            } else {
                ["nu", ".scripts/publish_package.nu", $pkg.package, "--method", $method, "--channel", $channel, "--target-platform", $platform, "--manifest", $manifest, "--dry-run"]
            }
        } else {
            if ($channel | is-empty) {
                ["nu", ".scripts/publish_package.nu", $pkg.package, "--method", $method, "--target-platform", $platform, "--manifest", $manifest]
            } else if ($method == "s3" and not ($url | is-empty)) {
                ["nu", ".scripts/publish_package.nu", $pkg.package, "--method", $method, "--channel", $channel, "--url", $url, "--target-platform", $platform, "--manifest", $manifest]
            } else {
                ["nu", ".scripts/publish_package.nu", $pkg.package, "--method", $method, "--channel", $channel, "--target-platform", $platform, "--manifest", $manifest]
            }
        }

        let result = (run-external ...$publish_cmd | complete)

        if $result.exit_code == 0 {
            # Check if this was a warning about already existing
            let output = $result.stdout
            if ($method == "s3" and ($output | str contains "already exists on S3")) {
                $published = $published + 1
                $results = ($results | append {
                    package: $pkg.package,
                    status: "⚠️  ALREADY EXISTS"
                })
            } else {
                $published = $published + 1
                $results = ($results | append {
                    package: $pkg.package,
                    status: "✅ PUBLISHED"
                })
            }
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
        print ("─" | repeat 80 | str join)
        print ""
    }

    # Print summary
    let action = if $dry_run { "Would publish" } else { "Publish" }
    print $"($action) Summary:"
    print ("=" | repeat 15 | str join)
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

# Helper function to publish all conda files in a directory
export def publish-directory [
    directory: string = "./pkgs-out",        # Directory to scan for conda files
    --method: string = "pd",                 # Publishing method: "pd" for prefix.dev, "s3" for S3
    --channel: string = "",                  # Channel name (overrides default channels)
    --url: string = "",                      # Endpoint URL for S3 (overrides default URL)
    --recursive,                             # Scan directory recursively
    --dry-run,                               # Show what would be published without executing
    --continue-on-error,                     # Continue publishing even if some fail
    --verbose,                               # Enable verbose output
    --force                                  # Force upload, overwriting existing packages
] {
    print $"📦 Publishing all conda files from ($directory) via ($method)"
    if $dry_run {
        print "🔍 DRY RUN - no actual publishing will occur"
    }
    print ("=" | repeat 80 | str join)
    print ""

    # Validate method
    if $method not-in ["pd", "s3"] {
        print -e "❌ Invalid method: ($method). Use 'pd' or 's3'"
        exit 1
    }

    # Check if directory exists
    if not ($directory | path exists) {
        print -e $"❌ Directory not found: ($directory)"
        exit 1
    }

    # Find all conda files
    let pattern = if $recursive { $"($directory)/**/*.conda" } else { $"($directory)/*.conda" }
    let conda_files = glob $pattern

    if ($conda_files | length) == 0 {
        print $"No conda files found in ($directory)"
        return
    }

    print $"Found ($conda_files | length) conda files to publish"
    print ""

    mut published = 0
    mut failed = 0
    mut results = []

    for conda_file in $conda_files {
        let filename = $conda_file | path basename
        print $"Publishing ($filename)..."

        let cmd = if $method == "pd" {
            let verbosity = if $verbose { "-vvv" } else { "-v" }
            let channel_name = if ($channel | is-empty) { "meso-forge" } else { $channel }
            let skip_existing = if $force { "" } else { "--skip-existing" }
            $"rattler-build upload prefix ($skip_existing) ($verbosity) --channel ($channel_name) ($conda_file)"
        } else if $method == "s3" {
            let verbosity = if $verbose { "-vvv" } else { "-v" }
            let endpoint_url = if ($url | is-empty) { "https://minio.isis.vanderbilt.edu" } else { $url }
            let channel_name = if ($channel | is-empty) { "s3://pixi/meso-forge" } else { $channel }
            $"rattler-build upload s3 --channel '($channel_name)' --region auto --endpoint-url '($endpoint_url)' --force-path-style ($verbosity) ($conda_file)"
        }

        if $dry_run {
            print $"   Would execute: ($cmd)"
            $published = $published + 1
            $results = ($results | append {
                file: $filename,
                status: "✅ WOULD PUBLISH"
            })
        } else {
            print $"   Command: ($cmd)"
            let result = (do { bash -c $cmd } | complete)

            if $result.exit_code == 0 {
                $published = $published + 1
                $results = ($results | append {
                    file: $filename,
                    status: "✅ PUBLISHED"
                })
                print $"   ✅ Successfully published ($filename)"
            } else {
                $failed = $failed + 1
                $results = ($results | append {
                    file: $filename,
                    status: "❌ FAILED"
                })
                print -e $"   ❌ Failed to publish ($filename)"

                if not $continue_on_error {
                    print -e ""
                    print -e "Stopping due to publish failure. Use --continue-on-error to publish remaining files."
                    break
                }
            }
        }

        print ""
    }

    # Print summary
    print ("─" | repeat 80 | str join)
    let action = if $dry_run { "Would publish" } else { "Publish" }
    print $"($action) Summary:"
    print ("=" | repeat 15 | str join)
    $results | to md
    print ""
    print $"Total: ($conda_files | length) | Published: ($published) | Failed: ($failed)"

    if $failed > 0 and not $dry_run {
        exit 1
    }
}

# Helper function to show available publish methods
export def publish-help [] {
    print "=== Package Publishing Help ==="
    print ""
    print "Available commands:"
    print "  main <pkg> --method <pd|s3>        - Publish a specific package"
    print "  publish-all --method <pd|s3>       - Publish all built packages (from manifest)"
    print "  publish-directory <dir> --method   - Publish all conda files in a directory"
    print "  publish-status                     - Show packages available for publishing"
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
    print "  publish-all --method pd --channel meso-forge --continue-on-error"
    print "  publish-directory ./pkgs-out --method pd --recursive"
    print "  publish-status"
}
