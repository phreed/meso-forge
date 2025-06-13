#!/usr/bin/env nu

# Simple wrapper for rattler-build that tracks output files in a manifest
# Usage: nu build_and_track.nu <package> [--target-platform <platform>] [--no-test]

def main [
    package: string,                         # Package name
    --target-platform: string = "linux-64",  # Target platform
    --no-test,                              # Skip tests
] {
    let pkg_dir = "./pkgs"
    let output_dir = "./pkgs-out"
    let manifest_file = $output_dir | path join "conda-manifest.json"
    let recipe_dir = $pkg_dir | path join $package

    # Check recipe exists
    if not ($recipe_dir | path exists) {
        print -e $"Recipe directory not found: ($recipe_dir)"
        exit 1
    }

    # Build command string
    let cmd = if $no_test {
        $"rattler-build build --recipe-dir ($recipe_dir) --output-dir ($output_dir) --skip-existing=local --target-platform=($target_platform) --channel conda-forge --no-test -vvv"
    } else {
        $"rattler-build build --recipe-dir ($recipe_dir) --output-dir ($output_dir) --skip-existing=local --target-platform=($target_platform) --channel conda-forge -vvv"
    }

    print $"Running: ($cmd)"

    # Execute and capture output
    let output = (do { bash -c $cmd } | complete)

    if $output.exit_code != 0 {
        print -e "Build failed!"
        print -e $output.stderr
        exit 1
    }

    # Look for the built file in both stdout and stderr
    let all_output = $output.stdout + "\n" + $output.stderr
    let output_lines = $all_output | lines
    let archive_lines = $output_lines | where { |line| $line | str contains "Archive written to" }
    let archive_line = if ($archive_lines | is-empty) { null } else { $archive_lines | last }

    if $archive_line == null {
        # Check if skipped
        if (($output_lines | where { |line| $line | str contains "Skipping build" } | length) > 0) {
            print "Build was skipped - package already exists"

            # Find existing package
            let pattern = $output_dir | path join $target_platform | path join $"($package)-*.conda"
            let matches = glob $pattern
            let existing = if ($matches | is-empty) { null } else { $matches | last }

            if $existing != null {
                save_to_manifest $manifest_file $package $target_platform $existing "skipped"
                print $"Found existing: ($existing)"
            }
            exit 0
        }

        print -e "Could not find output file in build log"
        exit 1
    }

    # Extract path from "Archive written to '/path/to/file.conda'"
    let conda_path = $archive_line
        | str replace "Archive written to '" ""
        | str replace "'" ""
        | str replace "Archive written to " ""
        | str trim

    if not ($conda_path | path exists) {
        print -e $"Output file not found: ($conda_path)"
        exit 1
    }

    # Save to manifest
    save_to_manifest $manifest_file $package $target_platform $conda_path "built"

    print $"✅ Build successful: ($conda_path)"
    print $"📝 Manifest updated: ($manifest_file)"
}

def save_to_manifest [
    manifest_file: string,
    package: string,
    platform: string,
    conda_path: string,
    status: string
] {
    # Load or create manifest
    let manifest = if ($manifest_file | path exists) {
        open $manifest_file
    } else {
        {}
    }

    # Get file info
    let file_stat = ls $conda_path | first

    # Create entry
    let entry = {
        path: $conda_path,
        filename: ($conda_path | path basename),
        size: $file_stat.size,
        modified: $file_stat.modified,
        build_time: (date now | format date "%Y-%m-%d %H:%M:%S"),
        status: $status
    }

    # Update manifest
    let new_manifest = if ($platform in $manifest) {
        let platform_data = $manifest | get $platform
        let updated_platform = if ($package in $platform_data) {
            $platform_data | update $package $entry
        } else {
            $platform_data | insert $package $entry
        }
        $manifest | update $platform $updated_platform
    } else {
        $manifest | insert $platform { $package: $entry }
    }

    # Ensure output dir exists
    let dir = $manifest_file | path dirname
    if not ($dir | path exists) {
        mkdir $dir
    }

    # Save
    $new_manifest | to json --indent 2 | save -f $manifest_file
}

# Helper to read manifest
export def read-manifest [
    --manifest: string = "./pkgs-out/conda-manifest.json"
] {
    if not ($manifest | path exists) {
        return {}
    }
    open $manifest
}

# Helper to get build info for a package
export def get-build-info [
    package: string,
    --platform: string = "linux-64",
    --manifest: string = "./pkgs-out/conda-manifest.json"
] {
    let data = read-manifest --manifest $manifest
    if ($platform in $data) and ($package in ($data | get $platform)) {
        $data | get $platform | get $package
    } else {
        null
    }
}
