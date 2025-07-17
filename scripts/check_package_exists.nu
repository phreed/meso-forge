#!/usr/bin/env nu

# Check if a conda package exists in various repositories
# Usage: nu check_package_exists.nu <package> [--version <version>] [--channel <channel>] [--platform <platform>]

def main [
    package: string,                         # Package name to check
    --version: string = "",                 # Specific version to check (optional)
    --channel: string = "conda-forge",      # Channel to check
    --platform: string = "linux-64",        # Platform to check
    --check_all,                            # Check all configured channels
    --check_local,                          # Also check local builds
    --check_prefix,                         # Check prefix.dev repository
    --check_s3,                             # Check S3 repository
    --json,                                 # Output results as JSON
] {
    mut results = []

    # Check conda-forge or specified channel
    if not $check_prefix and not $check_s3 {
        let conda_result = (check-conda-channel $package $version $channel $platform)
        $results = ($results | append $conda_result)
    }

    # Check local builds if requested
    if $check_local {
        let local_result = (check-local-builds $package $version $platform)
        $results = ($results | append $local_result)
    }

    # Check prefix.dev if requested
    if $check_prefix {
        let prefix_result = (check-prefix-dev $package $version $platform)
        $results = ($results | append $prefix_result)
    }

    # Check S3 repository if requested
    if $check_s3 {
        let s3_result = (check-s3-repo $package $version $platform)
        $results = ($results | append $s3_result)
    }

    # Check all channels if requested
    if $check_all {
        let channels = ["conda-forge", "https://prefix.dev/meso-forge", "bioconda", "defaults"]
        for ch in $channels {
            if $ch != $channel {  # Don't check the same channel twice
                let ch_result = (check-conda-channel $package $version $ch $platform)
                $results = ($results | append $ch_result)
            }
        }
    }

    # Output results
    if $json {
        $results | to json
    } else {
        (print-results $results $package $version)
    }

    # Return exit code based on whether package was found
    let found_count = ($results | where found == true | length)
    let found = $found_count > 0
    if $found { exit 0 } else { exit 1 }
}

# Check if package exists in a conda channel
export def "check-conda-channel" [
    package: string,
    version: string,
    channel: string,
    platform: string
] {
    print $"Checking ($channel) for ($package)..."

    let result = if ($version | is-empty) {
        (^micromamba search -c $channel --platform $platform $package | complete)
    } else {
        (^micromamba search -c $channel --platform $platform $"($package)==($version)" | complete)
    }

    if $result.exit_code != 0 {
        return {
            location: $channel,
            found: false,
            error: "Failed to search channel",
            packages: []
        }
    }

    # Parse micromamba search output
    let lines = $result.stdout | lines

    # Skip header lines and find data rows
    # Format: " numpy 2.3.0   py311h519dc76_0                 (+  3 builds) conda-forge linux-64"
    let data_lines = $lines | skip while { |line|
        not ($line | str trim | str starts-with $package)
    }

    let package_lines = $data_lines | where { |line|
        let trimmed = $line | str trim
        let starts_with_pkg = ($trimmed | str starts-with $package)
        let parts = ($trimmed | split row -r '\s+')
        let has_enough_parts = (($parts | length) >= 3)
        ($starts_with_pkg and $has_enough_parts)
    }

    if ($package_lines | length) == 0 {
        return {
            location: $channel,
            found: false,
            count: 0,
            packages: []
        }
    }

    # Parse package information from micromamba output
    let packages = $package_lines | each { |line|
        let parts = $line | str trim | split row -r '\s+'

        # Typical format: [name, version, build, "(+", "N", "builds)", channel, platform]
        if ($parts | length) >= 3 {
            {
                version: ($parts | get 1),
                build_number: ($parts | get 2),
                platform: $platform
            }
        } else {
            null
        }
    } | where { |pkg| $pkg != null }

    let found = ($packages | length) > 0
    return {
        location: $channel,
        found: $found,
        count: ($packages | length),
        packages: ($packages | first 5)
    }
}

# Check local builds
export def "check-local-builds" [
    package: string,
    version: string,
    platform: string
] {
    print $"Checking local builds for ($package)..."

    let output_dir = "./pkgs-out"
    let platform_dir = $output_dir | path join $platform

    if not ($platform_dir | path exists) {
        return {
            location: "local",
            found: false,
            packages: []
        }
    }

    # Look for package files
    let pattern = if ($version | is-empty) {
        $"($package)-*.conda"
    } else {
        $"($package)-($version)-*.conda"
    }

    let files = try {
        ls ($platform_dir | path join $pattern) | select name size modified
    } catch {
        []
    }

    let found = ($files | length) > 0
    return {
        location: "local",
        found: $found,
        count: ($files | length),
        packages: ($files | each { |f|
            let parts = ($f.name | path basename | str replace ".conda" "" | split row "-")
            {
                version: ($parts | get 1),
                build: ($parts | skip 2 | str join "-"),
                file: ($f.name | path basename),
                size: $f.size,
                modified: $f.modified
            }
        })
    }
}

# Check prefix.dev repository
export def "check-prefix-dev" [
    package: string,
    version: string,
    platform: string
] {
    print $"Checking prefix.dev for ($package)..."

    # Use micromamba to check prefix.dev
    let result = if ($version | is-empty) {
        (^micromamba search -c "https://prefix.dev/meso-forge" $package --platform $platform | complete)
    } else {
        (^micromamba search -c "https://prefix.dev/meso-forge" $"($package)==($version)" --platform $platform | complete)
    }

    if $result.exit_code != 0 {
        return {
            location: "prefix.dev/meso-forge",
            found: false,
            error: "Could not search prefix.dev (may need authentication)",
            packages: []
        }
    }

    # Parse micromamba search output
    let lines = $result.stdout | lines

    # Skip header lines and find data rows
    let data_lines = $lines | skip while { |line|
        not ($line | str trim | str starts-with $package)
    }

    let package_lines = $data_lines | where { |line|
        let trimmed = $line | str trim
        let starts_with_pkg = ($trimmed | str starts-with $package)
        let parts = ($trimmed | split row -r '\s+')
        let has_enough_parts = (($parts | length) >= 3)
        ($starts_with_pkg and $has_enough_parts)
    }

    if ($package_lines | length) == 0 {
        return {
            location: "prefix.dev/meso-forge",
            found: false,
            count: 0,
            packages: []
        }
    }

    # Parse package information
    let packages = $package_lines | each { |line|
        let parts = $line | str trim | split row -r '\s+'

        if ($parts | length) >= 3 {
            {
                version: ($parts | get 1),
                build: ($parts | get 2)
            }
        } else {
            null
        }
    } | where { |pkg| $pkg != null }

    let found = ($packages | length) > 0
    return {
        location: "prefix.dev/meso-forge",
        found: $found,
        count: ($packages | length),
        packages: ($packages | first 5)
    }
}

# Check S3 repository
export def "check-s3-repo" [
    package: string,
    version: string,
    platform: string
] {
    print $"Checking S3 repository for ($package)..."

    # Check if we have S3 credentials
    let has_aws_key = (not ($env.AWS_ACCESS_KEY_ID? | is-empty))
    let has_aws_secret = (not ($env.AWS_SECRET_ACCESS_KEY? | is-empty))

    if (not $has_aws_key) or (not $has_aws_secret) {
        return {
            location: "s3://pixi/meso-forge",
            found: false,
            error: "S3 credentials not configured",
            packages: []
        }
    }

    # Use micromamba with S3 channel
    let s3_channel = "https://minio.isis.vanderbilt.edu/pixi/meso-forge"
    let result = if ($version | is-empty) {
        (^micromamba search -c $s3_channel --platform $platform $package | complete)
    } else {
        (^micromamba search -c $s3_channel --platform $platform $"($package)==($version)" | complete)
    }

    if $result.exit_code != 0 {
        return {
            location: "s3://pixi/meso-forge",
            found: false,
            error: "Failed to search S3 repository",
            packages: []
        }
    }

    # Parse micromamba search output
    let lines = $result.stdout | lines

    # Skip header lines and find data rows
    let data_lines = $lines | skip while { |line|
        not ($line | str trim | str starts-with $package)
    }

    let package_lines = $data_lines | where { |line|
        let trimmed = $line | str trim
        let starts_with_pkg = ($trimmed | str starts-with $package)
        let parts = ($trimmed | split row -r '\s+')
        let has_enough_parts = (($parts | length) >= 3)
        ($starts_with_pkg and $has_enough_parts)
    }

    if ($package_lines | length) == 0 {
        return {
            location: "s3://pixi/meso-forge",
            found: false,
            count: 0,
            packages: []
        }
    }

    # Parse package information
    let packages = $package_lines | each { |line|
        let parts = $line | str trim | split row -r '\s+'

        if ($parts | length) >= 3 {
            {
                version: ($parts | get 1),
                build_number: ($parts | get 2),
                platform: $platform
            }
        } else {
            null
        }
    } | where { |pkg| $pkg != null }

    let found = ($packages | length) > 0
    return {
        location: "s3://pixi/meso-forge",
        found: $found,
        count: ($packages | length),
        packages: ($packages | first 5)
    }
}

# Print formatted results
def "print-results" [
    results: table,
    package: string,
    version: string
] {
    print ""
    print $"=== Package Search Results for '($package)' ==="
    if not ($version | is-empty) {
        print $"    Version: ($version)"
    }
    print ""

    for result in $results {
        print $"📍 ($result.location):"

        if $result.found {
            print $"   ✅ Found ($result.count) packages"

            if ($result.packages | length) > 0 {
                print "   Available versions:"
                for pkg in $result.packages {
                    if "file" in ($pkg | columns) {
                        print $"     - ($pkg.version) [($pkg.build)] - ($pkg.file)"
                    } else if "build_number" in ($pkg | columns) {
                        print $"     - ($pkg.version) \(build ($pkg.build_number)\)"
                    } else {
                        print $"     - ($pkg.version) [($pkg.build)]"
                    }
                }

                if $result.count > ($result.packages | length) {
                    print $"     ... and (($result.count) - ($result.packages | length)) more"
                }
            }
        } else {
            if "error" in ($result | columns) {
                print $"   ❌ Not found \(($result.error)\)"
            } else {
                print "   ❌ Not found"
            }
        }
        print ""
    }

    # Summary
    let found_locations = $results | where found == true | get location
    if ($found_locations | length) > 0 {
        print $"✅ Package found in: ($found_locations | str join ', ')"
    } else {
        print "❌ Package not found in any checked repository"
    }
}

# Helper function to check before building
export def "check-before-build" [
    package: string,
    --version: string = "",
    --platform: string = "linux-64"
] {
    print $"🔍 Checking if ($package) already exists before building..."

    # Check all common locations - work with native data structures
    mut results = []

    # Check conda-forge
    let conda_result = (check-conda-channel $package $version "conda-forge" $platform)
    $results = ($results | append $conda_result)

    # Check local builds
    let local_result = (check-local-builds $package $version $platform)
    $results = ($results | append $local_result)

    # Check prefix.dev
    let prefix_result = (check-prefix-dev $package $version $platform)
    $results = ($results | append $prefix_result)

    # Check S3
    let s3_result = (check-s3-repo $package $version $platform)
    $results = ($results | append $s3_result)

    let remote_found_count = ($results | where found == true and location != "local" | length)
    let remote_found = $remote_found_count > 0

    if $remote_found {
        print ""
        print "⚠️  Package already exists in remote repository!"
        print "   Use --skip-existing flag with rattler-build to skip building"
        print "   Or use --force to rebuild anyway"
        return true
    } else {
        print "✅ Package not found in remote repositories - safe to build"
        return false
    }
}

# Integration with build script
export def "should-skip-build" [
    package: string,
    --platform: string = "linux-64"
] {
    # Quick check for conda-forge and custom channels - work with native data structures
    let conda_result = (check-conda-channel $package "" "conda-forge" $platform)
    let meso_result = (check-conda-channel $package "" "https://prefix.dev/meso-forge" $platform)
    let prefix_result = (check-prefix-dev $package "" $platform)

    return ($conda_result.found or $meso_result.found or $prefix_result.found)
}
