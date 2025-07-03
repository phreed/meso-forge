#!/usr/bin/env nu

use build_mod.nu [build_with_rattler build_with_rattler_dry_run resolve_recipe]

# Build a package for the current platform
def main [
    --recipe: string,
    --tgt-dir: string = "./output",
    --dry-run,                              # Show command without executing
    --verbose,                              # Enable verbose output
    --force                                 # Force upload, overwriting existing packages
] {
    let recipe_obj = resolve_recipe --recipe $recipe
    if ($recipe_obj == nothing) {
        print "❌ Package recipe is missing or defective"
        return
    }
    let pkg_name = $recipe_obj.package?.name? | default "unknown"
    print $"🚀 Building a package ($pkg_name)..."
    if ($dry_run) {
        build_with_rattler_dry_run $pkg_name --recipe $recipe --output-dir $tgt_dir
    } else {
        build_with_rattler $pkg_name --recipe $recipe --output-dir $tgt_dir
    }
}
