
# Get current platform
export def get_current_platform [] {
    let os_info = uname
    match [$os_info.kernel-name, $os_info.machine] {
        ["Linux", "x86_64"] => "linux-64",
        ["Linux", "aarch64"] => "linux-aarch64",
        ["Darwin", "x86_64"] => "osx-64",
        ["Darwin", "aarch64"] => "osx-arm64",
        ["Windows", "x86_64"] => "win-64",
        _ => (error make { msg: $"Unsupported platform: ($os_info.kernel-name)-($os_info.machine)" })
    }
}

# Find packages marked as noarch
export def find_noarch_packages [
    --src-dir: string = "./pkgs",
    --verbose,                              # Enable verbose output
] {
    ls $src_dir
    | where type == dir
    | get name
    | where {|pkg|
        if not ($"($pkg)/recipe.yaml" | path exists) {
            print $"No recipe.yaml found for ($pkg)"
            false
        } else {
            print $"recipe.yaml found for ($pkg)"
            let recipe = open $"($pkg)/recipe.yaml"
            if ($recipe.extra?.tarball-size? | default 0) > 30000 {
                print $"Package ($pkg) is too large"
                false
            }
            if ($recipe.extra?.conda-size? | default 0) > 3000 {
                print $"Package ($pkg) is too large"
                false
            }
            match $recipe.build?.noarch? {
                "python" => true,
                "generic" => true,
                _ => false
            }
        }
    }
}

# Find packages that are platform-specific (not noarch)
export def find_platform_specific_packages [
    --src-dir: string = "./pkgs",
    --verbose,                              # Enable verbose output
] {
    ls $src_dir
    | where type == dir
    | get name
    | where {|pkg|
        if not ($"($pkg)/recipe.yaml" | path exists) {
            false
        } else {
            let recipe = open $"($pkg)/recipe.yaml"
            if ($recipe.extra?.tarball-size? | default 0) > 30000 {
                print $"Package ($pkg) is too large"
                false
            }
            if ($recipe.extra?.conda-size? | default 0) > 3000 {
                print $"Package ($pkg) is too large"
                false
            }
            ($recipe.build?.noarch? | default false) == false
        }
    }
}
