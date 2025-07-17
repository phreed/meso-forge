#!/usr/bin/env nu

# Retract published packages from repositories
# Usage: nu package_retract.nu <package> --channel <channel> --versions <versions> [--method <pd|s3>] [--target-platform <platform>]

use manifest_utils.nu *
use std repeat

def main [
    package: string,                         # Package name to retract
    --channel: string,                       # Channel name (required)
    --versions: string,                      # Version range or specific versions (e.g., "1.0.0", "1.0.0-1.2.0", "1.0.0,1.1.0,1.2.0")
    --method: string = "pd",                 # Publishing method: "pd" for prefix.dev, "s3" for S3
    --target-platform: string = "linux-64", # Target platform
    --url: string = "",                      # Endpoint URL for S3 (overrides default URL)
    --manifest: string = "./pkgs-out/conda-manifest.json",  # Path to manifest file
    --dry-run,                              # Show commands without executing
    --verbose,                              # Enable verbose output
    --force                                 # Force retraction without confirmation
] {
    print $"🗑️  Retracting package: ($package) from channel: ($channel) via ($method)"
    print $"   Platform: ($target_platform)"
    print $"   Versions: ($versions)"
    print ""

    # Validate required parameters
    if ($channel | str trim | is-empty) {
        print -e "❌ Channel name is required. Use --channel <channel-name>"
        exit 1
    }

    if ($versions | str trim | is-empty) {
        print -e "❌ Versions are required. Use --versions <version-range>"
        exit 1
    }

    # Validate method
    if $method not-in ["pd", "s3"] {
        print -e $"❌ Invalid method: ($method). Use 'pd' or 's3'"
        exit 1
    }

    # Parse version specifications
    let version_list = parse-versions $versions

    if ($version_list | length) == 0 {
        print -e $"❌ No valid versions found in: ($versions)"
        exit 1
    }

    if $verbose {
        print $"📋 Parsed versions: (($version_list | str join ', '))"
        print ""
    }

    # Check if manifest exists for reference (optional)
    let manifest_exists = ($manifest | path exists)
    if $manifest_exists and $verbose {
        print $"📄 Using manifest file: ($manifest)"
    }

    # Confirm retraction unless --force is used
    if not $force {
        print $"⚠️  WARNING: This will permanently delete the following packages:"
        print $"   Package: ($package)"
        print $"   Channel: ($channel)"
        print $"   Platform: ($target_platform)"
        print $"   Versions: (($version_list | str join ', '))"
        print ""

        let confirmation = input "Are you sure you want to continue? (yes/no): "
        if $confirmation != "yes" {
            print "❌ Retraction cancelled."
            exit 0
        }
        print ""
    }

    # Retract packages based on method
    match $method {
        "pd" => { retract-from-prefix-dev $package $channel $version_list $target_platform $dry_run $verbose }
        "s3" => { retract-from-s3 $package $channel $version_list $target_platform $url $dry_run $verbose }
        _ => {
            print -e $"❌ Unsupported method: ($method)"
            exit 1
        }
    }
}

# Parse version specifications into a list
def parse-versions [versions: string] {
    let trimmed = ($versions | str trim)

    if ($trimmed | str contains "-") and not ($trimmed | str contains ",") {
        # Range format: "1.0.0-1.2.0"
        let parts = ($trimmed | split row "-")
        if ($parts | length) == 2 {
            expand-version-range ($parts | get 0) ($parts | get 1)
        } else {
            [$trimmed]
        }
    } else if ($trimmed | str contains ",") {
        # List format: "1.0.0,1.1.0,1.2.0"
        $trimmed | split row "," | each { |v| $v | str trim } | where { |v| not ($v | is-empty) }
    } else {
        # Single version: "1.0.0"
        [$trimmed]
    }
}

# Expand version range (simplified - assumes semantic versioning)
def expand-version-range [start: string, end: string] {
    # For now, return both start and end versions
    # In a real implementation, this could query the repository to find all versions in range
    [$start, $end]
}

# Retract packages from prefix.dev
def retract-from-prefix-dev [
    package: string,
    channel: string,
    versions: list<string>,
    platform: string,
    dry_run: bool,
    verbose: bool
] {
    print $"🌐 Retracting from prefix.dev channel: ($channel)"

    # Get API token from environment or auth file
    let api_token = get-prefix-api-token $channel $verbose
    if ($api_token | is-empty) {
        print -e "❌ No API token found for prefix.dev"
        print -e "   Either set PREFIX_API_TOKEN environment variable:"
        print -e "   export PREFIX_API_TOKEN=pfx_your_token_here"
        print -e "   Or configure authentication in RATTLER_AUTH_FILE"
        return
    }

    # Validate API token format
    if not ($api_token | str starts-with "pfx_") {
        print -e "⚠️  WARNING: API token should start with 'pfx_'"
        print -e "   Make sure you're using a valid prefix.dev API token"
    }

    for version in $versions {
        let package_file = $"($package)-($version)-($platform).conda"
        let api_url = $"https://prefix.dev/api/v1/delete/($channel)/($platform)/($package_file)"

        if $verbose or $dry_run {
            print $"API URL: ($api_url)"
            print $"Command: http delete ($api_url) --headers [Authorization \"Bearer [REDACTED]\"]"
        }

        if not $dry_run {
            print $"🗑️  Deleting: ($package_file)"

            let result = try {
                http delete $api_url --headers [Authorization $"Bearer ($api_token)"]
                {status: 200, success: true}
            } catch { |e|
                if ($e.msg | str contains "404") {
                    {status: 404, success: false, error: "Not found"}
                } else if ($e.msg | str contains "401") {
                    {status: 401, success: false, error: "Authentication failed"}
                } else if ($e.msg | str contains "403") {
                    {status: 403, success: false, error: "Permission denied"}
                } else {
                    {status: 500, success: false, error: $e.msg}
                }
            }

            if $result.success {
                print $"✅ Successfully deleted: ($package_file)"
            } else {
                match $result.status {
                    404 => {
                        print -e $"❌ Package not found: ($package_file)"
                        if $verbose {
                            print -e $"   The package may have already been deleted or never existed"
                        }
                    }
                    401 => {
                        print -e $"❌ Authentication failed for: ($package_file)"
                        print -e $"   Check your PREFIX_API_TOKEN"
                    }
                    403 => {
                        print -e $"❌ Permission denied for: ($package_file)"
                        print -e $"   You may not have delete permissions for this channel"
                    }
                    _ => {
                        print -e $"❌ Failed to delete: ($package_file) (HTTP $result.status)"
                        if $verbose and "error" in $result {
                            print -e $"   Error: ($result.error)"
                        }
                    }
                }
            }
        }
    }
}

# Retract packages from S3
def retract-from-s3 [
    package: string,
    channel: string,
    versions: list<string>,
    platform: string,
    url: string,
    dry_run: bool,
    verbose: bool
] {
    print $"☁️  Retracting from S3 channel: ($channel)"

    let s3_url = if ($url | is-empty) {
        $env.CONDA_S3_URL? | default "s3://conda-packages"
    } else {
        $url
    }

    for version in $versions {
        let package_file = $"($package)-($version)-($platform).conda"
        let s3_path = $"($s3_url)/($channel)/($platform)/($package_file)"

        let cmd = ["aws", "s3", "rm", $s3_path]

        if $verbose or $dry_run {
            print $"Command: (($cmd | str join ' '))"
        }

        if not $dry_run {
            print $"🗑️  Deleting: ($s3_path)"

            let result = (^aws ...$cmd.1.. | complete)

            if $result.exit_code == 0 {
                print $"✅ Successfully deleted: ($package_file)"
            } else {
                print -e $"❌ Failed to delete: ($package_file)"
                if $verbose {
                    print -e $"   Error: ($result.stderr)"
                }
            }
        }
    }

    # Update repository metadata if not dry-run
    if not $dry_run {
        update-s3-metadata $channel $platform $s3_url $verbose
    }
}

# Update S3 repository metadata after package deletion
def update-s3-metadata [
    channel: string,
    platform: string,
    s3_url: string,
    verbose: bool
] {
    print "🔄 Updating repository metadata..."

    let repodata_path = $"($s3_url)/($channel)/($platform)/repodata.json"
    let temp_dir = $nu.temp-path | path join $"retract-(date now | format date '%Y%m%d_%H%M%S')_(random int)"
    mkdir $temp_dir
    let local_repodata = $"($temp_dir)/repodata.json"

    # Download current repodata
    let download_cmd = ["aws", "s3", "cp", $repodata_path, $local_repodata]

    if $verbose {
        print $"Downloading metadata: (($download_cmd | str join ' '))"
    }

    let download_result = (^aws ...$download_cmd.1.. | complete)

    if $download_result.exit_code == 0 {
        # Here you would typically update the repodata.json to remove references
        # to the deleted packages and then upload it back
        print "⚠️  Note: Automatic metadata update not implemented."
        print "   You may need to manually update the repository metadata."
    } else {
        if $verbose {
            print -e $"Failed to download metadata: ($download_result.stderr)"
        }
    }

    # Clean up temp directory
    rm -r $temp_dir
}

# Helper function to run external commands and capture results
def run-external [command: string, ...args] {
    try {
        let output = ^$command ...$args | complete
        {
            exit_code: $output.exit_code,
            stdout: $output.stdout,
            stderr: $output.stderr
        }
    } catch { |e|
        {
            exit_code: 1,
            stdout: "",
            stderr: $"Command failed: ($e.msg)"
        }
    }
}

# Get prefix.dev API token from environment or auth file
def get-prefix-api-token [channel: string, verbose: bool] {
    # First try PREFIX_API_TOKEN environment variable
    let env_token = $env.PREFIX_API_TOKEN? | default ""
    if not ($env_token | is-empty) {
        if $verbose {
            print "🔑 Using API token from PREFIX_API_TOKEN environment variable"
        }
        return $env_token
    }

    # Try to get token from RATTLER_AUTH_FILE
    let auth_file = $env.RATTLER_AUTH_FILE? | default ""
    if not ($auth_file | is-empty) and ($auth_file | path exists) {
        if $verbose {
            print $"🔑 Checking RATTLER_AUTH_FILE for authentication: ($auth_file)"
        }

        let token = get-token-from-auth-file $auth_file $channel $verbose
        if not ($token | is-empty) {
            return $token
        }
    }

    # Try default auth file locations
    let default_auth_files = [
        ($env.HOME | path join ".rattler" "auth.json"),
        ($env.HOME | path join ".conda" "auth.json"),
        ($env.XDG_CONFIG_HOME? | default ($env.HOME | path join ".config") | path join "rattler" "auth.json")
    ]

    for auth_file in $default_auth_files {
        if ($auth_file | path exists) {
            if $verbose {
                print $"🔑 Checking default auth file: ($auth_file)"
            }

            let token = get-token-from-auth-file $auth_file $channel $verbose
            if not ($token | is-empty) {
                return $token
            }
        }
    }

    return ""
}

# Extract token from auth file for a specific channel
def get-token-from-auth-file [auth_file: string, channel: string, verbose: bool] {
    try {
        let auth_data = open $auth_file --raw | from json

        # Handle different auth file formats
        let token = if ($auth_data | describe) == "record" {
            # Try different possible structures
            let prefix_dev_urls = [
                "https://prefix.dev",
                $"https://prefix.dev/api/v1/upload/($channel)",
                "prefix.dev"
            ]

            mut found_token = ""
            for url in $prefix_dev_urls {
                if $url in $auth_data {
                    let auth_entry = $auth_data | get $url
                    if ($auth_entry | describe) == "record" {
                        if "BearerToken" in $auth_entry {
                            $found_token = ($auth_entry | get BearerToken)
                            break
                        } else if "bearer_token" in $auth_entry {
                            $found_token = ($auth_entry | get bearer_token)
                            break
                        } else if "token" in $auth_entry {
                            $found_token = ($auth_entry | get token)
                            break
                        }
                    } else if ($auth_entry | describe) == "string" {
                        $found_token = $auth_entry
                        break
                    }
                }
            }
            $found_token
        } else {
            ""
        }

        if not ($token | is-empty) {
            if $verbose {
                print $"✅ Found authentication token in ($auth_file)"
            }
            return $token
        }

        return ""
    } catch { |e|
        if $verbose {
            print $"⚠️  Could not read auth file ($auth_file): ($e.msg)"
        }
        return ""
    }
}

# Helper function to run external commands with HTTP status code parsing
# Note: This function is kept for compatibility with other external commands
def run-external-with-status [command: string, ...args] {
    try {
        let output = ^$command ...$args | complete
        let full_output = $output.stdout

        # Extract HTTP status code from the end of the output (added by curl -w %{http_code})
        let status_code = if ($full_output | str length) >= 3 {
            $full_output | str substring (-3..) | into int
        } else {
            0
        }

        # Remove status code from stdout
        let clean_stdout = if ($full_output | str length) >= 3 {
            $full_output | str substring 0..(-4)
        } else {
            $full_output
        }

        {
            exit_code: $output.exit_code,
            status_code: $status_code,
            stdout: $clean_stdout,
            stderr: $output.stderr
        }
    } catch { |e|
        {
            exit_code: 1,
            status_code: 0,
            stdout: "",
            stderr: $"Command failed: ($e.msg)"
        }
    }
}
