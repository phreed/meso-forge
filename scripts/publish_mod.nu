
export def announce_pkg [ ]: record -> record {
    let pkg = $in
    print $"📦 Processing package ($pkg.value?.name?):($pkg.value?.version?)"
    $pkg
}

export def get_args [
   mode: string
   channel: string
   url: string
   force: bool
   verbose: bool
] {
    let pkg = $in
    if $verbose {
        print $"Input: ($pkg.value?.name? | default "unknown")"
    }

    match $mode {
        "pd" => {
            # --url if self hosted
            let args = ["upload", "prefix",
                "--channel", ($channel | default --empty "meso-forge"),
                ]
            let args = if $force {$args | insert 2 "--skip-package"} else {$args}
            let args = if $verbose {$args | insert 2 "--verbose"} else {$args}
            if $verbose {
                print $"Args: ($args)"
            }
            $args
        },
        "s3" => {
            # --region
            let args = ["upload", "s3",
                "--channel", $channel,
                "--force-path-style",
                "--endpoint-url", ($url | default --empty "s3://pixi/meso-forge"),
                ]
            let args = if $verbose {$args | insert 2 "--verbose"} else {$args}
            if $verbose {
                print $"Args: ($args)"
            }
            $args
        },
        _ => {
            print $"Invalid mode: ($mode)"
            exit 1
        }
    }
}

# Publish to generic repository
export def --wrapped publish [
    dry_run: bool = false,                # Show command without executing
    ...cmds
] {
    if $dry_run {
        print $"🔍 Dry run - would execute:"
        print $"   rattler-build (($cmds | str join ' '))"
        exit 0
    }

    # Execute the publish
    let start_time = date now
    let result = (^rattler-build ...$cmds | complete)
    let duration = ((date now) - $start_time)

    if $result.exit_code == 0 {
        print $"✅ Successfully published !"

        # Show relevant output
        if not ($result.stdout | is-empty) {
            let output_lines = $result.stdout | lines
            let success_lines = $output_lines | where { |line|
                ($line | str contains "uploaded") or ($line | str contains "SUCCESS") or ($line | str contains "published")
            }

            if ($success_lines | length) > 0 {
                print "Upload details:"
                $success_lines | each { |line| print $"  ($line)" }
            }
        }
    }
    $result
}

def show_result_pd [] {
    let result = $in
}


def show_result_s3 [] {
    let result = $in

    if $result.exit_code != 0 {
        # Check if this is an S3 "file already exists" error
        let all_output = $result.stdout + "\n" + $result.stderr
        let is_s3_already_exists = (
            ($all_output | str contains "PreconditionFailed") or
            ($all_output | str contains "status: 412")
        )

        if $is_s3_already_exists {
            print $"⚠️  Package already exists on S3!"
            print ""
            print "This is expected if the package was previously uploaded."
            print "The existing package on S3 will be used."
        } else {
            print -e $"❌ Failed to publish!"

            if not ($result.stderr | is-empty) {
                print -e ""
                print -e "Error output:"
                print -e $result.stderr
            }

            # Try to extract specific error information
            let error_lines = $all_output | lines | where { |line|
                ($line | str contains "error") or ($line | str contains "Error") or ($line | str contains "failed") or ($line | str contains "Failed")
            }

            if ($error_lines | length) > 0 {
                print -e ""
                print -e "Error details:"
                $error_lines | first 5 | each { |line| print -e $"  ($line)" }

                if ($error_lines | length) > 5 {
                    print -e $"  ... and (($error_lines | length) - 5) more error lines"
                }
            }
            exit 1
        }
    }
}

export def show_result [mode: string] {
    let result = $in

    match $mode {
        "pd" => { $result | show_result_pd }
        "s3" => { $result | show_result_s3 }
    }
}
