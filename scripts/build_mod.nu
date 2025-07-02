
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

export def pkg_filter [] {
    let recipe = $in
    let upper_tarball_size = $env.PKG_MAX_TARBALL? | default --empty 32000
    let upper_conda_size = $env.PKG_MAX_CONDA? | default --empty 3200

    if ($recipe.extra?.filter?.tarball-size? | default 0) > $upper_tarball_size {
        print $"Package tarball ($recipe.package?.name?) is too large"
        return false
    }
    if ($recipe.extra?.filter?.conda-size? | default 0) > $upper_conda_size {
        print $"Package conda ($recipe.package?.name?) is too large"
        return false
    }
    print $"Package ($recipe.package?.name?) is within size limits"
    return true
}

export def resolve_recipe [
    --recipe: string,
    --verbose,                              # Enable verbose output
] {
    let recipe_yaml = (rattler-build build --render-only $recipe | from yaml)
    if not ($recipe_yaml | pkg_filter) {
        return nothing
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
            let recipe = resolve_recipe --recipe "($pkg)/recipe.yaml"
            match $recipe.build?.noarch? {
                "python" => true,
                "generic" => true,
                _ => false
            }
        }
    }
}

# Find packages that are platform-specific (not noarch)
export def find_platform_packages [
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
            let recipe = resolve_recipe --recipe "($pkg)/recipe.yaml"
            ($recipe.build?.noarch? | default false) == false
        }
    }
}

export def --wrapped build_with_rattler [...rest] {
    print $"Building package ($rest)..."
    if '--recipe' in $rest {
        let recipes = $rest
            | enumerate
            | where ($it.item == "--recipe")
            | each { |elt| $rest | get ($elt.index + 1) }
        let recipe_path = $recipes.0
        try {
            let result = ^rattler-build build ...$rest | complete
            return $result
        } catch {
            print $"❌ Failed to build ($recipe_path)"
            exit 1
        }
        # if result == 0 {
        #     print $"Package ($recipe) built successfully"
        #     true
        # } else {
        #     print $"Failed to build package ($recipe)"
        #     false
        # }
    } else {
        print $"No recipe specified ($rest)"
        false
    }
}
