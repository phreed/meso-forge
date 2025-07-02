#!/usr/bin/env nu

use build_mod.nu [
    build_noarch_packages]

# Build only noarch packages
def main [
--src-dir: string = "./pkgs",
--tgt-dir: string = "./output",
] {
    print "📦 Building noarch packages only..."

    build_noarch_packages --src-dir $src_dir --tgt-dir $tgt_dir

    print "📦 Noarch package build complete!"
}
