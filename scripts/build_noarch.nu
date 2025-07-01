#!/usr/bin/env nu

use build_mod.nu get_current_platform
use build_mod.nu find_noarch_packages

# Build only noarch packages
def main [
--in-dir: string = "./pkgs",
--out-dir: string = "./output",
] {
    print "📦 Building noarch packages only..."

    let noarch_packages = find_noarch_packages --in-dir $in_dir

    if ($noarch_packages | length) == 0 {
        print "ℹ️  No noarch packages found"
        return
    }

    print $"Found ($noarch_packages | length) noarch packages"

    for package in $noarch_packages {
        print $"Building: ($package)"
        let recipe_path = $"($package)/recipe.yaml"

        try {
            rattler-build build --recipe $recipe_path --output-dir $out_dir
            print $"✅ Successfully built ($package)"
        } catch {
            print $"❌ Failed to build ($package)"
        }
    }

    print "📦 Noarch package build complete!"
}
