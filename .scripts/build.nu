#!/usr/bin/env nu

# Comprehensive build script with smart checking and manifest tracking
# Combines features from build_with_manifest.nu and smart_build.nu

use check_package_exists.nu *
use manifest_utils.nu *
use std repeat

def main [
    package: string,                         # Package name to build
    --target-platform: string = "linux-64",  # Target platform
    --pkg-dir: string = "./pkgs",           # Package directory
    --output-dir: string = "./pkgs-out",    # Output directory
    --no-test,                              # Skip tests
    --force,                                # Force build even if package exists
    --check-remote,                         # Check remote repositories (default: true)
    --check-prefix,                         # Check prefix.dev repository
    --check-s3,                             # Check S3 repository
    --skip-existing: string = "all",        # Skip existing: "none", "local", "all"
    --dry-run,                              # Show what would be done without building
    --verbose,                              # Verbose output
] {
    let manifest_path = $output_dir | path join "conda-manifest.json"
    let recipe_dir = $pkg_dir | path join $package

    print $"🔨 Build for ($package) on ($target_platform)"

    # Check recipe exists
    if not ($recipe_dir | path exists) {
        print -e $"❌ Recipe directory not found: ($recipe_dir)"
        exit 1
    }

    # Read package metadata from recipe if available
    let recipe_file = $recipe_dir | path join "recipe.yaml"
    let recipe_data = if ($recipe_file | path exists) {
        open $recipe_file
    } else {
        print -e $"❌ Recipe path not found: ($recipe_dir)"
        exit 1
    }

    let package_version = if "package" in $recipe_data and "version" in $recipe_data.package {
        $recipe_data.package.version
    } else {
        ""
    }

    # Step 1: Check if package already exists (unless forced)
    if not $force and $check_remote != false {
        print "📍 Checking if package already exists..."
        print ""

        # Initialize results with defaults
        mut prefix_result = {found: false, count: 0}
        mut s3_result = {found: false, count: 0}

        # Always check conda-forge
        let conda_result = (check-conda-channel $package $package_version "conda-forge" $target_platform)
        if $conda_result.found {
            print $"  ✅ Found in conda-forge: ($conda_result.count) version(s)"
            if $verbose and ($conda_result.packages | length) > 0 {
                for pkg in ($conda_result.packages | first 3) {
                    print $"     - ($pkg.version) \(build ($pkg.build_number)\)"
                }
            }
        }

        # Check local builds
        let local_result = (check-local-builds $package $package_version $target_platform)
        if $local_result.found {
            print $"  ✅ Found locally: ($local_result.count) build(s)"
            if $verbose and ($local_result.packages | length) > 0 {
                for pkg in ($local_result.packages | first 3) {
                    print $"     - ($pkg.version) [($pkg.build)] - ($pkg.file)"
                }
            }
        }

        # Check prefix.dev if requested
        if $check_prefix {
            $prefix_result = (check-prefix-dev $package $package_version $target_platform)
            if $prefix_result.found {
                print $"  ✅ Found in prefix.dev: ($prefix_result.count) version(s)"
            } else if "error" in ($prefix_result | columns) {
                print $"  ⚠️  Could not check prefix.dev: ($prefix_result.error)"
            }
        }

        # Check S3 if requested
        if $check_s3 {
            $s3_result = (check-s3-repo $package $package_version $target_platform)
            if $s3_result.found {
                print $"  ✅ Found in S3: ($s3_result.count) version(s)"
            } else if "error" in ($s3_result | columns) {
                print $"  ⚠️  Could not check S3: ($s3_result.error)"
            }
        }

        print ""

        # Determine if we should skip
        let should_skip = match $skip_existing {
            "none" => false,
            "local" => $local_result.found,
            "all" => {
                ($conda_result.found or $local_result.found or ($check_prefix and $prefix_result.found) or ($check_s3 and $s3_result.found))
            },
            _ => {
                print -e $"Invalid --skip-existing value: ($skip_existing)"
                exit 1
            }
        }

        if $should_skip {
            print "⚠️  Package already exists!"

            if $dry_run {
                print "   🔍 DRY RUN: Would skip building this package"
                exit 0
            }

            # Check if we have a local build we can use
            if $local_result.found and ($local_result.packages | length) > 0 {
                let existing_pkg = $local_result.packages | first
                let existing_path = $output_dir | path join $target_platform | path join $existing_pkg.file

                if ($existing_path | path exists) {
                    update_manifest $manifest_path $package $target_platform $existing_path "skipped"
                    print ""
                    print $"📦 Using existing package: ($existing_pkg.file)"
                    print $"📝 Manifest updated: ($manifest_path)"
                }
            }

            print ""
            print "Options:"
            print "  1. Use --force to rebuild anyway"
            print "  2. Use --skip-existing=local to only skip if locally built"
            print "  3. Use --skip-existing=none to always build"

            if $local_result.found {
                print ""
                print "💡 Tip: You can publish the existing local build with:"
                print $"   pixi run publish-pd ($package) ($target_platform)"
                print $"   pixi run publish-s3 ($package) ($target_platform)"
            }

            exit 0
        }
    }

    # Step 2: Build the package
    if $dry_run {
        print "🔍 DRY RUN: Would build package with following settings:"
        print $"   Package: ($package)"
        print $"   Platform: ($target_platform)"
        print $"   Skip tests: ($no_test)"
        print $"   Skip existing: ($skip_existing)"
        print ""
        print "Command that would be executed:"

        let cmd_args = build-command-args $recipe_dir $output_dir $target_platform $skip_existing $no_test $verbose
        print $"   rattler-build (($cmd_args | str join ' '))"

        exit 0
    }

    print "🚀 Building package..."
    print ""

    # Build the rattler-build command arguments
    let cmd_args = build-command-args $recipe_dir $output_dir $target_platform $skip_existing $no_test $verbose
    print $"Running: rattler-build (($cmd_args | str join ' '))"

    # Execute build
    let start_time = date now
    let build_result = (^rattler-build ...$cmd_args | complete)
    let duration = ((date now) - $start_time)

    if $build_result.exit_code != 0 {
        print -e ""
        print -e $"❌ Build failed! \(duration: ($duration)\)"

        if not ($build_result.stderr | is-empty) {
            print -e ""
            print -e "Error output:"
            print -e ($build_result.stderr | lines | last 20 | str join "\n")
        }

        exit $build_result.exit_code
    }

    # Parse the output to find the built conda file
    let all_output = $build_result.stdout + "\n" + $build_result.stderr
    let output_lines = $all_output | lines
    let matching_lines = $output_lines | where { |line| $line | str contains "Archive written to" }
    let archive_line = if ($matching_lines | length) > 0 { $matching_lines | last } else { null }

    if $archive_line == null {
        # Check if build was skipped
        let skip_lines = $output_lines | where { |line| $line | str contains "Skipping build" }
        let skip_line = if ($skip_lines | length) > 0 { $skip_lines | last } else { null }
        if $skip_line != null {
            print "Build was skipped (package already exists)"

            # Try to find existing package using glob
            let pattern = $output_dir | path join $target_platform | path join $"($package)-*.conda"
            let matches = glob $pattern
            let existing_file = if ($matches | is-empty) { "" } else { $matches | last }

            if not ($existing_file | is-empty) {
                update_manifest $manifest_path $package $target_platform $existing_file "skipped"
                print $"📦 Package already exists: ($existing_file | path basename)"
                print $"📝 Manifest updated: ($manifest_path)"
            }
        } else {
            print -e "Could not find built conda file in output"
        }
        exit 0
    }

    # Extract the file path from the archive line
    let conda_path = if ($archive_line | str contains "'") {
        $archive_line | str replace "Archive written to '" "" | str replace "'" "" | str trim
    } else {
        $archive_line | str replace "Archive written to " "" | str trim
    }

    # Verify the file exists
    if not ($conda_path | path exists) {
        print -e $"Error: Built file not found at ($conda_path)"
        exit 1
    }

    # Update the manifest
    update_manifest $manifest_path $package $target_platform $conda_path "built"

    print ""
    print $"✅ Build successful! \(duration: ($duration)\)"
    print $"📦 Package: ($conda_path | path basename)"
    print $"📝 Manifest updated: ($manifest_path)"

    print ""
    print "Next steps:"
    print $"  • Test: pixi run test ($package) ($target_platform)"
    print $"  • Publish to prefix.dev: pixi run publish-pd ($package) ($target_platform)"
    print $"  • Publish to S3: pixi run publish-s3 ($package) ($target_platform)"
    print $"  • Publish to S3 local: pixi run publish-s3-local ($package) ($target_platform)"
}

# Build the rattler-build command arguments
def "build-command-args" [
    recipe_dir: string,
    output_dir: string,
    platform: string,
    skip_existing: string,
    no_test: bool,
    verbose: bool
] {
    mut cmd_args = [
        "build",
        "--recipe-dir", $recipe_dir,
        "--output-dir", $output_dir,
        $"--skip-existing=($skip_existing)",
        "--target-platform", $platform,
        "--channel", "conda-forge",
    ]

    if $no_test {
        $cmd_args = ($cmd_args | append "--no-test")
    }

    if $verbose {
        $cmd_args = ($cmd_args | append "-vvv")
    } else {
        $cmd_args = ($cmd_args | append "-v")
    }

    $cmd_args
}

# Update the manifest file with build information
def update_manifest [
    manifest_path: string,
    package: string,
    platform: string,
    conda_path: string,
    status: string
] {
    # Load existing manifest or create new one
    let manifest = if ($manifest_path | path exists) {
        open $manifest_path
    } else {
        {}
    }

    # Get file info
    let file_info = ls $conda_path | first

    # Create build record
    let build_record = {
        path: $conda_path
        filename: ($conda_path | path basename)
        size: $file_info.size
        modified: $file_info.modified
        build_time: (date now | format date "%Y-%m-%d %H:%M:%S %z")
        status: $status
    }

    # Update manifest structure: {platform: {package: build_info}}
    let updated_manifest = if ($platform in $manifest) {
        # Platform exists
        let platform_data = $manifest | get $platform
        let updated_platform = if ($package in $platform_data) {
            $platform_data | update $package $build_record
        } else {
            $platform_data | insert $package $build_record
        }
        $manifest | update $platform $updated_platform
    } else {
        # New platform
        $manifest | insert $platform {($package): $build_record}
    }

    # Create output directory if it doesn't exist
    let output_dir = $manifest_path | path dirname
    if not ($output_dir | path exists) {
        mkdir $output_dir
    }

    # Save the updated manifest
    $updated_manifest | to json --indent 2 | save -f $manifest_path
}

# Helper function to get the latest build for a package
export def "get-latest-build" [
    package: string,
    --platform: string = "linux-64",
    --manifest-path: string = "./pkgs-out/conda-manifest.json"
] {
    if not ($manifest_path | path exists) {
        print -e "No manifest file found"
        return null
    }

    let manifest = open $manifest_path

    if ($platform in $manifest) and ($package in ($manifest | get $platform)) {
        return ($manifest | get $platform | get $package)
    }

    return null
}

# Helper function to list all builds in the manifest
export def "list-builds" [
    --manifest-path: string = "./pkgs-out/conda-manifest.json"
] {
    if not ($manifest_path | path exists) {
        print -e "No manifest file found"
        return
    }

    let manifest = open $manifest_path

    for platform in ($manifest | columns) {
        print $"Platform: ($platform)"
        let packages = $manifest | get $platform
        for package in ($packages | columns) {
            let info = $packages | get $package
            print $"  ($package): ($info.filename) \(($info.status)\)"
        }
    }
}

# Helper function for batch builds with smart checking
export def "build-all" [
    --platform: string = "linux-64",
    --force,                                # Force rebuild all
    --check-prefix,                         # Check prefix.dev
    --check-s3,                             # Check S3
    --continue-on-error,                    # Continue if a build fails
    --dry-run,                              # Show what would be built
    --no-test,                              # Skip tests for all builds
] {
    print "🔨 Build All Packages"
    print "=" * 60

    # Get all package directories
    let pkg_dirs = ls ./pkgs | where type == "dir" | get name

    if ($pkg_dirs | length) == 0 {
        print "No package directories found in ./pkgs"
        exit 1
    }

    print $"Found ($pkg_dirs | length) packages to process"
    print ""

    mut built = 0
    mut skipped = 0
    mut failed = 0
    mut results = []

    for pkg_path in $pkg_dirs {
        let pkg_name = $pkg_path | path basename

        print $"Processing ($pkg_name)..."

        let result = (do {
            main $pkg_name --target-platform $platform --force=$force --check-prefix=$check_prefix --check-s3=$check_s3 --dry-run=$dry_run --no-test=$no_test
        } | complete)

        if $result.exit_code == 0 {
            if ($result.stdout | str contains "already exists") {
                $skipped = $skipped + 1
                $results = ($results | append {
                    package: $pkg_name,
                    status: "⏭️  SKIPPED",
                    reason: "Already exists"
                })
            } else {
                $built = $built + 1
                $results = ($results | append {
                    package: $pkg_name,
                    status: "✅ BUILT",
                    reason: "Success"
                })
            }
        } else {
            $failed = $failed + 1
            $results = ($results | append {
                package: $pkg_name,
                status: "❌ FAILED",
                reason: "Build error"
            })

            if not $continue_on_error {
                print -e ""
                print -e "Stopping due to build failure. Use --continue-on-error to continue."
                break
            }
        }

        print ""
        print "─" * 60
        print ""
    }

    # Print summary
    print "Build Summary:"
    print "=============="
    $results | to md
    print ""

    let action = if $dry_run { "Would process" } else { "Processed" }
    print $"($action): ($pkg_dirs | length) packages"
    print $"  Built: ($built)"
    print $"  Skipped: ($skipped)"
    print $"  Failed: ($failed)"

    if $failed > 0 and not $dry_run {
        exit 1
    }
}

# Quick status check for a package
export def "package-status" [
    package: string,
    --platform: string = "linux-64"
] {
    print $"📊 Status for ($package) on ($platform)"
    print (1..40 | each { "=" } | str join "")

    # Check all locations
    print ""
    print "Repository Status:"

    # Check conda-forge
    let conda_result = (check-conda-channel $package "" "conda-forge" $platform)
    if $conda_result.found {
        print $"  ✅ conda-forge: ($conda_result.count) version(s)"
    } else {
        print "  ❌ conda-forge: not found"
    }

    # Check local builds
    let local_result = (check-local-builds $package "" $platform)
    if $local_result.found {
        print $"  ✅ local: ($local_result.count) build(s)"
    } else {
        print "  ❌ local: not found"
    }

    # Check manifest for build info
    let manifest_info = (get-latest-build $package --platform $platform)

    if $manifest_info != null {
        print ""
        print "📝 Build Manifest Info:"
        print $"   Last built: ($manifest_info.build_time)"
        print $"   File: ($manifest_info.filename)"
        print $"   Size: (($manifest_info.size / 1024 / 1024) | math round -p 2) MB"
        print $"   Status: ($manifest_info.status)"
        print $"   Path: ($manifest_info.path)"
    } else {
        print ""
        print "📝 No build manifest entry found"
    }
}

# Helper to clean up old builds
export def "clean-old-builds" [
    --days: int = 7,                        # Remove builds older than N days
    --keep-latest: int = 3,                 # Keep at least N latest builds per package
    --dry-run,                              # Show what would be deleted
] {
    print $"🧹 Cleaning old builds (older than ($days) days, keeping latest ($keep_latest))"

    let manifest_path = "./pkgs-out/conda-manifest.json"
    if not ($manifest_path | path exists) {
        print "No manifest file found"
        return
    }

    let manifest = open $manifest_path
    let cutoff_date = (date now) - ($days * 24hr)

    mut files_to_delete = []

    for platform in ($manifest | columns) {
        let packages = $manifest | get $platform

        for package in ($packages | columns) {
            let builds = $packages | get $package

            # For packages with multiple builds, we'd need to handle this differently
            # For now, just check single build entries
            if "modified" in ($builds | columns) {
                let modified_date = $builds.modified | into datetime

                if $modified_date < $cutoff_date {
                    $files_to_delete = ($files_to_delete | append $builds.path)
                }
            }
        }
    }

    if ($files_to_delete | length) == 0 {
        print "No old builds to clean"
        return
    }

    print $"Found ($files_to_delete | length) old builds to remove:"
    for file in $files_to_delete {
        print $"  - ($file | path basename)"
    }

    if $dry_run {
        print ""
        print "🔍 DRY RUN - no files were deleted"
    } else {
        print ""
        print "Deleting old builds..."
        for file in $files_to_delete {
            if ($file | path exists) {
                rm $file
                print $"  ✓ Deleted ($file | path basename)"
            }
        }
        print "✅ Cleanup complete"
    }
}
