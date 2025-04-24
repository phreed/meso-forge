# license-summary.nu

# Define common license file names
let license_names = ['LICENSE', 'LICENSE.txt', 'LICENSE.md', 'COPYING', 'COPYING.txt']

# Heuristically guess license type from license file content
def guess_license_type [text: string] {
    let content = $text | str downcase

    if $content =~ 'mit license' or $content =~ 'permission is hereby granted' {
        return 'MIT'
    } else if $content =~ 'gnu general public license' or $content =~ 'gpl' {
        return 'GPL'
    } else if $content =~ 'apache license' {
        return 'Apache'
    } else if $content =~ 'mozilla public license' or $content =~ 'mpl' {
        return 'MPL'
    } else if $content =~ 'bsd license' or $content =~ 'redistribution and use' {
        return 'BSD'
    } else if $content =~ 'creative commons' {
        return 'CC'
    } else if $content =~ 'unlicense' {
        return 'Unlicense'
    } else {
        return 'Unknown'
    }
}

# Main logic: gather and display license info
def main [
    path: string # Directory to scan
    --output(-o): string # Optional output file path
] {
    let results = (
        ls $path --recursive
        | where type == 'file' and (name | path basename | str downcase) in ($license_names | each {|n| $n | str downcase })
        | each {|file|
            let dir = ($file.name | path dirname)
            let package_path = ($dir | path join "package.json")

            let package_info = if (path exists $package_path) {
                try { open $package_path | select name version license } catch { null }
            } else { null }

            let license_text = try { open $file.name | str join } catch { "" }
            let heuristic_license = guess_license_type $license_text

            {
                package: ($package_info.name? | default "unknown"),
                version: ($package_info.version? | default "unknown"),
                license: ($package_info.license? | default $heuristic_license),
                license_file: $file.name
            }
        }
        | sort-by package
    )

    if $output != null {
        $results | save --force $output
    } else {
        $results
    }
}

# Example usage:
#   main "node_modules"
#   main "node_modules" --output licenses.json
