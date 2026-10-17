#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

python3 scripts/check-language.py
dotnet build BakaThreesome.slnx --configuration Debug --nologo
swift test --package-path Packages/BakaKit
python3 scripts/check-bridge.py
