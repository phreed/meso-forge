#!/usr/bin/env nu

# JSON Handling Patterns Demo for Nushell
# Demonstrates excellent patterns for working with JSON data in nushell

# =============================================================================
# EXCELLENT PATTERNS: Native nushell data structure handling
# =============================================================================

# Pattern 1: Reading JSON files - nushell automatically parses JSON
export def "demo-json-reading" [] {
    print "=== Pattern 1: Reading JSON Files ==="

    # Create a sample JSON file
    let sample_data = {
        name: "example-package",
        version: "1.2.3",
        dependencies: [
            {name: "dep1", version: "^2.0.0"},
            {name: "dep2", version: "~1.5.0"}
        ],
        metadata: {
            author: "Jane Doe",
            license: "MIT"
        }
    }

    # Save as JSON
    $sample_data | to json --indent 2 | save /tmp/sample.json

    # EXCELLENT: Open automatically parses JSON into nushell data structures
    let parsed_data = open /tmp/sample.json
    print $"Package name: ($parsed_data.name)"
    print $"Version: ($parsed_data.version)"
    print $"Dependencies count: ($parsed_data.dependencies | length)"

    # Clean up
    rm /tmp/sample.json
}

# Pattern 2: Working with JSON data natively
export def "demo-native-processing" [] {
    print "\n=== Pattern 2: Native Data Processing ==="

    let packages = [
        {name: "pkg1", version: "1.0.0", license: "MIT"},
        {name: "pkg2", version: "2.1.0", license: ""},
        {name: "pkg3", version: "0.5.0", license: "Apache-2.0"}
    ]

    # EXCELLENT: Work with data structures directly
    let processed = $packages
        | where version =~ "^[12]"  # Filter by version pattern
        | update license { |row|
            if ($row.license | is-empty) { "UNKNOWN" } else { $row.license }
        }
        | insert has_major_version { |row|
            ($row.version | split row "." | first | into int) >= 1
        }

    print "Processed packages:"
    $processed | table
}

# Pattern 3: API responses and JSON conversion
export def "demo-api-response" [] {
    print "\n=== Pattern 3: API Response Handling ==="

    # Simulate API response (normally you'd get this from an HTTP request)
    let api_response = {
        status: "success",
        data: {
            packages: [
                {name: "react", version: "18.2.0", downloads: 1000000},
                {name: "vue", version: "3.3.4", downloads: 800000}
            ]
        }
    }

    # EXCELLENT: Work with the structure directly
    let popular_packages = $api_response.data.packages
        | where downloads > 900000
        | select name version

    print "Popular packages (>900k downloads):"
    $popular_packages | table
}

# Pattern 4: Conditional JSON output
export def "demo-conditional-json" [
    --json  # Flag to output as JSON
] {
    print "\n=== Pattern 4: Conditional JSON Output ==="

    let data = {
        build_info: {
            package: "my-package",
            version: "1.0.0",
            platform: "linux-64",
            timestamp: (date now)
        },
        stats: {
            duration: "2m 30s",
            size: "15.2 MB"
        }
    }

    # EXCELLENT: Only convert to JSON when needed
    if $json {
        $data | to json --indent 2
    } else {
        print $"Package: ($data.build_info.package)"
        print $"Version: ($data.build_info.version)"
        print $"Platform: ($data.build_info.platform)"
        print $"Build duration: ($data.stats.duration)"
        print $"Package size: ($data.stats.size)"
    }
}

# =============================================================================
# ANTI-PATTERNS: What NOT to do
# =============================================================================

# Anti-pattern 1: Unnecessary JSON serialization/deserialization
export def "demo-antipattern-unnecessary-conversion" [] {
    print "\n=== ANTI-PATTERN: Unnecessary JSON Conversion ==="

    let data = {name: "test", version: "1.0.0"}

    # BAD: Converting to JSON and back for no reason
    print "❌ BAD:"
    print "let result = ($data | to json | from json | get name)"
    let bad_result = ($data | to json | from json | get name)
    print $"Result: ($bad_result)"

    # GOOD: Work with the data directly
    print "\n✅ GOOD:"
    print "let result = $data.name"
    let good_result = $data.name
    print $"Result: ($good_result)"
}

# Anti-pattern 2: Using external JSON tools
export def "demo-antipattern-external-tools" [] {
    print "\n=== ANTI-PATTERN: External JSON Tools ==="

    let json_string = '{"name": "test", "version": "1.0.0"}'

    # BAD: Using external jq (if it were available)
    print "❌ BAD (would use external jq):"
    print "echo '$json_string' | jq '.name'"

    # GOOD: Use nushell's native JSON handling
    print "\n✅ GOOD:"
    print "($json_string | from json | get name)"
    let result = ($json_string | from json | get name)
    print $"Result: ($result)"
}

# =============================================================================
# REAL-WORLD EXAMPLES from the meso-forge scripts
# =============================================================================

# Example 1: Package manifest handling (inspired by manifest_utils.nu)
export def "demo-manifest-handling" [] {
    print "\n=== Real-world Example: Package Manifest ==="

    # Simulate a conda manifest structure
    let manifest = {
        "linux-64": {
            "numpy": {
                path: "/path/to/numpy-1.24.3-py311.conda",
                filename: "numpy-1.24.3-py311.conda",
                size: 6234567,
                modified: "2023-12-01T10:30:00Z",
                build_time: "2023-12-01 10:30:00 +0000",
                status: "built"
            },
            "scipy": {
                path: "/path/to/scipy-1.11.4-py311.conda",
                filename: "scipy-1.11.4-py311.conda",
                size: 12345678,
                modified: "2023-12-01T11:45:00Z",
                build_time: "2023-12-01 11:45:00 +0000",
                status: "built"
            }
        }
    }

    # EXCELLENT: Work with the structure directly
    let linux_packages = $manifest."linux-64"
    let total_size = ($linux_packages | values | get size | math sum)
    let built_packages = ($linux_packages | values | where status == "built" | length)

    print $"Platform: linux-64"
    print $"Total packages: ($linux_packages | columns | length)"
    print $"Built packages: ($built_packages)"
    print $"Total size: (($total_size / 1024 / 1024) | math round -p 2) MB"

    # Show package details
    print "\nPackage details:"
    $linux_packages | transpose package info | table
}

# Example 2: API check results (inspired by check_package_exists.nu)
export def "demo-api-check-results" [] {
    print "\n=== Real-world Example: API Check Results ==="

    # Simulate check results from different sources
    let check_results = [
        {location: "conda-forge", found: true, count: 5, packages: [
            {version: "1.24.3", build_number: "py311h1d29b94_0"},
            {version: "1.24.2", build_number: "py311h1d29b94_0"}
        ]},
        {location: "local", found: false, count: 0, packages: []},
        {location: "prefix.dev/meso-forge", found: true, count: 2, packages: [
            {version: "1.24.3", build: "py311_custom_0"}
        ]}
    ]

    # EXCELLENT: Process the results natively
    let found_locations = $check_results | where found == true | get location
    let total_found = ($check_results | where found == true | get count | math sum)
    let remote_found = ($check_results | where found == true and location != "local" | length) > 0

    print $"Package found in: ($found_locations | str join ', ')"
    print $"Total packages found: ($total_found)"
    print $"Available remotely: ($remote_found)"

    # Show detailed results
    print "\nDetailed results:"
    $check_results | select location found count | table
}

# Main demo function
def main [] {
    print "🚀 Nushell JSON Handling Patterns Demo"
    print "======================================"

    demo-json-reading
    demo-native-processing
    demo-api-response
    demo-conditional-json
    demo-antipattern-unnecessary-conversion
    demo-antipattern-external-tools
    demo-manifest-handling
    demo-api-check-results

    print "\n✅ Demo completed!"
    print "\nKey takeaways:"
    print "1. Use 'open' to automatically parse JSON files"
    print "2. Work with nushell data structures directly"
    print "3. Only use 'to json'/'from json' when interfacing with external systems"
    print "4. Avoid unnecessary JSON serialization/deserialization"
    print "5. Leverage nushell's native data manipulation commands"
}
