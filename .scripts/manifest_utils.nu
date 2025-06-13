#!/usr/bin/env nu

# Utilities for working with the conda build manifest

# Default manifest path
const DEFAULT_MANIFEST = "./pkgs-out/conda-manifest.json"

# Read the manifest file
export def read-manifest [
    --manifest: string = $DEFAULT_MANIFEST  # Path to manifest file
] {
    if not ($manifest | path exists) {
        print -e $"Manifest file not found: ($manifest)"
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
    --dry-run                               # Just print the command, don't execute
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
    --dry-run                               # Just show what would be removed
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
    print "  read-manifest              - Read the manifest file"
    print "  get-package-info <pkg>     - Get info for a specific package"
    print "  get-package-path <pkg>     - Get conda file path for a package"
    print "  list-packages              - List all packages"
    print "  get-built-packages         - List only built packages"
    print "  get-skipped-packages       - List only skipped packages"
    print "  package-exists <pkg>       - Check if package is in manifest"
    print "  get-publish-command <pkg> <channel> - Get publish command"
    print "  publish-from-manifest <pkg> <channel> - Publish using manifest"
    print "  manifest-summary           - Show summary of all packages"
    print "  manifest-cleanup           - Remove entries for missing files"
    print ""
    print "Example usage:"
    print "  use .scripts/manifest_utils.nu *"
    print "  manifest-summary"
    print "  get-package-path pwgen"
    print "  publish-from-manifest pwgen pd --dry-run"
}
