
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
    let upper_tarball_size = try { $env.PKG_MAX_TARBALL? | into int } catch { 32000 }
    let upper_conda_size = try { $env.PKG_MAX_CONDA? | into int } catch { 3200 }

    let tarball_size = try { ($recipe.extra?.filter?.tarball-size? | default 0) | into int } catch { 0 }
    let conda_size = try { ($recipe.extra?.filter?.conda-size? | default 0) | into int } catch { 0 }

    if $tarball_size > $upper_tarball_size {
        print $"Package tarball ($recipe.package?.name?) is too large ($tarball_size) > ($upper_tarball_size)"
        return false
    }
    if $conda_size > $upper_conda_size {
        print $"Package conda ($recipe.package?.name?) is too large ($conda_size) > ($upper_conda_size)"
        return false
    }
    print $"Package ($recipe.package?.name?) is within size limits"
    return true
}

export def resolve_recipe [ --recipe: string ] {
    if not ($recipe | path exists) {
        print $"Recipe ($recipe) does not exist"
        return nothing
    }
    try {
        let recipe_yaml = (^rattler-build build --render-only --recipe $recipe | from yaml)
        print $"Here is a recipe: ($recipe)"
        # rattler-build returns an array of recipes, we want the first one
        return ($recipe_yaml | first).recipe
    } catch {
        print $"Failed to parse recipe ($recipe)"
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
    | each {|pkg| $pkg | path basename}
    | where {|pkg|
        let recipe_path = ($src_dir | path join $pkg "recipe.yaml")
        if not ($recipe_path | path exists) {
            print $"X No recipe.yaml found for ($pkg)"
            return false
        } else {
            print $"recipe.yaml found for ($pkg)"
            let recipe = resolve_recipe --recipe $recipe_path
            if ($recipe == nothing) {
                print "❌ Package recipe does not exist"
                return false
            }
            if not ($recipe | pkg_filter) {
                print "❌ Package filtered out due to size constraints"
                return false
            }
            return (match $recipe.build?.noarch? {
                "python" => true,
                "generic" => true,
                _ => false
            })
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
            print "❌ Package filtered out because no recipe exists"
            return false
        } else {
            let recipe = resolve_recipe --recipe $recipe_path
            if ($recipe == nothing) {
                print "❌ Package recipe is missing or defective"
                return false
            }
            if not ($recipe | pkg_filter) {
                print "❌ Package filtered out due to size constraints"
                return false
            }
            if $recipe.build == nothing {
                print "❌ Package filtered because build section is missing"
                return false
            }
            if $recipe.build.noarch == nothing {
                print "✅ Package accepted because no build/noarch section is provided"
                return true
            }
            return (match $recipe.build?.noarch? {
                "python" => false,
                "generic" => false,
                _ => true
            })
        }
    }
}


export def --wrapped build_with_rattler_dry_run [package: string, ...rest] {
    let rest_str = $rest | flatten | str join ' '
    print $"build_with_rattler_dry_run ($package) ($rest_str)"
    print $"rattler-build build ($rest_str)"
}

export def --wrapped build_with_rattler [package: string, ...rest] {
    print $"Building package ($rest)..."
    if '--recipe' in $rest {
        try {
            let result = ^rattler-build build ...$rest | complete
            return $result
        } catch {
            print $"❌ Failed to build ($package)"
            exit 1
        }
        # if result == 0 {
        #     print $"Package ($package) built successfully"
        #     true
        # } else {
        #     print $"Failed to build package ($package)"
        #     false
        # }
    } else {
        print $"No recipe specified ($rest)"
        false
    }
}


# Build noarch packages
export def build_noarch_packages [
    --src-dir: string = "./pkgs",
    --tgt-dir: string = "./output",
    --dry-run,                              # Show command without executing
    --verbose,                              # Enable verbose output
] {
    let noarch_packages = find_noarch_packages --src-dir $src_dir

    if ($noarch_packages | length) == 0 {
        print "ℹ️  No noarch packages found"
        return
    }

    print $"Found ($noarch_packages | length) noarch packages"

    for package in $noarch_packages {
        print $"Building: ($package)"
        let recipe_path = ($src_dir | path join $package "recipe.yaml")

        if ($dry_run) {
            build_with_rattler_dry_run $package --recipe $recipe_path --output-dir $tgt_dir
        } else {
            try {
                build_with_rattler $package --recipe $recipe_path --output-dir $tgt_dir
                print $"✅ Successfully built ($package)"
            } catch {
                print $"❌ Failed to build ($package)"
            }
        }
    }
}

# Build platform specific packages
export def build_platform_packages [
    --platform: string,
    --src-dir: string = "./pkgs",
    --tgt-dir: string = "./output",
    --dry-run,                              # Show command without executing
    --verbose,                              # Enable verbose output
] {
    let platform_packages = find_platform_packages --src-dir $src_dir

    if ($platform_packages | length) == 0 {
        print "ℹ️  No platform-specific packages found"
        return
    }

    print $"Found ($platform_packages | length) platform-specific packages"

    for package in $platform_packages {
        print $"Building: ($package) for ($platform)"
        let recipe_path = ($src_dir | path join $package "recipe.yaml")

        if ($dry_run) {
            build_with_rattler_dry_run $package --recipe $recipe_path --target-platform $platform --output-dir $tgt_dir
        } else {
            try {
                build_with_rattler $package --recipe $recipe_path --target-platform $platform --output-dir $tgt_dir
                print $"✅ Successfully built ($package) for ($platform)"
            } catch {
                print $"❌ Failed to build ($package) for ($platform)"
            }
        }
    }
}
