#!/usr/bin/env nu

# Lint all recipe files
def main [
    --fix (-f)  # Attempt to fix issues automatically
] {
    print "🔍 Linting recipe files..."

    let recipes = find_all_recipes

    if ($recipes | length) == 0 {
        print "ℹ️  No recipe files found"
        return
    }

    print $"Found ($recipes | length) recipe files"

    mut total_issues = 0

    for recipe in $recipes {
        let package_name = $recipe | path dirname | path basename
        print $"\n📋 Linting: ($package_name)"

        let issues = lint_recipe $recipe
        $total_issues = $total_issues + ($issues | length)

        if ($issues | length) == 0 {
            print $"  ✅ No issues found"
        } else {
            print $"  ⚠️  Found ($issues | length) issues:"
            for issue in $issues {
                print $"    - ($issue)"
            }

            if $fix {
                print $"  🔧 Attempting to fix issues..."
                try {
                    fix_recipe_issues $recipe $issues
                    print $"  ✅ Issues fixed"
                } catch {
                    print $"  ❌ Could not fix all issues automatically"
                }
            }
        }
    }

    print $"\n📊 Linting complete! Total issues found: ($total_issues)"

    if $total_issues > 0 and not $fix {
        print "💡 Run with --fix to attempt automatic fixes"
    }
}

# Find all recipe files
def find_all_recipes [] {
    find packages -name "recipe.yaml" -type f
}

# Lint a single recipe file
def lint_recipe [recipe_path: string] {
    mut issues = []

    try {
        let recipe = open $recipe_path

        # Check required fields
        if ($recipe.package?.name? | is-empty) {
            $issues = ($issues | append "Missing package.name")
        }

        if ($recipe.package?.version? | is-empty) {
            $issues = ($issues | append "Missing package.version")
        }

        # Check source section
        if ($recipe.source? | is-empty) {
            $issues = ($issues | append "Missing source section")
        }

        # Check build section
        if ($recipe.build? | is-empty) {
            $issues = ($issues | append "Missing build section")
        }

        # Check for common formatting issues
        let content = open $recipe_path | to text
        if ($content | str contains "\t") {
            $issues = ($issues | append "Contains tabs (should use spaces)")
        }

        if ($content | str contains "  \n") {
            $issues = ($issues | append "Contains trailing whitespace")
        }

    } catch {
        $issues = ($issues | append "Invalid YAML syntax")
    }

    $issues
}

# Fix common recipe issues
def fix_recipe_issues [recipe_path: string, issues: list] {
    let content = open $recipe_path | to text

    # Fix tabs to spaces
    let fixed_content = $content | str replace -a "\t" "  "

    # Remove trailing whitespace
    let final_content = $fixed_content | str replace -ra "[ ]+\n" "\n"

    $final_content | save -f $recipe_path
}
