# Application updates

BakaThreesome uses Sparkle 2.10.0 to verify, download, replace and relaunch the
installed app. Scheduled checks show only an `arrow.down.circle` toolbar button
beside Settings. Its tooltip includes the available version. Clicking it opens
Sparkle's standard installation UI. The app menu and Settings > About also offer
Check for Updates. Dismissed or skipped updates clear the toolbar reminder.

Background checking is enabled by default with Sparkle's daily schedule. Automatic
downloads and unattended installation are disabled. Sparkle handles compatible
versions, skipped releases, failed downloads and installation permissions. Quit
still uses the application's asynchronous player, progress and helper cleanup.

## GitHub release contract

The production feed is:

`https://github.com/F3T1W/ShikiThreesome/releases/latest/download/appcast.xml`

GitHub's latest stable release must include `appcast.xml` and the corresponding
application archive as release assets. A Git tag or source-code archive alone is
not an application update. Drafts and prereleases are not the stable update feed.
Before the first release with these assets, background checks fail quietly;
manual checks show Sparkle's standard error. No update icon appears without a
valid, newer, compatible feed entry.

Both the feed and update archive require Ed25519 signatures. The public key lives
in `macOS/Info.plist`. The private key stays in the login Keychain under account
`dev.bakathreesome.updates`, managed by Sparkle's tools. Never commit or upload
that private key with release assets. Losing it can prevent existing installations
from accepting future updates; back it up securely outside the repository.

Sparkle tools are available after resolving package dependencies:

```sh
swift package --package-path Packages/BakaKit resolve
Packages/BakaKit/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account dev.bakathreesome.updates -p
```

The second command displays only the existing public key. Exporting the private
key for secure backup is a separate manual operation with `generate_keys -x`.
Use a destination outside the checkout and protect it as a signing credential.

## Preparing a future release

1. Increase `CURRENT_PROJECT_VERSION` monotonically and set `MARKETING_VERSION`.
2. Build the distributable app, sign and notarize it as appropriate. Keep the bundle
   identifier, public update key and feed URL consistent. Include the embedded
   .NET helper, framework, resources and third-party notices. The updater does not
   install external .NET, mpv or SVP prerequisites.
3. Put the final app archive in a new directory belonging only to this release.
   Use `ditto` for ZIP archives to preserve framework symlinks and signatures. Do
   not modify the archive after signing the feed. Optional matching `.md` release
   notes are embedded by the generator.
4. Generate the signed feed for that exact GitHub tag:

   ```sh
   ./scripts/generate-update-feed.sh artifacts/releases/v0.2.0 v0.2.0
   ```

5. Upload the archive and generated `appcast.xml` as assets of the same stable
   GitHub release. The script prepares metadata only; it does not build, upload,
   create or publish a release.
6. Test an actual upgrade from an older installed app copy in a disposable location.
   Verify signature rejection for a modified archive, successful relaunch, restored
   local progress, account access and mpv/SVP behavior. Do not test replacement in
   the active development checkout.

## Validation boundaries

Focused tests cover signing-key configuration, absent app configuration, manual
check readiness, passive update reminders and dismissal. They use a fake updater
driver and cannot replace an application. Sparkle's binary dependency is pinned
in the package manifest and resolved files. A real download/install/relaunch test
requires a signed release feed and distributable archive; a successful build is
not evidence that a published upgrade has completed.

The current local app is ad-hoc signed. Developer ID signing and notarization
remain part of the distribution stage. Ed25519 update signatures do not replace
Gatekeeper signing or notarization.

The Xcode project disables `COPY_PHASE_STRIP` in Debug and Release. Sparkle ships
pre-signed binaries; copy them intact. This setting does not disable symbol
stripping for the application executable or change its optimization settings.
