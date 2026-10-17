# BakaThreesome

A native macOS anime streaming app integrating Shikimori, Kinopub, and SVP

The interface uses SwiftUI, with AppKit where window management or system
integration requires it. The first playback prototype will control an external
mpv process through JSON IPC. Stream retrieval and SVP connectivity come first,
followed by the catalog, episode matching, and progress synchronization

## Acknowledgments

The selected foundation for Shikimori integration is
[ShikimoriSharp](https://github.com/JustRoxy/ShikimoriSharp), a C#/.NET API client
by [JustRoxy](https://github.com/JustRoxy). Thank's, Akari ;3

The library is not connected yet. General-purpose fixes can be proposed upstream
When distributing the library, include its MIT license and copyright notice:

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
