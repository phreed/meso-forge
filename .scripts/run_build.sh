#!/usr/bin/env bash

echo "ARGS $@"
export ANACONDA_OWNER=mesomorph
export ANACONDA_CHANNEL=dev
    
rattler-build build anaconda -v --force "${pkg}"

for pkg in "$@"; do
  echo "PKG: $pkg"
  rattler-build build --recipe ./packages/${pkg} \
    --target-platform linux-64 \
    --channel mesomorph --channel conda-forge
done
