#!/usr/bin/env nu

# Example usage script for package_retract.nu
# This script demonstrates safe usage patterns for package retraction

print "🧪 Package Retraction Example Script"
print "======================================"
print ""

# Check if the retract script exists
if not ("./package_retract.nu" | path exists) and not ("./.scripts/package_retract.nu" | path exists) {
    print -e "❌ package_retract.nu script not found!"
    print -e "   Make sure you're running this from the meso-forge directory"
    exit 1
}

# Determine script path
let script_path = if ("./package_retract.nu" | path exists) {
    "./package_retract.nu"
} else {
    "./.scripts/package_retract.nu"
}

print $"📄 Using script: ($script_path)"
print ""

# Example 1: Check environment setup
print "🔧 Example 1: Authentication Setup Check"
print "----------------------------------------"

let api_token = $env.PREFIX_API_TOKEN? | default ""
let auth_file = $env.RATTLER_AUTH_FILE? | default ""

print "Authentication Methods (in order of precedence):"
print ""

print "1. PREFIX_API_TOKEN environment variable:"
if ($api_token | is-empty) {
    print "   ❌ Not set"
    print "   To use: export PREFIX_API_TOKEN=pfx_your_actual_token_here"
} else {
    if ($api_token | str starts-with "pfx_") {
        print "   ✅ Set with correct format"
    } else {
        print "   ⚠️  Set but should start with 'pfx_'"
    }
}
print ""

print "2. RATTLER_AUTH_FILE:"
if ($auth_file | is-empty) {
    print "   ❌ Not set"
    print "   To use: export RATTLER_AUTH_FILE=~/.rattler/auth.json"
} else {
    if ($auth_file | path exists) {
        print $"   ✅ Set and file exists: ($auth_file)"
    } else {
        print $"   ⚠️  Set but file doesn't exist: ($auth_file)"
    }
}
print ""

print "3. Default auth file locations:"
let default_locations = [
    ($env.HOME | path join ".rattler" "auth.json"),
    ($env.HOME | path join ".conda" "auth.json"),
    ($env.HOME | path join ".config" "rattler" "auth.json")
]

for location in $default_locations {
    if ($location | path exists) {
        print $"   ✅ Found: ($location)"
    } else {
        print $"   ❌ Not found: ($location)"
    }
}
print ""

# Example 2: Dry run demonstration
print "🔍 Example 2: Dry Run (Safe Testing)"
print "------------------------------------"
print "Always use --dry-run first to see what would happen:"
print ""
print $"Command: nu ($script_path) example-package --channel test-channel --versions \"1.0.0\" --dry-run --verbose"
print ""
print "This would show you exactly what API calls would be made without actually deleting anything."
print ""

# Example 3: Different version formats
print "📋 Example 3: Version Format Examples"
print "-------------------------------------"
print "Single version:"
print $"  nu ($script_path) mypackage --channel mychannel --versions \"1.0.0\""
print ""
print "Multiple specific versions:"
print $"  nu ($script_path) mypackage --channel mychannel --versions \"1.0.0,1.0.1,1.0.2\""
print ""
print "Version range (simplified):"
print $"  nu ($script_path) mypackage --channel mychannel --versions \"1.0.0-1.2.0\""
print ""

# Example 4: Different repository types
print "🌐 Example 4: Repository Types"
print "------------------------------"
print "prefix.dev (default):"
print $"  nu ($script_path) mypackage --channel mychannel --versions \"1.0.0\" --method pd"
print ""
print "S3 repository:"
print $"  nu ($script_path) mypackage --channel mychannel --versions \"1.0.0\" --method s3"
print ""
print "S3 with custom URL:"
print $"  nu ($script_path) mypackage --channel mychannel --versions \"1.0.0\" --method s3 --url s3://my-conda-bucket"
print ""

# Example 5: Platform-specific
print "🖥️  Example 5: Platform-Specific Retraction"
print "--------------------------------------------"
print "Linux (default):"
print $"  nu ($script_path) mypackage --channel mychannel --versions \"1.0.0\""
print ""
print "macOS:"
print $"  nu ($script_path) mypackage --channel mychannel --versions \"1.0.0\" --target-platform osx-64"
print ""
print "Windows:"
print $"  nu ($script_path) mypackage --channel mychannel --versions \"1.0.0\" --target-platform win-64"
print ""

# Example 6: Safety features
print "🛡️  Example 6: Safety Features"
print "------------------------------"
print "Interactive confirmation (default):"
print $"  nu ($script_path) mypackage --channel mychannel --versions \"1.0.0\""
print "  (Will prompt for confirmation)"
print ""
print "Force mode (no confirmation):"
print $"  nu ($script_path) mypackage --channel mychannel --versions \"1.0.0\" --force"
print "  (Use with caution!)"
print ""
print "Verbose output for debugging:"
print $"  nu ($script_path) mypackage --channel mychannel --versions \"1.0.0\" --verbose"
print ""

# Example 7: Real-world scenario
print "🌍 Example 7: Real-World Scenario"
print "---------------------------------"
print "Imagine you published a package with a critical bug and need to retract it:"
print ""
print "Step 1 - Dry run to verify:"
print $"  nu ($script_path) my-buggy-package --channel my-channel --versions \"2.1.0\" --dry-run --verbose"
print ""
print "Step 2 - Review the output, then execute:"
print $"  nu ($script_path) my-buggy-package --channel my-channel --versions \"2.1.0\""
print ""
print "Step 3 - If you need to retract multiple versions:"
print $"  nu ($script_path) my-buggy-package --channel my-channel --versions \"2.1.0,2.1.1,2.1.2\""
print ""

# Example 8: Error scenarios
print "❌ Example 8: Common Error Scenarios"
print "------------------------------------"
print "Missing API token:"
print "  Error: PREFIX_API_TOKEN environment variable is required"
print "  Solution: export PREFIX_API_TOKEN=pfx_your_token"
print ""
print "Package not found:"
print "  Error: Package not found (HTTP 404)"
print "  Reason: Package may already be deleted or never existed"
print ""
print "Permission denied:"
print "  Error: Permission denied (HTTP 403)"
print "  Reason: Your API token doesn't have delete permissions for this channel"
print ""

# Conclusion
print "✅ Example Script Complete"
print "=========================="
print ""
print "Key safety reminders:"
print "• Always use --dry-run first"
print "• Double-check package names, versions, and channels"
print "• Package deletion is permanent and irreversible"
print "• Use --verbose for debugging"
print "• Keep your API tokens secure"
print ""
print "For more information, see .doc/package-retract.adoc"
