#!/usr/bin/env nu

use build_mod.nu [
    get_current_platform
    build_noarch_packages
    build_platform_packages]

# Build all packages for the current platform
def main [
    --src-dir: string = "./pkgs",
    --tgt-dir: string = "./output",
    --dry-run,                              # Show command without executing
    --verbose,                              # Enable verbose output
    --force                                 # Force upload, overwriting existing packages
] {
    print "🚀 Building all packages..."

    let packages = ls $src_dir | where type == dir | get name
    let current_platform = get_current_platform

    print $"Current platform: ($current_platform)"

    # Build noarch packages first (only once)
    print "📦 Building noarch packages..."
    build_noarch_packages --src-dir $src_dir --tgt-dir $tgt_dir

    # Build platform-specific packages
    print $"🔧 Building platform specific packages for ($current_platform)..."
    build_platform_packages --platform $current_platform --src-dir $src_dir --tgt-dir $tgt_dir

    print "✅ All packages built successfully!"
}
