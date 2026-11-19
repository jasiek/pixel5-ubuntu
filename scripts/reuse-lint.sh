#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Check licensing with the REUSE tool (https://reuse.software), in a
# throwaway python container so nothing is installed on the Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
exec docker run --rm -v "$PWD:/w" -w /w python:3.12 sh -c \
    'git config --global --add safe.directory /w &&
     pip install -q --root-user-action=ignore "reuse[charset-normalizer]" >/dev/null 2>&1 &&
     reuse lint'
