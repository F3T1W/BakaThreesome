#!/bin/bash
set -euo pipefail

if [[ $# != 2 ]]; then
    echo 'Usage: scripts/generate-update-feed.sh <release-archives-directory> <github-release-tag>' >&2
    exit 1
fi

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archives_directory="$(cd "$1" && pwd)"
release_tag="$2"
if [[ -z "$release_tag" ]]; then
    echo 'The GitHub release tag must not be empty.' >&2
    exit 1
fi

appcast_tool="$project_root/Packages/BakaKit/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [[ ! -x "$appcast_tool" ]]; then
    echo 'Resolve Packages/BakaKit dependencies first: swift package --package-path Packages/BakaKit resolve' >&2
    exit 1
fi

# Each directory belongs to one release; never rewrite older assets to a newer tag URL.
encoded_tag="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$release_tag")"
"$appcast_tool" \
    --account dev.bakathreesome.updates \
    --maximum-deltas 0 \
    --download-url-prefix "https://github.com/F3T1W/ShikiThreesome/releases/download/$encoded_tag/" \
    --full-release-notes-url "https://github.com/F3T1W/ShikiThreesome/releases/tag/$encoded_tag" \
    --link 'https://github.com/F3T1W/ShikiThreesome' \
    --embed-release-notes \
    -o "$archives_directory/appcast.xml" \
    "$archives_directory"
