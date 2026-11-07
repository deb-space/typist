#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 typist contributors
#
# Fails if a source file lacks the SPDX header in its first 5 lines.
# Checks files tracked by git, plus untracked files that are not ignored.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

expected="SPDX-License-Identifier: GPL-3.0-only"
missing=0

while IFS= read -r -d '' file; do
    [[ -f "$file" ]] || continue
    if ! head -n 5 "$file" | grep -q "$expected"; then
        echo "missing SPDX header: $file"
        missing=1
    fi
done < <(git ls-files -z --cached --others --exclude-standard -- \
    '*.swift' '*.sh' '*.py' '*.yml' '*.yaml' '*.xcconfig' '*.plist' '*.entitlements' Makefile)

if [[ $missing -ne 0 ]]; then
    echo
    echo "Add these two lines at the top of each file above (with the comment syntax of its language):"
    echo "  $expected"
    echo "  Copyright (C) $(date +%Y) typist contributors"
    exit 1
fi
echo "SPDX headers: OK"
