#!/usr/bin/env nu

# Nushell module for managing conda files reliably
# Provides functions to find and manage built conda packages

# Find the most recent conda file for a given package and platform
export def "find-conda-file" [
    package_name: string,           # Name of the package to find
    platform: string = "linux-64", # Target platform (default: linux-64)
    output_dir: string = "./pkgs-out", # Output directory (default: ./pkgs-out)
    --quiet (-q)                    # Suppress error messages
] {
    let platform_dir = $output_dir | path join $platform

    # Check if platform directory exists
    if not ($platform_dir | path exists) {
        if not $quiet {
            print -e $"Platform directory does not exist: ($platform_dir)"
        }
        return ""
    }

    # Find all matching conda files
    let pattern = $platform_dir | path join $"($package_name)-*.conda"
    let matches = glob $pattern

    if ($matches | is-empty) {
        if not $quiet {
            print -e $"No conda files found for package '($package_name)' in ($platform_dir)"
        }
        return ""
    }

    if ($matches | length) == 1 {
        return ($matches | first)
    }

    # If multiple matches, return the most recently modified
    let latest_file = $matches
    | each { |file|
        {
            path: $file,
            modified: ($file | path expand | ls | first | get modified)
        }
    }
    | sort-by modified --reverse
    | first
    | get path

    if not $quiet {
        print -e $"Found ($matches | length) conda files for '($package_name)', using most recent: ($latest_file | path basename)"
    }

    return $latest_file
}

# List all conda files for a given package and platform
export def "list-all-conda-files" [
    package_name: string,           # Name of the package to find
    platform: string = "linux-64", # Target platform (default: linux-64)
    output_dir: string = "./pkgs-out" # Output directory (default: ./pkgs-out)
] {
    let platform_dir = $output_dir | path join $platform

    if not ($platform_dir | path exists) {
        return []
    }

    let pattern = $platform_dir | path join $"($package_name)-*.conda"
    let matches = glob $pattern

    if ($matches | is-empty) {
        return []
    }

    # Sort by modification time, newest first
    $matches
    | each { |file|
        {
            path: $file,
            modified: ($file | path expand | ls | first | get modified)
        }
    }
    | sort-by modified --reverse
    | get path
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
    let file = find-conda-file $package_name $platform $output_dir --quiet

    if ($file | is-empty) {
        return null
    }

    let info = $file | path expand | ls | first
    {
        path: $file,
        name: ($file | path basename),
        size: $info.size,
        modified: $info.modified,
        type: $info.type
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
        rm $file
        if not $quiet {
            print $"Removed: ($file | path basename)"
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
