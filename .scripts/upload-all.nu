# upload-all.nu

def main [pkg_dir: string] {

   for $proj in (glob $pkg_dir/**/*.conda) { 
       rattler-build upload prefix --channel https://prefix.dev/meso-forge $proj
    }

}
