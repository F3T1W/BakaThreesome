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
`http_persistent=0,http_multiple=0` remain the compatibility baseline. HTTP(S)
`.m3u8` sources use full stream probing and the compatibility baseline by default.
The experimental reduced-probing profile remains an explicit source option for
controlled tests; normal app playback no longer opts into it.
See [Startup latency](#startup-latency) for fallback and validation.
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
  is not implemented. Long-session stability remains unverified. There is no integrated native video UI.
  Native track selection and explicit stream recovery are available. Opt-in Shikimori updates and local linked-episode
  position persistence is implemented; see [Continue Watching](continue-watching.md).
  Kinopub website sign-in and playback are described in
  [Kinopub browser](kinopub-browser.md).
- Playback position is sampled every two seconds for local resume checkpoints.
  Property subscriptions and a playback event stream remain future work.
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
starts Manager without activating it if it is not already running, and once
file-loaded or a subsequent snapshot confirms video, advertises
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

## Startup latency

The app warms its capability cache in the background. Concurrent callers share a
probe, successful results are keyed by resolved executable path, modification date
and size, and replacement binaries trigger a new check. Version and filter-list
probes run concurrently. Failures remain retryable and Quit cleans up probes.

On Play, mpv starts while SVP preparation runs concurrently. An already running SVP
Manager is reused. `force-window=immediate` creates the player window during media
opening instead of hiding it until demuxing completes. Headless checks still use
`force-window=no`. Browser pause and User-Agent lookup share one WebKit evaluation.
The status distinguishes process startup from media readiness and includes elapsed
time. Numeric phase timings use the `PlaybackStartup` log category, without URLs,
headers or credentials. The process/IPC timing starts at the playback action and includes WebKit source
preparation and cleanup of a previous player;
media timing includes any remaining SVP preparation. It is not a first-frame metric.

Network HLS sources use full stream-info probing with persistent/parallel HLS
connections disabled by default. The original master manifest and its track
choices remain intact. The earlier experimental reduced-probing profile timed
out on a live multi-track manifest and is no longer selected by normal app
playback. Explicit experimental sources still have one compatibility reload after
a load rejection or two seconds without the expected decoder metadata.
For linked episodes, fast mode waits for both video and audio before reporting
success. Compatibility mode retains the existing video-only warning behavior.
The reload preserves resume offset, Origin, Referer, User-Agent and external audio.
Cancellation stops the owned player, including while opening a stream.

Run controlled HTTP HLS and installed-player checks with:

```sh
BAKA_HLS_INTEGRATION=1 BAKA_MPV_INTEGRATION=1 ./scripts/check.sh
```

The HLS fixture requires `/opt/homebrew/bin/ffmpeg`, Python 3 and installed mpv.
It generates synthetic H.264/AAC media, serves a multi-variant VOD master on loopback
with a small response delay, and verifies video, audio, resume and advancing playback
in both probing modes. It prints timings without enforcing a fragile speed threshold.
A local result is not a guarantee about Kinopub/CDN latency. The previous live path
was observed at 47 seconds with no video/audio and a hidden window, then timed out.

References: [mpv probing and window options](https://mpv.io/manual/stable/),
[FFmpeg HLS connection options](https://ffmpeg.org/ffmpeg-formats.html#hls).

On 2026-10-19, real SVP interpolation passed after 30 seconds of idle time with
immediate windows. A live app trial reported process/IPC startup in 0.31 seconds;
its window was available while the stream was loading. That timing preceded the
addition of WebKit preparation to the reported interval. The same Kinopub stream
still hit the media-open deadline with the final fast profile: end-to-end live
video startup is not verified as improved. Controlled HLS readiness was about
0.50 seconds in both profiles in one run, so no HLS speedup percentage is claimed.
The test playback was stopped and no Shikimori data was changed.

## Retry interrupted playback

Linked episode playback now offers Retry Playback after a media-open timeout,
rejected media load, or an observed stream failure. The action stops the owned
player, reloads the exact episode page without using the local page cache and
requests its current primary manifest through the existing browser flow. The
native retry label identifies the title, episode and requested resume position.
Play from Beginning uses the same refresh flow with position zero.

Runtime monitoring retains the last good sampled position even when the failed
player reports position zero or the latest checkpoint could not be written.
The retry point exists only in memory; local Continue Watching checkpoints still
survive normal app restarts. Signed media URLs and browser credentials are not
part of the retry point. Stop, Cancel Playback, browser-session clearing and
navigation away invalidate the pending retry. A website user gesture may still
be required; the UI explains when to start the web player.

The IPC adapter retains end-file error events while reading ordinary replies.
It also treats EOF clearly before a known duration as interrupted playback:
remaining time must exceed both five seconds and 0.5 percent of the duration.
A reported failure cannot remove the resume entry or contribute watched coverage.
Closing mpv, pausing and reaching the normal end do not request a retry. Each
retry requires a click; there is no automatic player-restart loop.

The adapter cannot reliably classify a truncated stream if mpv reports normal
EOF without a usable position and duration, or changes the reported duration to
match the truncated media. Buffering without a terminal error is not classified
as a failure. Diagnostic individual-source playback remains unlinked and does
not offer episode recovery. An unavailable mirror or expired browser login must
be resolved on the website. SVP setup failures keep their existing instructions.

Tests exercise the actual IPC adapter with a synthetic child process, including
an error mixed with ordinary replies, repeated snapshots, a fresh load, normal
EOF and premature EOF. Resume tests verify that failure preserves and flushes the
last good checkpoint. Recovery destination tests cover season, episode, movie,
zero position and exclusion of signed or credential-bearing origins.

Reference: [mpv end-file events and EOF properties](https://mpv.io/manual/stable/).
EOF can also represent a broken connection; the native early-end check is a
conservative application heuristic, not proof of a particular network error.

On 2026-10-19, the full default checks and the opt-in installed-mpv and synthetic
HTTP HLS suite passed after these changes. These tests validate local adapter
behavior; they do not prove recovery from every Kinopub CDN failure.

A live linked Kinopub attempt on the same date reached its media-open timeout.
Retry Playback appeared for Kakegurui S01E02 at 1:22. Clicking it reloaded the same
episode page, discovered the primary manifest again and started a new player
attempt. Cancel Playback stopped that attempt, removed the pending retry and
retained the 1:22 checkpoint. Successful video recovery on that CDN and sustained
playback after a real mid-episode interruption remain unverified. No Shikimori
list entries were changed by the short startup trial.

## Stream diagnosis and compatible defaults

The Kinopub panel includes a collapsed Stream Diagnostics section. Check Stream
compares a bounded browser fetch with an ephemeral URLSession request using the
same User-Agent, Referer and Origin, without transferring browser cookies. It
checks the master and at most 24 unique video/audio playlists in batches of four.
For each media playlist it samples the segment covering the requested resume
position. Segment reads are capped at 4 KiB. It then opens the stream in a paused,
headless diagnostic mpv using the selected-program startup path, with a
35-second media-open deadline. This player does not
register with SVP or record progress. The requested start position and language
preferences match the pending recovery point or saved episode. Browser and native
master probes fail independently; a browser fetch failure no longer skips native
HTTP or mpv diagnosis. Cancel Playback and Quit cancel the probe.
These are samples; they do not verify every rendition or segment.

The report includes HTTP statuses, timing, HLS track counts, codec presence and
allowlisted mpv network categories/host names, event counts and a bounded timeline
of the latest 24 distinct consecutive events. Counts are log observations, not
HTTP request counts. It never displays response bodies,
signed paths, queries, cookies, authorization headers or arbitrary mpv log text.
Bodies and addresses remain in memory, samples are bounded, and native sessions
have no URL cache or credential storage. Ordinary players do not enable debug
log messages. Navigating clears the old report.

On 2026-10-19, the tested episode's master contained three variants, fifteen audio
renditions and one subtitle rendition. Browser and URLSession master/track reads
returned HTTP 200; segment samples returned HTTP 206 in under about 1.3 seconds.
An experimental complete-master probe reached its 35-second deadline. Full
probing with compatibility connections opened video and audio in a headless
check in 19.73 seconds. A normal linked app run without SVP then confirmed video,
audio and advancing resume position, ready in 25.50 seconds. These are individual
observations with dynamically routed CDN responses, not a controlled speed ratio.
They do not establish a particular FFmpeg internal defect.

Player snapshots now tolerate temporary IPC response timeouts while filters
initialize, within the existing 20-second startup readiness budget and a
15-second monitoring budget. These budgets bound retries; a command already in
flight is still bounded by its own timeout. Each individual IPC command retains
its two-second limit. Disconnects and cancellation are immediate. A sustained timeout stops
the owned player and preserves the retry point. Startup errors identify their
phase so media-open timeouts can be distinguished from filter/readiness failures.

After bounded IPC timeout handling was added, a linked Continue Watching run with
SVP enabled confirmed simultaneous video/audio and active interpolation at
23.98 → 59.94 fps, ready in 26.03 seconds. It resumed the existing episode position,
advanced normally and was stopped through the app. This is a short live success,
not a whole-episode stability result or a guarantee about future CDN routing.

## Audio and subtitles

During playback, the Kinopub panel shows native Audio and Subtitles selectors.
They switch the current mpv tracks through IPC without loading the episode again.
Track labels use the language and title, including HLS rendition comments when
mpv exposes them. Duplicate labels include a track number for this session.

The initial preference is Japanese audio with Russian subtitles. Full subtitles
are preferred over forced subtitles. If Japanese audio is unavailable, the current
mpv audio remains selected. If Russian subtitles are unavailable, subtitles stay
off and the panel explains the fallback. Other original languages can be selected
manually; Japanese is a default preference, not inferred original-language metadata.

A successful manual choice saves its language and rendition name in local
UserDefaults. Track IDs and stream addresses are never saved as preferences.
The next episode first applies per-file language options, then matches the saved
rendition name among tracks of that language. Numbered rendition prefixes are
ignored when matching names. If that rendition is missing, another track in the
same language is used. Off is remembered separately. The reset button restores
Japanese audio and Russian subtitles. Keyboard changes in mpv refresh the app's
selectors without overwriting the saved preference or forcing a switch back.

Track polling and switching failures are nonfatal to playback. Selectors are
cleared on stop, and delayed replies cannot update a later player session.
The optional `TrackSwitchingIntegrationTests` generate a local MKV with Japanese
and Russian audio plus English and Russian subtitles using Homebrew ffmpeg.
They verify defaults, live switching, Off and unchanged playback position.

## Optional opening skip

When mpv exposes chapters, the app recognizes explicitly labelled OP, Opening,
Opening credits or Intro chapters. The next chapter supplies the end boundary;
unlabelled chapters, missing ends, invalid ordering and ranges outside 5–300
seconds do not create a skip action. No assumed 90-second opening is used.
The app reads mpv's documented `chapter-list` title/time metadata:
[mpv chapter properties](https://mpv.io/manual/stable/#properties).

For media with a recognized range, Show Skip Opening controls button visibility
and is remembered locally. Skip Opening appears only while playback is inside
that range and seeks to its known end after rechecking the live position. It never
skips automatically. Skipping interrupts watched-coverage sampling before and
after the seek, so the skipped interval is not counted toward Shikimori progress.
Stop and a new player session invalidate pending actions and marker state.

Many HLS sources expose no named chapters. In that case the controls stay hidden;
there is no Kinopub marker extractor, external timing-service lookup or inferred
opening duration. A generated local MKV with real chapters verifies discovery and
seeking through the installed mpv; absence of markers on a real stream is not
proof that the episode has no opening.

## Controlled HTTP interruption check

With `BAKA_HLS_INTEGRATION=1`, HLSRecoveryTests generates a local video/audio HLS
stream and serves it on an ephemeral loopback HTTP port. After real mpv begins
playing, a fixture switch makes subsequent segment requests return HTTP 503.
The test requires a failed-media snapshot rather than successful completion,
checks that the failed snapshot cannot erase the last resume checkpoint, and
reopens the actual disk history through a new store instance. It then restores
HTTP service, starts a new player with a refreshed URL and the saved start offset,
and requires video/audio plus advancing playback from that position.

The check does not change the Mac's network settings, terminate unrelated players,
use service credentials or make Shikimori mutations. It complements the normal-EOF,
startup cancellation, delayed IPC and account-bound progress tests; it does not
prove every Kinopub/CDN failure mode or long-session SVP stability.

Combined local checks:

```sh
BAKA_MPV_INTEGRATION=1 BAKA_HLS_INTEGRATION=1 BAKA_WEBKIT_INTEGRATION=1 ./scripts/check.sh
```

### Live stability sample on 2026-10-19

A bounded live Kinopub check encountered three 60-second media-load timeouts before
player readiness: the first S01E02 startup, a subsequent S01E03 transition, and
S01E03 Continue after a full application restart.
Retry Playback recovered S01E02 with a freshly discovered stream in 26.07 seconds,
restored Japanese audio/Russian subtitles and confirmed SVP at 23.98 to 59.94 fps.
Across three IPC observations over 40 seconds, time-pos advanced from 397.79 to
437.80 seconds at speed 1.0, paused-for-cache stayed false and decoder-frame-drop-count
stayed zero. These measurements cover only that short recovered playback interval.

Retry Playback also recovered S01E03 in 20.00 seconds with Japanese audio,
Russian subtitles and active SVP. After normal Stop at approximately 0:59 and a
full application restart, Continue Watching displayed only S01E03 for this anime.
Its approximately 0:59 position was retained, but the first real stream startup
after that restart also timed out; a successful live resume from this new restart
was not verified in this run. The local HLS restart/resume check did pass.
Timeout recovery preserved the local episode position and kept the application
responsive. At this checkpoint, the repeated live startup timeouts remained a release limitation; the
controlled local HLS test does not explain or eliminate their remote cause. This
is not evidence of a full-episode or multi-hour stability pass.

The current built executable is arm64 and ad-hoc signed (no TeamIdentifier); local
`codesign --verify --deep --strict` passes. The helper still launches through an
installed .NET host, and mpv/SVP are external. These facts describe the development
artifact, not a signed/notarized distribution package or a clean-Mac installation
check. Packaging and release validation remain separate work.

### Follow-up startup investigation on 2026-10-19

The master returned HTTP 200 in 0.11 seconds through WebKit and 0.46 seconds
through URLSession. Sampled child playlists returned HTTP 200 in 0.12 to 0.98
seconds; sampled segments returned HTTP 206 in 0.19 to 0.28 seconds. These samples
cover only two child playlists and do not establish that all media is available.

With the saved 59.33-second offset, the paused diagnostic player opened video and
audio in 27.70 seconds. Its allowlisted timeline recorded a network timeout and
segment-open failure at 27.58 seconds, followed by another media-open event and
file-loaded. A second run recorded the same sequence around 27.88 seconds and
loaded in 27.96 seconds. Both used the complete master; a proposed quality-program
reduction did not apply to the live manifest. That experiment was removed rather
than added to normal playback.

This narrows the fault to remote-media startup: mpv can encounter a segment
read/open timeout while loading this HLS graph. The master fetch and initial IPC
startup are not the slow stages in these samples. A local segment failure/recovery
check passes, but neither sample reproduced the entire previous 60-second failure
or proves whether CDN routing, transport behavior or a particular rendition is the
underlying cause. SVP was absent from both probes, so it is not required for this
startup delay. At that stage, these results did not yet justify changing playback defaults.

At that checkpoint, intermittent first-attempt media startup still blocked release
readiness. The following investigation compared transport/probing alternatives and
selected-program loading while preserving audio/subtitle tracks and the saved position. Packaging and publication are explicitly on hold at the user's
request; stop and notify the user before starting that stage.

### Selected-program startup validation on 2026-10-19

All 18 sampled video/audio playlists and their resume-position segment samples
responded quickly through URLSession. Both compatible and concurrent connections
still hit the 35-second diagnostic deadline in mpv. Disabling HTTP ranges and
limiting stream analysis also failed to resolve the delay. Those experimental
transport/probing modes were removed from the application.

The real master also contains I-frame trick-play variants. The earlier strict
reducer rejected that tag and therefore always retained the original master.
The selector now recognizes and omits optional I-frame trick-play entries while
keeping the highest-bandwidth normal video variant. It reduces only when every
referenced quality group offers an equivalent set of audio/subtitle/caption
renditions; language, studio/name, channels and characteristics remain significant.
Numbered display prefixes and default/auto-selection flags may differ between
otherwise equivalent groups. Unique voices, incomplete group references,
unsupported tags, malformed attributes or insecure child URLs retain the original
master. Full stream probing and compatible HTTP connections remain enabled.

The selected master is passed through private mpv IPC as an in-memory data URI.
It is never written to a file, command-line argument or diagnostic report. Explicit
lavf/HLS demuxing preserves the alternate tracks. Loading starts paused when a
saved offset exists; an exact seek is issued, the previous pause state is restored,
and the target position is confirmed with allowance for elapsed playback time. Out-of-range offsets continue through the existing resume error
path. The playback model retains its one-time original-master fallback if an
optimized load is rejected or video/audio metadata does not become usable.

On the previously affected S01E03 stream, the headless selected-program probe
loaded in 5.71 seconds, retained six renditions from one of three quality programs,
selected Japanese audio and Russian subtitles, and reported position 59.35 seconds
for a 59.33-second request. This is a bounded live observation, not a guaranteed
startup time for every CDN or title.

The real-mpv local fixture includes two video programs, alternate Japanese/Russian
audio groups, Russian WebVTT subtitles and a saved offset. It checks track selection,
audio switching, position preservation and reloading the original master in the
same player after selected-program loading. Pure parser checks cover I-frame tags,
unique voices, malformed attributes, unknown tags and unsafe child addresses.

The initial normal-player trial loaded S01E03 with SVP in 6.68 seconds and the
S01E04 transition in 3.60 seconds. Two numeric observations over 20 seconds showed
position advancing from 23.40 to 43.40, speed 1.0, no cache pause, zero decoder-frame
drops and approximately 59.94 output fps. Japanese audio and Russian subtitles
remained selected. These are short runtime samples.

A subsequent cold resume exposed a separate confirmation defect: after 18.96
seconds the application rejected startup even though a later numeric trace showed
the exact saved position (257.631254 seconds) with `seeking=true`. That flag may
remain set pending the first rendered/filter frame. Requiring it to clear before
SVP registration created a false failure. Position confirmation now checks the
restored position rather than waiting for that first-frame flag. Resume property,
seek and pause requests also tolerate temporary IPC timeouts within a shared
15-second budget; cancellation and disconnects still propagate immediately.
A synthetic IPC regression keeps `seeking=true` at the correct position and delays
several replies beyond the individual two-second request limit. It requires
successful resume with the prior transport state restored.

After correcting the first-frame flag check, the exact previously failing cold
resume at 257.631254 seconds completed in 4.55 seconds with Japanese audio, Russian
subtitles and SVP active at 23.98 to 59.94 fps. Three IPC observations across one
minute showed position 258.566583 → 288.562998 → 318.576111, speed 1.0, no cache
pause, zero decoder-frame drops and approximately 59.94 output fps. This validates
that resumed playback actually advanced after confirmation; it is not a whole-
episode or multi-hour stability claim.

The final combined local check matrix passed, including real mpv/HLS failure and
recovery, alternate-track selection, original-master fallback, delayed IPC replies,
WebKit, bridge checks and the English-only project scan. The opt-in Keychain write
check was not enabled. Distribution packaging, clean-Mac installation, signing and
notarization remain the next stage and were not started.

A further full application restart resumed the newer S01E04 checkpoint in 4.14
seconds with the same language selection and active SVP. Normal Stop saved its
position, and Continue Watching still displayed a single card for the anime.
Test playback was stopped. No package, repository commit, push or release was created.
