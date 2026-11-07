#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 typist contributors
#
# Fails if a commit in BASE..HEAD has no "Signed-off-by:" line matching its author.
# Usage: scripts/check-dco.sh <base-ref> [head-ref]

set -euo pipefail

base="${1:?usage: $0 <base-ref> [head-ref]}"
head="${2:-HEAD}"
failed=0

for sha in $(git rev-list --no-merges "$base..$head"); do
    author="$(git log -1 --format='%an <%ae>' "$sha")"
    if ! git log -1 --format='%B' "$sha" | grep -qiF "Signed-off-by: $author"; then
        echo "commit $(git log -1 --format='%h %s' "$sha")"
        echo "  has no 'Signed-off-by: $author'"
        failed=1
    fi
done

if [[ $failed -ne 0 ]]; then
    echo
    echo "Every commit must be signed off under the Developer Certificate of Origin."
    echo "Fix with: git rebase --signoff $base && git push --force-with-lease"
    exit 1
fi
echo "DCO sign-off: OK"
