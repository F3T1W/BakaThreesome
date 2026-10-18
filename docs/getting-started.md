# Getting started

## Launch BakaThreesome

From the project root, run:

```sh
./scripts/run.sh
```

This builds the native app and .NET helper, then opens BakaThreesome. The local
build requires macOS 26+, Xcode, .NET 10 and mpv. Diagnostics > Check Player checks
the installed player; it does not verify SVP interpolation.

## Connect Shikimori

1. Open Settings with the toolbar gear or Command-comma, then select Accounts.
2. In the Shikimori section, choose Register Application. Sign in on Shikimori
   and create an application with these values:
   - Name: `BakaThreesome`
   - Redirect URI: `urn:ietf:wg:oauth:2.0:oob`
   - Permission/scope: `user_rates`
3. Copy the application's Client ID and Client secret into the matching fields
   in BakaThreesome. These are Shikimori application credentials.
4. Choose Authorize in Browser, sign in if needed, and approve access.
5. Copy the authorization code displayed by Shikimori into Authorization code
   from Shikimori in the app, then choose Connect Shikimori.
6. Your nickname should appear in Settings. Open Watchlist to browse Watching,
   Planned, Completed, On Hold, Dropped, Rewatching, or All Lists.

Credentials and session tokens are saved in macOS Keychain. Enter them locally;
do not add them to source files. Check Session checks the saved session, and
Sign Out removes it from this app. Remote access revocation is managed on Shikimori.

To track a title, find it in Catalog or Watchlist, open it, choose a list, set
Watched episodes and Your rating, then choose Add to List or Save Changes.
Unrated clears the score. This is manual tracking; playback does not update it yet.

Shikimori registration and code exchange follow the
[official OAuth guide](https://shikimori.io/oauth).

## Play an episode

1. Open Kinopub in the main sidebar.
2. The configured website opens inside the app. Enter another trusted HTTPS
   mirror in the address field if needed, then choose Open.
3. Sign in directly on the website. This browser login is separate from Shikimori
   and survives app restarts. Clear Session removes this app's browser session.
4. Search for the title on the Kinopub website, select a season and episode, and
   start the web player. Wait for its media source to load; you can then pause it.
5. Leave SVP enabled below the web view to start SVP Manager automatically, or
   disable it to play without interpolation. The switch applies to the next session.
   Choose Play Episode in mpv below the web view. The app finds the primary HLS
   source from the video's source element and passes its original URL to mpv with
   the current browser's User-Agent, Origin and Referer.
6. mpv opens a separate video window. Use its playback controls for pause and seek.
   Stop mpv in BakaThreesome stops the player launched by this app.
7. Watch the SVP status below the web view. `SVP: Active` shows measured input and
   output frame rates, for example `24.00 → 60.00 fps`. If it stays waiting, check
   SVP Manager for a disabled profile, minimum video duration or a runtime error.
   Interpolation settings and target frame rate remain controlled by SVP Manager.

Pause the web player to avoid simultaneous sound from the website and mpv.
If Play Episode in mpv is missing, start the web player and choose Rescan.
The individual source list is a diagnostic fallback: it may include advertisements,
subtitles, video-only playlists and audio-only playlists. Prefer the episode button.

A short live episode check confirmed simultaneous video and audio. CDN timeouts
were also observed; long-session stability remains unverified. SVP interpolation
was confirmed on a live episode at 23.98 → 59.94 fps and a generated local video
at 24 → 60 fps. Live startup took nearly one minute. Reopen the episode and rescan if a signed source has expired.

## Current boundary

Use Open in Kinopub beside a title in Watchlist or Catalog to search by its
Shikimori names. A confident single-season match opens immediately. Otherwise
choose the correct card and season, then Save Match and Open. A saved link is
reused on the next click; the row context menu offers Change Kinopub Match.
The alternative-title section provides a Google search link, an extra title query
and a manual Kinopub page option. Google alias extraction is currently manual.
See [Title matching](title-matching.md) for behavior and limits.

The destination opens on the website. Start its web player and use Play Episode
in mpv to launch playback. Automatic episode offsets, resume persistence and
progress updates from playback are future work.

See [Shikimori details](shikimori-integration.md) and
[Kinopub browser details](kinopub-browser.md) for implementation and verification.
