# BakaThreesome

A native macOS anime streaming app integrating Shikimori, Kinopub, and SVP

The interface uses SwiftUI, with AppKit where window management or system
integration requires it. An external mpv process is controlled through JSON IPC.
Shikimori catalog and manual tracking are connected; Kinopub stream retrieval,
episode matching, and automatic playback synchronization are still in progress.

## Acknowledgments

Shikimori integration uses
[ShikimoriSharp](https://github.com/JustRoxy/ShikimoriSharp), a C#/.NET API client
by [JustRoxy](https://github.com/JustRoxy). Thank's, Akari ;3

The vendored adaptation preserves its MIT license and copyright notice and ships
them with the helper. [Source provenance and local patches](Vendor/ShikimoriSharp/PATCHES.md).
General-purpose fixes can be proposed upstream.

Copyright (c) 2020 JustRoxy

## Development

Requirements: macOS 26+, Xcode 26+ with Swift 6.2+, .NET SDK 10.0.203
(or a newer patch), and Python 3 for smoke checks
The initial build has been verified on Apple Silicon; Intel has not been tested and will never be

Open `BakaThreesome.xcodeproj` in Xcode and run the BakaThreesome scheme.
For C# development, open `BakaThreesome.slnx` in Rider.

From the project root:

```sh
./scripts/run.sh       # Build both stacks and open the app
./scripts/build.sh     # Build both stacks
./scripts/check.sh     # Check language, Swift contracts, and the actual helper
```

Built application: `artifacts/DerivedData/Build/Products/Debug/BakaThreesome.app`

[Architecture and module boundaries](docs/architecture.md).

## Current playback status

Diagnostics verifies the installed mpv version, VapourSynth availability, process
launch, and JSON IPC control. The playback adapter supports loading, pause, seek,
and position snapshots. Kinopub streams and active SVP interpolation are not
verified by this check.

[Playback foundation and real-player checks](docs/playback.md).

## Shikimori catalog and tracking

Catalog supports live public search. Connect Shikimori in Settings > Accounts to
browse status lists, add titles, update watched episodes, and set your rating.
Credentials and session tokens are saved in Keychain. Register your Shikimori
application through its application page.
The .NET helper is embedded by Xcode; the development app still needs a local
.NET 10 runtime. Live sign-in and writes require local account verification.

[Shikimori setup, behavior and verification](docs/shikimori-integration.md).

## Kinopub website prototype

Open Kinopub in the sidebar to sign in directly on the website.
The prototype discovers the primary HLS manifest from the video source element
and starts it through Play Episode in mpv. One live authenticated episode was
verified with simultaneous H.264 video and AAC audio. Browser cookies stay in
WebKit; playback receives the signed URL and browser request headers. Long-session
stability, cookie-dependent sources and SVP remain unverified.

[Browser flow, limitations and verification](docs/kinopub-browser.md).

[Getting started: Shikimori sign-in and episode playback](docs/getting-started.md).
