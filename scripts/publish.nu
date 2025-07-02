#!/usr/bin/env nu

use publish_mod.nu [publish get_args announce_pkg show_result]

# Publish all packages
def main [
    --mode: string = "s3",
    --src-dir: string = "./output",
    --channel: string,
    --url: string = "https://minio.isis.vanderbilt.edu",
    --dry-run,                # Show command without executing
    --verbose,                # Enable verbose output
    --force                   # Force upload, overwriting existing packages
] {
    print "🚀 Publishing all packages..."

    glob ($src_dir | path join "**/repodata.json") | each { |file|
        let dir = ($file | path dirname)
        open $file
        | from json
        | get "packages.conda"
        | transpose key value
        | each {|pkg|
            let pkg_path = $dir | path join $pkg.key

            let args = $pkg
            | announce_pkg
            | get_args $mode $channel $url $force $verbose
            | append $pkg_path

            $pkg
            | publish ...$args
            | show_result $mode
        }
    }

    print "✅ All packages published successfully!"
}
