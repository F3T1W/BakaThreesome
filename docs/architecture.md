# BakaThreesome Architecture

Decision: a native macOS 26+ app using SwiftUI with selective AppKit integration,
structured as a modular monolith with Ports & Adapters. The MVP uses an external
mpv process controlled through JSON IPC.

## Structure

- `BakaThreesome.xcodeproj`: the application target and .app build configuration.
- `macOS/`: application entry point and dependency composition.
- `Packages/BakaKit/`: a local Swift Package with separate targets:
  - `BakaUI`: native screens and presentation state.
  - `Accounts`: credential storage contracts and macOS Keychain access.
  - `Kinopub`: browser media discovery, catalog models/port and a signed-in WebKit search adapter.
  - `Catalog`: Shikimori catalog models.
  - `Matching`: title normalization, candidate resolution and saved season mappings; depends on Catalog and Kinopub.
  - `Playback`: playback and position models.
  - `Tracking`: episode context, resume checkpoint policy and actor-owned SwiftData history; depends on Catalog and Playback.
  - `ShikimoriBridge`: typed API client, child-process transport and account lifecycle.
- `BakaThreesome.slnx`: the .NET solution:
  - `BakaThreesome.Bridge.Contracts`: the JSON v1 contract.
  - `BakaThreesome.ShikimoriBridge`: the child console process and ShikimoriSharp adapter.
  - `BakaThreesome.ShikimoriBridge.Checks`: synthetic HTTP contract checks.
- `Vendor/ShikimoriSharp`: attributed MIT source adaptation, isolated from app code.

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

One JSON line per request and response. Request fields: version, id, method and
parameters. Responses preserve the request ID and contain either result or error.
Reserve stdout for the protocol. Capabilities cover handshake, public catalog,
anime details, OAuth tokens/profile and signed-in list reads/writes.
Never pass secrets as process arguments or write them to logs.

The serial Swift transport owns and bounds the helper lifecycle. Xcode embeds
the helper and dependency/license files; the local .NET 10 runtime is still
required. Self-contained runtime distribution is not implemented. Swift account
services own token rotation and Keychain persistence. See
[Shikimori integration](shikimori-integration.md) for supported behavior and checks.

## Future boundaries

The Kinopub catalog gateway is implemented for website search and item details.
Introduce a stream gateway and further storage interfaces as their scenarios appear.
SwiftData stores local episode playback history;
confirmed title mappings currently use a small atomic JSON store. Keychain stores
secrets. Tracking owns unique playback coverage, confirmed numbering, an atomic
account-bound progress outbox and delivery policy. The Shikimori adapter reconciles
absolute counts before a progress-only update; BakaUI owns opt-in settings and retries.
See [Automatic progress](automatic-progress.md) for delivery and concurrency limits.

PlaybackEngine and its external mpv adapter are now implemented. The application
composition owns diagnostics, and an AppKit termination delegate waits for
diagnostic and account/helper cleanup on Quit. See [Playback foundation](playback.md) for current
behavior, verification, and remaining work.

CredentialStore and the Shikimori account service manage secrets through Keychain.
Kinopub sign-in uses a separate persistent WebKit browser session. Application
composition shares these services between windows and waits for account, browser,
and player cleanup on Quit. See [Kinopub browser](kinopub-browser.md) and
[Getting started](getting-started.md) for the current user flow.

## Distribution

The current build is local and ad-hoc signed, with sandboxing disabled.
Hardened runtime is configured, but Xcode disables it for ad-hoc signing.
Developer ID signing, notarization, runtime distribution, and architecture
verification are required before distribution. mpv and SVP are not bundled.

Remaining work: automatic external alias lookup, sustained playback validation, automatic episode-offset inference,
and tracking across multiple playback sessions. Embedded libmpv requires a separate experiment.

[Title matching, website search and saved destinations](title-matching.md).

[Episode identity, resume persistence and Continue Watching](continue-watching.md).

## Artwork presentation

Catalog exposes an optional poster URL by anime ID. The bridge reads GraphQL poster
metadata through the existing ShikimoriSharp transport in batches of at most 50.
A shared BakaUI artwork model coalesces requests and owns metadata, decoded-image
and HTTP caches. The same thumbnail and adaptive grid views serve Catalog, Watchlist
and Continue Watching; artwork failure never blocks title data or playback.
