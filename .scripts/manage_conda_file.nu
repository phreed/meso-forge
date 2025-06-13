#!/usr/bin/env nu

# Nushell module for managing conda files reliably
# Provides functions to find and manage built conda packages

# Default manifest path
const DEFAULT_MANIFEST = "./pkgs-out/conda-manifest.json"

# Find the most recent conda file for a given package and platform
export def "find-conda-file" [
    package_name: string,           # Name of the package to find
    platform: string = "linux-64", # Target platform (default: linux-64)
    output_dir: string = "./pkgs-out", # Output directory (default: ./pkgs-out)
    --quiet (-q)                    # Suppress error messages
] {
    let manifest_path = $output_dir | path join "conda-manifest.json"

    # Check if manifest exists
    if not ($manifest_path | path exists) {
        if not $quiet {
            print -e $"Manifest file does not exist: ($manifest_path)"
        }
        return ""
    }

    # Read manifest
    let manifest = open $manifest_path

    # Check if platform exists in manifest
    if not ($platform in $manifest) {
        if not $quiet {
            print -e $"Platform '($platform)' not found in manifest"
        }
        return ""
    }

    # Check if package exists for this platform
    let platform_data = $manifest | get $platform
    if not ($package_name in $platform_data) {
        if not $quiet {
            print -e $"No conda files found for package '($package_name)' on platform '($platform)'"
        }
        return ""
    }

    # Get package info
    let package_info = $platform_data | get $package_name
    let conda_path = $package_info.path

    # Verify file still exists
    if not ($conda_path | path exists) {
        if not $quiet {
            print -e $"Conda file in manifest no longer exists: ($conda_path)"
        }
        return ""
    }

    return $conda_path
}

# List all conda files for a given package and platform
export def "list-all-conda-files" [
    package_name: string,           # Name of the package to find
    platform: string = "linux-64", # Target platform (default: linux-64)
    output_dir: string = "./pkgs-out" # Output directory (default: ./pkgs-out)
] {
    let manifest_path = $output_dir | path join "conda-manifest.json"

    # Check if manifest exists
    if not ($manifest_path | path exists) {
        return []
    }

    # Read manifest
    let manifest = open $manifest_path

    # Check if platform exists
    if not ($platform in $manifest) {
        return []
    }

    # Get all packages for platform and filter by name
    let platform_data = $manifest | get $platform
    let matching_packages = $platform_data
    | columns
    | where { |pkg| $pkg == $package_name }

    if ($matching_packages | is-empty) {
        return []
    }

    # Return paths that still exist
    $matching_packages
    | each { |pkg|
        let info = $platform_data | get $pkg
        if ($info.path | path exists) {
            $info.path
        }
    }
    | compact
}

# Check if a conda file exists for the given package
export def "conda-file-exists" [
    package_name: string,           # Name of the package to check
    platform: string = "linux-64", # Target platform (default: linux-64)
    output_dir: string = "./pkgs-out" # Output directory (default: ./pkgs-out)
] {
    let file = find-conda-file $package_name $platform $output_dir --quiet
    not ($file | is-empty)
}

# Get conda file info (path, size, modification time)
export def "conda-file-info" [
    package_name: string,           # Name of the package to get info for
    platform: string = "linux-64", # Target platform (default: linux-64)
    output_dir: string = "./pkgs-out" # Output directory (default: ./pkgs-out)
] {
    let manifest_path = $output_dir | path join "conda-manifest.json"

    # Check if manifest exists
    if not ($manifest_path | path exists) {
        return null
    }

    # Read manifest
    let manifest = open $manifest_path

    # Check if platform and package exist
    if not ($platform in $manifest) {
        return null
    }

    let platform_data = $manifest | get $platform
    if not ($package_name in $platform_data) {
        return null
    }

    # Get package info from manifest
    let package_info = $platform_data | get $package_name

    # Verify file still exists
    if not ($package_info.path | path exists) {
        return null
    }

    # Return info from manifest
    {
        path: $package_info.path,
        name: $package_info.filename,
        size: $package_info.size,
        modified: $package_info.modified,
        type: "file"
    }
}

# Remove conda file for the given package
export def "remove-conda-file" [
    package_name: string,           # Name of the package to remove
    platform: string = "linux-64", # Target platform (default: linux-64)
    output_dir: string = "./pkgs-out", # Output directory (default: ./pkgs-out)
    --quiet (-q)                    # Suppress messages
] {
    let file = find-conda-file $package_name $platform $output_dir --quiet

    if ($file | is-empty) {
        if not $quiet {
            print $"No conda file found for ($package_name) on ($platform)"
        }
        return false
    }

    try {
        # Remove the file
        rm $file
        if not $quiet {
            print $"Removed: ($file | path basename)"
        }

        # Update the manifest
        let manifest_path = $output_dir | path join "conda-manifest.json"
        if ($manifest_path | path exists) {
            let manifest = open $manifest_path

            # Remove entry from manifest if it exists
            if ($platform in $manifest) {
                let platform_data = $manifest | get $platform
                if ($package_name in $platform_data) {
                    # Remove the package entry
                    let updated_platform = $platform_data | reject $package_name

                    # Update or remove platform based on whether it has any packages left
                    let updated_manifest = if ($updated_platform | columns | is-empty) {
                        # Remove empty platform
                        $manifest | reject $platform
                    } else {
                        # Update platform with remaining packages
                        $manifest | update $platform $updated_platform
                    }

                    # Save updated manifest
                    $updated_manifest | to json --indent 2 | save -f $manifest_path

                    if not $quiet {
                        print "Updated manifest"
                    }
                }
            }
        }

        return true
    } catch { |err|
        if not $quiet {
            print -e $"Failed to remove ($file): ($err.msg)"
        }
        return false
    }
}

# Main command-line interface (for standalone usage)
export def main [
    package_name: string,           # Name of the package to find
    platform: string = "linux-64", # Target platform (default: linux-64)
    --output-dir: string = "./pkgs-out", # Output directory (default: ./pkgs-out)
    --list-all                      # List all matching files instead of just the latest
    --quiet (-q)                    # Suppress stderr output
    --info                          # Show file info instead of just path
    --exists                        # Check if file exists (exit code 0/1)
] {
    if $exists {
        if (conda-file-exists $package_name $platform $output_dir) {
            exit 0
        } else {
            exit 1
        }
    }

    if $list_all {
        let files = list-all-conda-files $package_name $platform $output_dir
        if ($files | is-empty) {
            if not $quiet {
                print -e $"No conda files found for package '($package_name)'"
            }
            exit 1
        }
        $files | each { |f| print $f }
        return
    }

    if $info {
        let file_info = conda-file-info $package_name $platform $output_dir
        if ($file_info == null) {
            if not $quiet {
                print -e $"No conda file found for package '($package_name)'"
            }
            exit 1
        }
        print ($file_info | to json)
        return
    }

    let file = find-conda-file $package_name $platform $output_dir --quiet=$quiet
    if ($file | is-empty) {
        exit 1
    }

    print $file
}
