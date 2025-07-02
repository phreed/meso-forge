#!/usr/bin/env nu

use build_mod.nu [
    get_current_platform
    build_platform_packages]

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
        [(get_current_platform)]
    } else {
        [$platform]
    }

    print $"Target platforms: ($target_platforms | str join ', ')"

    for platform in $target_platforms {
        print $"\n🏗️  Building for platform: ($platform)"
        build_platform_packages --platform $platform --src-dir $src_dir --tgt-dir $tgt_dir
    }

    print "🔧 Platform-specific package build complete!"
}
