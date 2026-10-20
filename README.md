# BakaThreesome

A native macOS anime streaming app integrating Shikimori, Kinopub, and SVP

The interface uses SwiftUI, with AppKit where window management or system
integration requires it. An external mpv process is controlled through JSON IPC.
Shikimori catalog and manual tracking are connected; Kinopub stream retrieval,
automatic episode-number inference and sustained playback validation remain in progress.

## Acknowledgments

Shikimori integration uses
[ShikimoriSharp](https://github.com/JustRoxy/ShikimoriSharp), a C#/.NET API client
by [JustRoxy](https://github.com/JustRoxy). Thank's, Akari ;3

The vendored adaptation preserves its MIT license and copyright notice and ships
them with the helper. [Source provenance and local patches](Vendor/ShikimoriSharp/PATCHES.md).
General-purpose fixes can be proposed upstream.

Copyright (c) 2020 JustRoxy

## What you need

- macOS 26 or later. The Universal download includes Apple Silicon and Intel builds;
  physical Intel Macs have not been tested.
- [.NET 10 Runtime](https://dotnet.microsoft.com/en-us/download/dotnet/10.0) for Shikimori features.
  Under **Run apps**, choose **.NET Runtime** for macOS: Arm64 for Apple Silicon or x64 for Intel.
- [mpv](https://mpv.io/installation/) for video playback.
- A Kinopub account with access to the titles you want to watch.
- Optional: [SVP for Mac](https://www.svp-team.com/docs/mac/) for smoother playback.
  SVP also needs an mpv installation with VapourSynth support; follow its Mac setup guide.

## Install

1. Open the [latest release](https://github.com/F3T1W/ShikiThreesome/releases/latest)
   and download the **Universal DMG** from Assets.
2. Open the DMG and drag **BakaThreesome** into **Applications**.
3. Eject the DMG, then launch BakaThreesome from Applications.
4. Open **Diagnostics** and choose **Check Player** to check your mpv installation.

The current preview is not notarized and may be blocked by macOS. Read
[Apple's guide to opening downloaded apps](https://support.apple.com/en-us/102445)
if this happens. Only allow the app if you trust its source.

## Connect Shikimori

Shikimori lets you browse your lists, track watched episodes, and rate anime.
It requires a one-time application registration:

1. Open **Settings > Accounts** with the gear button or **Command-comma**.
2. Choose **Register Application** and sign in to Shikimori. Use the name
   `BakaThreesome`, redirect URI `urn:ietf:wg:oauth:2.0:oob`, and permission `user_rates`.
3. Copy the resulting **Client ID** and **Client secret** into the app.
4. Choose **Authorize in Browser** and approve access on Shikimori.
5. Copy the authorization code back into the app and choose **Connect Shikimori**.

Your account details are saved in macOS Keychain. If macOS asks BakaThreesome for
permission to access the saved account, review and approve the request yourself.

Open **Watchlist** to choose a list such as Watching, Planned, or Completed.
Use **Catalog** to find anime. Open a title to change its list, watched episode
count, or rating, then save your changes.

## Watch an episode

1. Open **Kinopub** in the sidebar and sign in on the website inside the app.
   If you use another Kinopub mirror, enter its address above the page and choose **Open**.
2. In **Watchlist** or **Catalog**, choose **Open in Kinopub** beside an anime.
   If asked, select the correct title and season. The app remembers your choice.
3. Select an episode and start its web player. You can pause it once it loads.
4. Turn **SVP** off if you do not have it installed, or leave it on to use interpolation.
5. Choose **Play Episode in mpv**. The video opens in a separate player window.

Use the **Audio** and **Subtitles** controls to choose tracks. The default preference
is Japanese audio with Russian subtitles, when available. With SVP enabled,
**SVP: Active** confirms interpolation is running.

## Resume and track progress

Open **Continue Watching** and choose **Continue** to resume your latest episode.
Positions are saved on this Mac. **Play from Beginning** starts the episode over.

Automatic watched-episode updates are optional: enable them in **Settings > Progress**
and confirm the episode number in Kinopub. Ratings and list statuses are changed manually.

## Update

When a new version is available, a download icon appears beside Settings.
Click it and follow the installation prompts to update and restart the app.
You can also choose **BakaThreesome > Check for Updates…** from the menu bar,
or **Check for Updates…** in **Settings > About**.

To update manually, download the latest DMG, quit the app, and replace the copy
in Applications. Saved accounts, matches, and playback positions are kept.

## If something does not work

- **mpv is missing:** install it, then run **Diagnostics > Check Player** again.
- **The episode button is missing:** start the web player and choose **Rescan**.
- **Playback was interrupted:** choose **Retry Playback** in Kinopub.
- **The title match is wrong:** use **Change Kinopub Match** from the title's context menu.
- **Shikimori did not reconnect:** use **Retry Restoring Session** in Accounts.
- **Updates cannot be checked:** try again later or use the manual DMG download.

For help, [open an issue](https://github.com/F3T1W/ShikiThreesome/issues).
Include your macOS version and what happened. Keep passwords, account secrets,
and private playback links out of reports.

## License

BakaThreesome's original code is available under the [MIT License](LICENSE).
Third-party components retain their own licenses and notices.

For build instructions and implementation details, see
[Development and implementation](docs/development.md).
