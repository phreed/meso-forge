#!/usr/bin/env nu

use build_mod.nu get_current_platform
use build_mod.nu find_platform_specific_packages

# Build platform-specific packages for current or specified platform
def main [
    --src-dir: string = "./pkgs",
    --tgt-dir: string = "./output",
    --platform (-p): string = ""  # Target platform (default: current)
    --all-platforms (-a)          # Build for all supported platforms
] {
    print "🔧 Building platform-specific packages..."

    let target_platforms = if $all_platforms {
        ["linux-64", "linux-aarch64"]
    } else if ($platform | is-empty) {
        [get_current_platform]
    } else {
        [$platform]
    }

    let platform_packages = find_platform_specific_packages --src-dir $src_dir

    if ($platform_packages | length) == 0 {
        print "ℹ️  No platform-specific packages found"
        return
    }

    print $"Found ($platform_packages | length) platform-specific packages"
    print $"Target platforms: ($target_platforms | str join ', ')"

    for platform in $target_platforms {
        print $"\n🏗️  Building for platform: ($platform)"

        for package in $platform_packages {
            print $"  Building: ($package)"
            let recipe_path = $"($package)/recipe.yaml"

            try {
                rattler-build build --recipe $recipe_path --target-platform $platform --output-dir output/
                print $"  ✅ Successfully built ($package) for ($platform)"
            } catch {
                print $"  ❌ Failed to build ($package) for ($platform)"
            }
        }
    }

    print "🔧 Platform-specific package build complete!"
}
