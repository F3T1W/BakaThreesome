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

- SVP discovery is based on application files, not active interpolation.
  VapourSynth availability is a build capability, not proof that its runtime
  plugins or SVP processing work on a video.
- SVP socket discovery/configuration still needs a dedicated experiment.
  The private diagnostic socket is intentionally not registered with SVP.
  Concurrent SVP playback is not implemented.
- Experimental browser media discovery and per-file User-Agent/Referer are now
  available; see [Kinopub browser](kinopub-browser.md). One live Kinopub episode has been verified with video and audio; cookie transfer
  is not implemented. Long-session stability and SVP remain unverified. No integrated native video UI,
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
One live episode was verified with simultaneous H.264/AAC playback and advancing
position. Intermittent CDN TLS timeouts were observed; long-session stability and
active SVP interpolation are still unverified. See [Kinopub browser](kinopub-browser.md).
