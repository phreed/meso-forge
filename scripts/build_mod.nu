
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

    let tarball_size = ($recipe.extra?.filter?.tarball-size? | default 0)
    let conda_size = ($recipe.extra?.filter?.conda-size? | default 0)

    if (($tarball_size | describe) == "int" or ($tarball_size | describe) == "float") and $tarball_size > $upper_tarball_size {
        print $"Package tarball ($recipe.package?.name?) is too large"
        return false
    }
    if (($conda_size | describe) == "int" or ($conda_size | describe) == "float") and $conda_size > $upper_conda_size {
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
    let recipe_yaml = (rattler-build build --render-only --recipe $recipe | from yaml)
    # rattler-build returns an array of recipes, we want the first one
    let first_recipe = $recipe_yaml | first
    if not ($first_recipe.recipe | pkg_filter) {
        return nothing
    }
    return $first_recipe.recipe
}

# Find packages marked as noarch
export def find_noarch_packages [
    --src-dir: string = "./pkgs",
    --verbose,                              # Enable verbose output
] {
    ls $src_dir
    | where type == dir
    | get name
    | each {|pkg| $pkg | path basename}
    | where {|pkg|
        let recipe_path = ($src_dir | path join $pkg "recipe.yaml")
        if not ($recipe_path | path exists) {
            print $"No recipe.yaml found for ($pkg)"
            false
        } else {
            print $"recipe.yaml found for ($pkg)"
            let recipe = resolve_recipe --recipe $recipe_path
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
    | each {|pkg| $pkg | path basename}
    | where {|pkg|
        let recipe_path = ($src_dir | path join $pkg "recipe.yaml")
        if not ($recipe_path | path exists) {
            false
        } else {
            let recipe = resolve_recipe --recipe $recipe_path
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
