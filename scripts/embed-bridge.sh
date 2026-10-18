#!/bin/bash
set -euo pipefail

for candidate in /usr/local/share/dotnet/dotnet /opt/homebrew/bin/dotnet /usr/local/bin/dotnet; do
    if [[ -x "$candidate" ]]; then
        dotnet_host="$candidate"
        break
    fi
done
if [[ -z "${dotnet_host:-}" ]]; then
    echo 'error: .NET 10 SDK is required to build the Shikimori helper.' >&2
    exit 1
fi

# Xcode exports TARGETNAME; MSBuild treats it as TargetName and otherwise gives
# every referenced project the app's assembly name.
env -u TARGETNAME -u TargetName "$dotnet_host" publish \
    "$SRCROOT/Bridge/BakaThreesome.ShikimoriBridge/BakaThreesome.ShikimoriBridge.csproj" \
    --configuration "$CONFIGURATION" \
    --no-self-contained \
    --output "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Bridge" \
    --nologo
