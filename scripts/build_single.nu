#!/usr/bin/env nu

use build_mod.nu [build_with_rattler resolve_recipe]

# Build a package for the current platform
def main [
    --recipe: string,
    --tgt-dir: string = "./output",
    --dry-run,                              # Show command without executing
    --verbose,                              # Enable verbose output
    --force                                 # Force upload, overwriting existing packages
] {
    print "🚀 Building a package..."
    build_with_rattler --recipe $recipe --output-dir $tgt_dir
}
