#!/usr/bin/env nu

# Build a conda package and save the output path to a manifest file
# This script wraps rattler-build and captures the output file path

# Parse command line arguments
def main [
    package: string,                     # Package name to build
    --target-platform: string = "linux-64",  # Target platform
    --pkg-dir: string = "./pkgs",        # Package directory
    --output-dir: string = "./pkgs-out", # Output directory
    --no-test,                          # Skip tests
    --verbose,                          # Verbose output
] {
    let manifest_path = $output_dir | path join "conda-manifest.json"
    let recipe_dir = $pkg_dir | path join $package

    # Check if recipe directory exists
    if not ($recipe_dir | path exists) {
        print -e $"Error: Recipe directory '($recipe_dir)' does not exist"
        exit 1
    }

    # Build the rattler-build command
    # Build the command as a string first, then split it
    mut cmd_str = $"rattler-build build --recipe-dir ($recipe_dir) --output-dir ($output_dir) --skip-existing=local --target-platform=($target_platform) --channel conda-forge"

    if $no_test {
        $cmd_str = $"($cmd_str) --no-test"
    }

    if $verbose {
        $cmd_str = $"($cmd_str) -vvv"
    }

    let cmd_with_options = $cmd_str | split row " "

    print $"Running: ($cmd_str)"

    # Run the build command and capture output
    # Use with-env to ensure we capture both stdout and stderr
    let build_result = (do {
        with-env { } {
            run-external $cmd_with_options.0 ...($cmd_with_options | skip 1)
        }
    } | complete)

    if $build_result.exit_code != 0 {
        print -e "Build failed!"
        print -e $build_result.stderr
        exit $build_result.exit_code
    }

    # Parse the output to find the built conda file
    let output_lines = $build_result.stdout | lines
    let archive_line = $output_lines | where { |line| $line | str contains "Archive written to" } | last?

    if $archive_line == null {
        # Check if build was skipped
        let skip_line = $output_lines | where { |line| $line | str contains "Skipping build for" } | last?
        if $skip_line != null {
            print "Build was skipped (package already exists)"

            # Try to find existing package using glob
            let pattern = $output_dir | path join $target_platform | path join $"($package)-*.conda"
            let matches = glob $pattern
            let existing_file = if ($matches | is-empty) { "" } else { $matches | last }

            if not ($existing_file | is-empty) {
                update_manifest $manifest_path $package $target_platform $existing_file "skipped"
                print $"Package already exists: ($existing_file)"
            }
        } else {
            print -e "Could not find built conda file in output"
        }
        exit 0
    }

    # Extract the file path from the line
    # Format: "Archive written to '/path/to/file.conda'"
    let conda_path = if ($archive_line | str contains "'") {
        # Format with quotes
        $archive_line | str replace "Archive written to '" "" | str replace "'" "" | str trim
    } else {
        # Format without quotes
        $archive_line | str replace "Archive written to " "" | str trim
    }

    # Verify the file exists
    if not ($conda_path | path exists) {
        print -e $"Error: Built file not found at ($conda_path)"
        exit 1
    }

    # Update the manifest
    update_manifest $manifest_path $package $target_platform $conda_path "built"

    print $"✅ Build successful: ($conda_path)"
    print $"📝 Manifest updated: ($manifest_path)"
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
        let platform_data = $manifest | get $platform | update $package $build_record
        $manifest | update $platform $platform_data
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
            print $"  ($package): ($info.filename) (($info.status))"
        }
    }
}
