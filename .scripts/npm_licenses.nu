# npm_licenses.nu
def main [
    --production (-p)  # Only include production dependencies
    --json (-j)        # Output in JSON format
] {
    let args = if $production { ["--prod"] } else { [] }

    ^npm list --each --parseable ...$args
    | lines
    | skip 1
    | par-each { |path|
        let package_json = ($path | path join "package.json")
        if ($package_json | path exists) {
            open $package_json
            | from json
            | select name version license? repository?
            | update license {|r| $r.license | default "UNKNOWN"}
            | update repository {|r| $r.repository? | default $r.repository.url? | default ""}
        } else {
            null
        }
    }
    | compact
    | if $json { to json } else { $in }
}
