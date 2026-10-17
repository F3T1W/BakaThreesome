#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

dotnet build BakaThreesome.slnx --configuration Debug --nologo
xcodebuild \
    -project BakaThreesome.xcodeproj \
    -scheme BakaThreesome \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath artifacts/DerivedData \
    build
