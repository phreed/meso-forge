# upload-all.nu

# Scan the pkg_dir looking for conda packages.
# When found upload them to the meso-forge channel on prefix.dev.

def main [pkg_dir: string] {
    do {
        cd $pkg_dir;
        for $proj in (glob "**/*.conda") { 
            rattler-build upload prefix --channel https://prefix.dev/meso-forge $proj
        }
    }
}

# Example usage:
#   main "pkgs"
