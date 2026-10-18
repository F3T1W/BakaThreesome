# BakaThreesome Architecture

Decision: a native macOS 26+ app using SwiftUI with selective AppKit integration,
structured as a modular monolith with Ports & Adapters. The MVP uses an external
mpv process controlled through JSON IPC.

## Structure

- `BakaThreesome.xcodeproj`: the application target and .app build configuration.
- `macOS/`: application entry point and dependency composition.
- `Packages/BakaKit/`: a local Swift Package with separate targets:
  - `BakaUI`: native screens and presentation state.
  - `Accounts`: service accounts.
  - `Catalog`: Shikimori catalog models.
  - `Matching`: catalog mappings; depends on Catalog.
  - `Playback`: playback and position models.
  - `Tracking`: resume state and progress; depends on Catalog and Playback.
  - `ShikimoriBridge`: Swift contracts for the .NET boundary.
- `BakaThreesome.slnx`: the .NET solution:
  - `BakaThreesome.Bridge.Contracts`: the JSON v1 contract.
  - `BakaThreesome.ShikimoriBridge`: the child console process.

Domain code does not depend on SwiftUI or AppKit. External service DTOs must
not become domain models. Introduce implementations and protocols alongside
working scenarios rather than creating an abstraction for every type.
Isolate UI state on MainActor; I/O must not block the interface.

All maintained content, interface strings, comments, documentation, file names,
and commit messages must be in English. The language check rejects Cyrillic
characters in maintained files and local commit messages.

## Native interface

Use NavigationSplitView, List, Toolbar, Settings, Form, and system windows.
Apply Liquid Glass through native styles and APIs. Accessibility and transparency
preferences remain under system control. Settings are available in the right
side of the toolbar; standard surfaces use system-provided styling.
English is the application's development language and its only declared
localization. Format the diagnostic OS version numerically to avoid localized
system text in the app's content.

## Swift / .NET boundary

One JSON line per request and response. Request fields: version, id, method.
Responses preserve the request ID and contain either result or error.
Reserve stdout for the protocol. The only current capability is handshake;
authentication and API calls are not implemented.
Never pass secrets as process arguments or write them to logs.

The Swift transport, helper lifecycle, and ShikimoriSharp integration are not
implemented yet. Bundling the helper and .NET runtime is a separate task.
Do not assume end users have dotnet installed.

## Future boundaries

Introduce ShikimoriGateway, KinopubGateway, CredentialStore,
and narrow storage interfaces as their scenarios are implemented.
SwiftData is the selected foundation for local persistence; Keychain stores
secrets. Synchronization must persist the intent to set absolute progress
and explicitly resolve conflicts with remote changes.

PlaybackEngine and its external mpv adapter are now implemented. The application
composition owns diagnostics, and an AppKit termination delegate waits for
diagnostic cleanup on Quit. See [Playback foundation](playback.md) for current
behavior, verification, and remaining work.

## Distribution

The current build is local and ad-hoc signed, with sandboxing disabled.
Hardened runtime is configured, but Xcode disables it for ad-hoc signing.
Developer ID signing, notarization, runtime distribution, and architecture
verification are required before distribution. mpv and SVP are not bundled.

Implementation order: stream retrieval, mpv/SVP, ShikimoriSharp, catalog and
matching, then tracking. Embedded libmpv requires a separate experiment.
