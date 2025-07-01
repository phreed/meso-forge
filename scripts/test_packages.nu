#!/usr/bin/env nu

# Test built packages
def main [
    --platform (-p): string = ""  # Test packages for specific platform
    --package (-k): string = ""   # Test specific package
] {
    print "🧪 Testing built packages..."

    let output_dirs = if ($platform | is-empty) {
        ls output | where type == dir | get name
    } else {
        let platform_dir = $"output/($platform)"
        if ($platform_dir | path exists) {
            [$platform_dir]
        } else {
            print $"❌ No packages found for platform: ($platform)"
            return
        }
    }

    for dir in $output_dirs {
        let platform_name = $dir | path basename
        print $"\n🔍 Testing packages for ($platform_name)..."

        let packages = ls $dir | where name =~ "\.conda$|\.tar\.bz2$" | get name

        if ($packages | length) == 0 {
            print $"  ℹ️  No packages found in ($dir)"
            continue
        }

        for package_file in $packages {
            let package_name = $package_file | path basename | str replace -r "\.(conda|tar\.bz2)$" ""

            if (not ($package | is-empty)) and ($package_name !~ $package) {
                continue
            }

            print $"  Testing: ($package_name)"

            # Basic package validation
            try {
                # Check if package can be inspected
                conda package -i $package_file | ignore
                print $"    ✅ Package structure valid"

                # Try to extract and check contents
                let temp_dir = mktemp -d
                try {
                    tar -tf $package_file | head -10 | each { print $"      ($in)" }
                    print $"    ✅ Package contents accessible"
                } catch {
                    print $"    ⚠️  Could not inspect package contents"
                }
                rm -rf $temp_dir

            } catch {
                print $"    ❌ Package validation failed"
            }
        }
    }

    print "🧪 Package testing complete!"
}
