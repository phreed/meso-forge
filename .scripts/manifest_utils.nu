#!/usr/bin/env nu

# Comprehensive utilities for working with the conda build manifest
# Combines functionality from manage_conda_file.nu and manifest_utils.nu

# Default manifest path
const DEFAULT_MANIFEST = "./pkgs-out/conda-manifest.json"

# Read the manifest file
export def read-manifest [
    --manifest: string = $DEFAULT_MANIFEST  # Path to manifest file
] {
    if not ($manifest | path exists) {
        return {}
    }
    open $manifest
}

# Get build info for a specific package
export def get-package-info [
    package: string,                         # Package name
    --platform: string = "linux-64",         # Target platform
    --manifest: string = $DEFAULT_MANIFEST   # Path to manifest file
] {
    let data = read-manifest --manifest $manifest

    if ($platform in $data) and ($package in ($data | get $platform)) {
        $data | get $platform | get $package
    } else {
        null
    }
}

# Get the conda file path for a package
export def get-package-path [
    package: string,                         # Package name
    --platform: string = "linux-64",         # Target platform
    --manifest: string = $DEFAULT_MANIFEST   # Path to manifest file
] {
    let info = get-package-info $package --platform $platform --manifest $manifest

    if $info != null {
        $info.path
    } else {
        ""
    }
}

# Find the most recent conda file for a given package and platform
# (Alias for get-package-path for backward compatibility)
export def find-conda-file [
    package_name: string,                    # Name of the package to find
    platform: string = "linux-64",           # Target platform (default: linux-64)
    output_dir: string = "./pkgs-out",       # Output directory (default: ./pkgs-out)
    --quiet (-q)                             # Suppress error messages
] {
    let manifest_path = $output_dir | path join "conda-manifest.json"
    let conda_path = get-package-path $package_name --platform $platform --manifest $manifest_path

    if ($conda_path | is-empty) {
        if not $quiet {
            print -e $"No conda file found for package '($package_name)' on platform '($platform)'"
        }
        return ""
    }

    # Verify file still exists
    if not ($conda_path | path exists) {
        if not $quiet {
            print -e $"Conda file in manifest no longer exists: ($conda_path)"
        }
        return ""
    }

    return $conda_path
}

# List all packages in the manifest
export def list-packages [
    --platform: string = "",                 # Filter by platform (empty for all)
    --manifest: string = $DEFAULT_MANIFEST   # Path to manifest file
] {
    let data = read-manifest --manifest $manifest

    if ($platform | is-empty) {
        # List all packages from all platforms
        mut all_packages = []

        for plat in ($data | columns) {
            let packages = $data | get $plat
            for pkg in ($packages | columns) {
                let info = $packages | get $pkg
                $all_packages = ($all_packages | append {
                    platform: $plat,
                    package: $pkg,
                    filename: $info.filename,
                    size: $info.size,
                    status: $info.status,
                    build_time: $info.build_time
                })
            }
        }

        $all_packages | sort-by platform package
    } else {
        # List packages for specific platform
        if $platform in $data {
            let packages = $data | get $platform
            mut pkg_list = []

            for pkg in ($packages | columns) {
                let info = $packages | get $pkg
                $pkg_list = ($pkg_list | append {
                    package: $pkg,
                    filename: $info.filename,
                    size: $info.size,
                    status: $info.status,
                    build_time: $info.build_time
                })
            }

            $pkg_list | sort-by package
        } else {
            []
        }
    }
}

# List all conda files for a given package across all platforms
export def list-each-conda-files [
    package_name: string,                    # Name of the package to find
    platform: string = "",                   # Target platform (empty for all)
    output_dir: string = "./pkgs-out"        # Output directory (default: ./pkgs-out)
] {
    let manifest_path = $output_dir | path join "conda-manifest.json"
    let data = read-manifest --manifest $manifest_path

    if ($data | is-empty) {
        return []
    }

    mut files = []

    if ($platform | is-empty) {
        # Check all platforms
        for plat in ($data | columns) {
            let platform_data = $data | get $plat
            if $package_name in $platform_data {
                let info = $platform_data | get $package_name
                if ($info.path | path exists) {
                    $files = ($files | append $info.path)
                }
            }
        }
    } else {
        # Check specific platform
        if $platform in $data {
            let platform_data = $data | get $platform
            if $package_name in $platform_data {
                let info = $platform_data | get $package_name
                if ($info.path | path exists) {
                    $files = ($files | append $info.path)
                }
            }
        }
    }

    $files
}

# Get packages that were actually built (not skipped)
export def get-built-packages [
    --platform: string = "",                 # Filter by platform (empty for all)
    --manifest: string = $DEFAULT_MANIFEST   # Path to manifest file
] {
    list-packages --platform $platform --manifest $manifest | where status == "built"
}

# Get packages that were skipped
export def get-skipped-packages [
    --platform: string = "",                 # Filter by platform (empty for all)
    --manifest: string = $DEFAULT_MANIFEST   # Path to manifest file
] {
    list-packages --platform $platform --manifest $manifest | where status == "skipped"
}

# Check if a package exists in the manifest
export def package-exists [
    package: string,                         # Package name
    --platform: string = "linux-64",         # Target platform
    --manifest: string = $DEFAULT_MANIFEST   # Path to manifest file
] {
    let info = get-package-info $package --platform $platform --manifest $manifest
    $info != null
}

# Check if a conda file exists for the given package
# (Wrapper around package-exists for backward compatibility)
export def conda-file-exists [
    package_name: string,                    # Name of the package to check
    platform: string = "linux-64",           # Target platform (default: linux-64)
    output_dir: string = "./pkgs-out"        # Output directory (default: ./pkgs-out)
] {
    let manifest_path = $output_dir | path join "conda-manifest.json"
    package-exists $package_name --platform $platform --manifest $manifest_path
}

# Get conda file info (path, size, modification time)
export def conda-file-info [
    package_name: string,                    # Name of the package to get info for
    platform: string = "linux-64",           # Target platform (default: linux-64)
    output_dir: string = "./pkgs-out"        # Output directory (default: ./pkgs-out)
] {
    let manifest_path = $output_dir | path join "conda-manifest.json"
    let package_info = get-package-info $package_name --platform $platform --manifest $manifest_path

    if $package_info == null {
        return null
    }

    # Verify file still exists
    if not ($package_info.path | path exists) {
        return null
    }

    # Return info in expected format
    {
        path: $package_info.path,
        name: $package_info.filename,
        size: $package_info.size,
        modified: $package_info.modified,
        type: "file"
    }
}

# Remove conda file for the given package
export def remove-conda-file [
    package_name: string,                    # Name of the package to remove
    platform: string = "linux-64",           # Target platform (default: linux-64)
    output_dir: string = "./pkgs-out",       # Output directory (default: ./pkgs-out)
    --quiet (-q)                             # Suppress messages
] {
    let manifest_path = $output_dir | path join "conda-manifest.json"
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

# Get publish command for a package using the manifest
export def get-publish-command [
    package: string,                         # Package name
    channel: string,                         # Channel to publish to (pd or s3)
    --platform: string = "linux-64",         # Target platform
    --manifest: string = $DEFAULT_MANIFEST   # Path to manifest file
] {
    let conda_path = get-package-path $package --platform $platform --manifest $manifest

    if ($conda_path | is-empty) {
        print -e $"Package '($package)' not found in manifest for platform '($platform)'"
        return ""
    }

    if $channel == "pd" {
        $"rattler-build upload prefix --skip-existing -vvv --channel meso-forge ($conda_path)"
    } else if $channel == "s3" {
        $"rattler-build upload s3 --channel 's3://pixi/meso-forge' --region auto --endpoint-url 'https://minio.isis.vanderbilt.edu' --force-path-style -vvv ($conda_path)"
    } else {
        print -e $"Unknown channel: ($channel). Use 'pd' or 's3'"
        ""
    }
}

# Publish a package using the manifest
export def publish-from-manifest [
    package: string,                         # Package name
    channel: string,                         # Channel to publish to (pd or s3)
    --platform: string = "linux-64",         # Target platform
    --manifest: string = $DEFAULT_MANIFEST,  # Path to manifest file
    --dry-run                                # Just print the command, don't execute
] {
    let cmd = get-publish-command $package $channel --platform $platform --manifest $manifest

    if ($cmd | is-empty) {
        return
    }

    if $dry_run {
        print $"Would run: ($cmd)"
    } else {
        print $"Publishing ($package) to ($channel)..."
        nu -c $cmd
    }
}

# Show manifest summary
export def manifest-summary [
    --manifest: string = $DEFAULT_MANIFEST   # Path to manifest file
] {
    let data = read-manifest --manifest $manifest

    if ($data | is-empty) {
        print "No packages in manifest"
        return
    }

    print "=== Conda Build Manifest Summary ==="
    print ""

    for platform in ($data | columns | sort) {
        let packages = $data | get $platform
        let total = $packages | columns | length
        let built = $packages | values | where status == "built" | length
        let skipped = $packages | values | where status == "skipped" | length

        print $"Platform: ($platform)"
        print $"  Total packages: ($total)"
        print $"  Built: ($built)"
        print $"  Skipped: ($skipped)"
        print ""

        # Show package details
        for pkg in ($packages | columns | sort) {
            let info = $packages | get $pkg
            let size_mb = ($info.size / 1024 / 1024 | math round -p 2)
            print $"  - ($pkg): ($info.filename) \(($size_mb) MB, ($info.status)\)"
        }
        print ""
    }
}

# Clean up manifest entries for packages that no longer exist
export def manifest-cleanup [
    --manifest: string = $DEFAULT_MANIFEST,  # Path to manifest file
    --dry-run                                # Just show what would be removed
] {
    let data = read-manifest --manifest $manifest
    mut new_data = {}
    mut removed = 0

    for platform in ($data | columns) {
        let packages = $data | get $platform
        mut new_packages = {}

        for pkg in ($packages | columns) {
            let info = $packages | get $pkg

            if ($info.path | path exists) {
                $new_packages = ($new_packages | insert $pkg $info)
            } else {
                print $"Would remove: ($platform)/($pkg) - file not found: ($info.path)"
                $removed = $removed + 1
            }
        }

        if ($new_packages | columns | length) > 0 {
            $new_data = ($new_data | insert $platform $new_packages)
        }
    }

    if $removed > 0 {
        if $dry_run {
            print $"\nWould remove ($removed) entries"
        } else {
            $new_data | to json --indent 2 | save -f $manifest
            print $"\nRemoved ($removed) entries from manifest"
        }
    } else {
        print "No cleanup needed - all files exist"
    }
}

# Example usage function
export def manifest-help [] {
    print "=== Manifest Utilities Help ==="
    print ""
    print "Available commands:"
    print "  read-manifest                        - Read the manifest file"
    print "  get-package-info <pkg>               - Get info for a specific package"
    print "  get-package-path <pkg>               - Get conda file path for a package"
    print "  find-conda-file <pkg>                - Find conda file (alias for get-package-path)"
    print "  list-packages                        - List all packages"
    print "  list-each-conda-files <pkg>          - List all conda files for a package"
    print "  get-built-packages                   - List only built packages"
    print "  get-skipped-packages                 - List only skipped packages"
    print "  package-exists <pkg>                 - Check if package is in manifest"
    print "  conda-file-exists <pkg>              - Check if conda file exists (backward compat)"
    print "  conda-file-info <pkg>                - Get detailed file info"
    print "  remove-conda-file <pkg>              - Remove conda file and update manifest"
    print "  get-publish-command <pkg> <channel>  - Get publish command"
    print "  publish-from-manifest <pkg> <channel> - Publish using manifest"
    print "  manifest-summary                     - Show summary of all packages"
    print "  manifest-cleanup                     - Remove entries for missing files"
    print ""
    print "Example usage:"
    print "  use .scripts/manifest_utils.nu *"
    print "  manifest-summary"
    print "  get-package-path pwgen"
    print "  find-conda-file pwgen linux-64"
    print "  conda-file-info pwgen"
    print "  publish-from-manifest pwgen pd --dry-run"
    print "  remove-conda-file old-package"
}

# Main command-line interface (for standalone usage)
export def main [
    package_name: string,                    # Name of the package to find
    platform: string = "linux-64",           # Target platform (default: linux-64)
    --output-dir: string = "./pkgs-out",     # Output directory (default: ./pkgs-out)
    --list-each                              # List all matching files instead of just the latest
    --quiet (-q)                             # Suppress stderr output
    --info                                   # Show file info instead of just path
    --exists                                 # Check if file exists (exit code 0/1)
] {
    if $exists {
        if (conda-file-exists $package_name $platform $output_dir) {
            exit 0
        } else {
            exit 1
        }
    }

    if $list_each {
        let files = list-each-conda-files $package_name $platform $output_dir
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
