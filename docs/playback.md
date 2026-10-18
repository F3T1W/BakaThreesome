# Playback foundation

## Implemented

- `PlaybackEngine` defines asynchronous lifecycle, media loading, pause, seek,
  position snapshots, and stop operations. `MPVPlaybackEngine` is its actor-based
  external mpv implementation.
- Arguments are passed through Foundation Process without invoking a shell.
  Media URLs are sent through JSON IPC, not process arguments or logs.
  Only file, HTTP, and HTTPS URLs are accepted; blob URLs are rejected.
- Each session owns a short-lived directory with mode 0700 and a Unix socket.
  It does not occupy, remove, or replace `/tmp/mpvsocket`.
- The IPC transport uses a dedicated serial dispatch queue, newline framing,
  request IDs, bounded messages, and a two-second request timeout. It ignores
  unsolicited events while waiting for the matching command response.
- Startup waits at most five seconds for IPC. Stop closes the connection,
  sends SIGTERM to its own child, then escalates to SIGKILL if required.
  Repeated stop calls are safe; duplicate starts are rejected.
- Diagnostics probes the actual mpv version and filter list, then runs a
  headless IPC check, changes and reads back pause state, and stops its child.
  Navigation cancellation and normal application termination cancel the check
  and wait for cleanup. Discovery checks standard Homebrew and SVP locations.
- Probe subprocesses have a five-second timeout. Probe stdout is temporary,
  private, bounded when read, and removed after the check. Player stdout and
  stderr are not forwarded to application logs.

## Playback defaults

The process uses `--no-config`, `--hwdec=auto-copy`, `--hr-seek-framedrop=no`,
`--no-resume-playback`, and a 15-second network timeout. The HLS options
`http_persistent=0,http_multiple=0` preserve the user's earlier working setup.
Their effect is empirical; these changes do not establish a CDN root cause.
No fixed User-Agent, Origin, Referer, signed stream URL, or token is embedded.

## Verification

Run the usual checks with `./scripts/check.sh`. The default suite covers
framing, invalid messages, invalid commands, missing executables, early child
exit, and cancellation during startup with actual process cleanup.

Run the optional real-player tests with:

```sh
BAKA_MPV_INTEGRATION=1 swift test --package-path Packages/BakaKit
```

These tests require an installed mpv with VapourSynth. They check capability
probing, IPC, pause, duplicate start, idempotent stop, restart, cancellation,
and loading and seeking a generated local WAV file with a quoted file name.
They require no service credentials or network streams. The WAV check validates
IPC media control, not video rendering or SVP.

## Remaining work

- SVP processing has been verified on a generated local 24 fps video at approximately
  60 fps with SVP 4.7.2.325 and mpv 0.41.0 on Apple Silicon. A live Kinopub HLS
  episode also confirmed H.264/AAC playback with SVP at 23.98 → 59.94 fps.
  Long-session stability still needs verification. Concurrent SVP sessions have not
  been exercised; the app advertises only its own player.
- Experimental browser media discovery and per-file User-Agent/Referer are now
  available; see [Kinopub browser](kinopub-browser.md). One live Kinopub episode has been verified with video and audio; cookie transfer
  is not implemented. Long-session stability remains unverified. No integrated native video UI,
  track selection, persistence, automatic stream recovery, or Shikimori updates.
  Kinopub website sign-in and playback are described in
  [Kinopub browser](kinopub-browser.md).
- Position is read on demand. Property subscriptions and a playback event stream
  will be added with the actual playback session and tracking use cases.
- Forced application termination cannot run orderly async cleanup. Normal Quit
  waits for the current diagnostic task; forced-quit recovery remains separate.
- Verification targets the local Apple Silicon configuration.

## Primary references

- [mpv stable manual: JSON IPC, commands, properties, and options](https://mpv.io/manual/stable/).
- [SVP mpv integration: VapourSynth, IPC, and copy-back decoding](https://www.svp-team.com/wiki/SVP:mpv).

## Browser stream verification

The primary Kinopub HLS source is read from the video source element and passed
unchanged over IPC. Browser-derived User-Agent, Origin and Referer are per-file
options. Loading waits for file-loaded or an error event with a cancellable
60-second startup deadline; ordinary commands retain their two-second limit.
One live episode was verified with simultaneous H.264/AAC playback, advancing
position and SVP interpolation at 23.98 → 59.94 fps. Startup took nearly one minute.
Intermittent CDN TLS timeouts were observed; long-session stability is unverified. See [Kinopub browser](kinopub-browser.md).

## SVP integration

The Kinopub SVP switch is enabled by default and saved locally. It applies to the
next playback session. The app checks for SVP Manager and mpv VapourSynth support,
starts Manager without activating it, and after file-loaded confirms video, advertises
its private IPC socket as
`/tmp/mpvSockets/<child-pid>`. SVP follows this symlink using its supported
mpvSockets discovery convention. The directory must be owned by the current user,
be a real directory, and disallow group/other writes. Existing links are never
replaced. Stop removes only this session's registration after stopping its child;
`/tmp/mpvsocket` and global mpv/SVP settings are untouched. Deferring registration
until video loads prevents SVP from classifying a slowly opening HLS player as
non-video and ignoring it. Forced termination may
leave a stale registration and private directory; orderly Quit removes them.

For Homebrew VapourSynth R81, the child receives `VSSCRIPT_PATH` pointing to
`libvsscript.dylib` in the installed Python package. Legacy Homebrew library paths
and an existing valid environment override are supported. No libraries are copied
or installed by the app.

Every two seconds, the browser playback status reads the enabled `@svp` VapourSynth
filter, source frame rate and filtered output frame rate. Active requires output
above input by more than 0.5 fps; a connected filter alone is shown separately.
Paused playback can retain the most recently measured rates. The diagnostic
headless check never advertises a socket or enables SVP.

For an opt-in check, start SVP Manager and provide a local video longer than its
minimum duration (normally 15 seconds). For example, generate a fixture with the
optional ffmpeg tool:

```sh
ffmpeg -f lavfi -i testsrc2=size=640x360:rate=24 -t 25 -c:v libx264 -pix_fmt yuv420p /tmp/baka-svp-test.mp4
BAKA_SVP_INTEGRATION=1 BAKA_SVP_TEST_MEDIA=/tmp/baka-svp-test.mp4 swift test --package-path Packages/BakaKit --filter SVPIntegrationTests
```

This waits 30 seconds with an idle player to cover slow startup, opens a real mpv
window, waits for an increased filter output rate, checks
that playback advances, and stops its own player. Default tests cover registration
ownership/collisions and distinguish disabled, connected and processing filters.

References: [SVP's mpvSockets recommendation](https://www.svp-team.com/wiki/SVP:mpv)
and [mpvSockets discovery naming](https://github.com/wis/mpvSockets).
