#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$project_root/scripts/build.sh"
open "$project_root/artifacts/DerivedData/Build/Products/Debug/BakaThreesome.app"
