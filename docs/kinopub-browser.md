# Kinopub browser playback prototype

Kinopub sign-in uses the website inside a dedicated WebKit browser session.
Shikimori authentication is independent and lives in Settings > Accounts.

## Current flow

1. Open Kinopub in the native sidebar. The initial address is the user's supplied
   mirror, `https://gxux.pkr.ovh`; another trusted HTTPS mirror can be entered.
2. Sign in directly on the website. Passwords are handled by the page and WebKit;
   native code does not read login form values.
3. Find a title on the website, choose an episode, and start its web player.
4. Choose Play Episode in mpv. This prioritizes the same-origin `/manifest/` HLS
   source from the video's source element, preserving the master playlist's tracks.
   The individual-source list and optional External audio picker remain available
   for diagnostics and sources that genuinely expose only separate tracks.
5. Stop mpv stops the app-owned player. Clear Session clears this browser's website
   data and stops its player; it does not affect Safari or another browser profile.

This stage intentionally uses the website for search/episode selection. A native
Kinopub catalog and automatic Shikimori-to-Kinopub matching are not implemented.

## Isolation and extraction

A dedicated persistent WKWebsiteDataStore retains this app's browser session.
It is separate from Shikimori credentials in Keychain and the user's other browsers.
Top-level navigation is limited to the entered HTTPS host and its subdomains.
HTTPS subframes may load player content. Unknown top-level redirects are blocked;
if a legitimate mirror changes domains, the user must enter the new address.
There is no certificate exception or automatic permission approval.

MediaDiscovery.js runs in WebKit's isolated defaultClient world in each frame.
It reads video/audio currentSrc, src and source-element attributes, media anchor hrefs,
and Resource Timing entries. A MutationObserver and PerformanceObserver discover
later media. It does not intercept form submissions, read passwords, export
cookies, or scan arbitrary response bodies. Blob URLs are not external media
sources and are ignored; the corresponding manifest may appear as a resource.
Encrypted Media Extensions / DRM are not handled.

Candidates stay in memory, are deduplicated and bounded, and are cleared on
navigation. Native labels show only format, host and discovery method. Token
query strings are neither displayed nor logged. A DOM video-source discovery can
upgrade an earlier Resource Timing entry for the same URL. Rescan can return earlier media
resources from the same document, so source selection remains explicit. Resource
names without recognized media extensions may not be discovered.

## Playback boundary

PlaybackSource adds typed request context to the existing PlaybackEngine. The
mpv loadfile command sends the URL and per-file options in one JSON IPC request,
with the index argument required by mpv 0.38+. The original master URL is sent
directly; no local copy, playlist rewriting, cookie export, or media proxy is used. No media token appears in process
arguments. An optional external audio URL uses the per-file `audio-files-append`
option, which treats its value as one literal item, including reserved characters. Per-file User-Agent, Origin and origin-only Referer follow the selected source;
extractor hooks are disabled for these direct media URLs. Header controls and
embedded URL credentials are rejected. Options do not leak to the next file.

The current prototype does not transfer browser cookies or arbitrary authorization
headers into mpv. Some signed URLs work alone, while other sources may require
extra context. Determine that from an actual authenticated playback request before
adding narrowly scoped cookie support. Expired URLs require reopening/rescanning.
A successful loadfile command alone is not treated as playback success. The IPC
transport waits up to 60 seconds for file-loaded (or reports end-file/error),
separately from the normal two-second command timeout. Cancellation interrupts
this wait through short poll intervals, so application shutdown does not have to
wait for the full HLS timeout. The prototype then waits
up to 20 seconds for non-idle playback with timing and decoder metadata. It distinguishes audio-only, video-only and combined playback. When
external audio is requested, both decoders must be present before success. This check does
not prove sustained playback, decoding quality or SVP interpolation.

The app pauses neither cross-origin web players nor their frames automatically.
Pause the web player manually after starting mpv if both play audio. Playback
progress is not yet written to Shikimori.

## Verification

- Swift tests cover candidate HTTPS/credential validation, token-free labels,
  origin referrers, header control rejection and per-file options.
- `node scripts/check-media-discovery.mjs` uses synthetic DOM/resource fixtures to
  check discovery, relative links, resource observation, deduplication and rescan.
  Node is needed only for this optional script check.
- `BAKA_MPV_INTEGRATION=1 swift test --package-path Packages/BakaKit` verifies the
  changed loadfile shape against the installed mpv using generated local audio.
- On 2026-10-18 the native browser loaded the supplied mirror and its login form.
  The user then signed in and selected an episode. Authenticated discovery found
  an advertisement plus separate HLS video/audio resources. The video decoded as
  H.264 at 1920x1072 and the audio as AAC; both had approximately 1425 seconds of
  media. The final primary-manifest button was verified using the original DOM
  URL: simultaneous H.264 video and AAC audio at 1920x1072, approximately 1425
  seconds duration, with playback advancing to about 50 seconds. Playback was
  paused after the check. No credentials or signed URLs were stored in fixtures
  or documentation. Browser login survived application restarts.
- The original user-supplied working command included Origin as well as Referer
  and User-Agent. All three are now derived from the browser context. Isolating
  whether Origin alone is required was not part of this check.
- The live mpv logs still showed intermittent CDN TLS timeouts and an audio
  underrun. The existing http_persistent=0,http_multiple=0 settings are retained;
  a short successful check does not prove long-session stability or SVP.
- A real mpv test pairs generated Y4M video with separate WAV audio, including
  colon, comma and percent characters in its path. Using the literal append option avoids splitting a URL or path at reserved
  characters.

References: [Apple WKWebView](https://developer.apple.com/documentation/webkit/wkwebview/),
[mpv manual](https://mpv.io/manual/stable/).
