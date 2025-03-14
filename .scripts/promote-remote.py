#!/usr/bin/env python3
#
from pathlib import Path
import os
import glob
import subprocess
import sys
from argparse import ArgumentParser
import platform


def run_build(ns):
    script = ".scripts/run_promote.sh"
    subprocess.check_call([script])


def main(args=None):
    p = ArgumentParser("build-locally")
    p.add_argument("config", default=None, nargs="?")
    p.add_argument(
        "--debug",
        action="store_true",
        help="Setup debug environment using `conda debug`",
    )
    p.add_argument(
        "--output-id", help="If running debug, specify the output to setup."
    )

    ns = p.parse_args(args=args)
    verify_config(ns)
    setup_environment(ns)

    if ns.config.startswith("linux") or (
        ns.config.startswith("osx") and platform.system() == "Linux"
    ):
        run_podman_build(ns)
    elif ns.config.startswith("osx"):
        run_osx_build(ns)
    elif ns.config.startswith("win"):
        run_win_build(ns)


if __name__ == "__main__":
    main()

