#!/usr/bin/env nu

use build_mod.nu [
    get_current_platform
    find_noarch_packages
    build_with_rattler]

# Build only noarch packages
def main [
--src-dir: string = "./pkgs",
--tgt-dir: string = "./output",
] {
    print "📦 Building noarch packages only..."

    let noarch_packages = find_noarch_packages --src-dir $src_dir

    if ($noarch_packages | length) == 0 {
        print "ℹ️  No noarch packages found"
        return
    }

    print $"Found ($noarch_packages | length) noarch packages"

    for package in $noarch_packages {
        print $"Building: ($package)"
        let recipe_path = $"($package)/recipe.yaml"

        try {
            build_with_rattler --recipe $recipe_path --output-dir $tgt_dir
            print $"✅ Successfully built ($package)"
        } catch {
            print $"❌ Failed to build ($package)"
        }
    }

    print "📦 Noarch package build complete!"
}
