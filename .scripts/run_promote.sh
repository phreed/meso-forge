#!/usr/bin/env bash
    
export ANACONDA_API_KEY=$(secret-tool lookup ANACONDA API_KEY)
export ANACONDA_FORCE=true
export ANACONDA_OWNER=mesomorph
# export ANACONDA_CHANNEL=dev
export RATTLER_BUILD_LOG_STYLE=fancy

for pkg in "$@"; do
for conda in $(find output -type f \( -name "${pkg}*.conda" -o -name "${pkg}*.tar.bz2" \) ); do
    echo "Uploading ${conda}"
    rattler-build upload anaconda -v --force "${conda}"
done
done
