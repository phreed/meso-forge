#!/usr/bin/env nu

use build_mod.nu get_current_platform
use build_mod.nu find_noarch_packages
use build_mod.nu find_platform_specific_packages

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
    build_noarch_packages --tgt-dir $tgt_dir
    --src-dir: string = "./pkgs",
    --tgt-dir: string = "./output",

    # Build platform-specific packages
    print $"🔧 Building platform-specific packages for ($current_platform)..."
    build_platform_specific_packages --platform $current_platform --src-dir $src_dir

    print "✅ All packages built successfully!"
}

# Build noarch packages
def build_noarch_packages [
    --src-dir: string = "./pkgs",
    --tgt-dir: string = "./output",
    --dry-run,                              # Show command without executing
    --verbose,                              # Enable verbose output
] {
    let noarch_packages = find_noarch_packages --src-dir $src_dir

    for package in $noarch_packages {
        print $"  Building noarch package: ($package)"
        let recipe_path = $"($package)/recipe.yaml"

        try {
            rattler-build build --recipe $recipe_path --output-dir $tgt_dir
        } catch {
            print $"❌ Failed to build ($package)"
            continue
        }

        print $"  ✅ Built ($package)"
    }
}

# Build platform-specific packages
def build_platform_specific_packages [
    --platform: string,
    --src-dir: string = "./pkgs",
    --tgt-dir: string = "./output",
    --dry-run,                              # Show command without executing
    --verbose,                              # Enable verbose output
  ] {
    let platform_packages = find_platform_specific_packages --src-dir $src_dir

    for package in $platform_packages {
        print $"  Building platform package: ($package) for ($platform)"
        let recipe_path = $"($package)/recipe.yaml"

        try {
            rattler-build build --recipe $recipe_path --target-platform $platform --output-dir $tgt_dir
        } catch {
            print $"❌ Failed to build ($package) for ($platform)"
            continue
        }

        print $"  ✅ Built ($package) for ($platform)"
    }
}
