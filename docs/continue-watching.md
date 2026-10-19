# Episodes and Continue Watching

## Use

1. Open a Shikimori title with Open in Kinopub from Watchlist or Catalog. Confirm
   its title and season if asked. This associates the website with a Shikimori ID.
2. Use the native Episode picker or the website to open the concrete episode.
   The native context label shows the linked title and SxxExx. Only the linked
   item and season can record progress for that Shikimori title.
3. Start the web player if its stream is not ready, then choose Play Episode in
   mpv. The app pauses the main-frame web video before starting mpv.
4. Stop playback or quit normally. Continue Watching shows the episode and its
   saved position. Continue reopens that exact episode and requests its current
   primary manifest before passing the saved position to mpv.
5. If the website requires a user gesture, start its web player. The pending
   Continue action then launches mpv automatically once the primary stream is
   available. Navigating elsewhere or choosing Cancel Playback cancels this action.

Play from Beginning is available in the episode controls and the Continue
Watching row context menu. Remove from Continue Watching deletes only that local
entry and is disabled while that episode is playing. Failed startup preserves
existing progress. If the saved position is outside a changed version's duration,
choose Play from Beginning; the app does not silently discard the old entry.

The arrow buttons beside the native Episode picker play the previous or next
numbered episode. They stop and checkpoint the current player, refresh the chosen
page and launch its primary stream, using that episode's own saved position when
available. Audio/subtitle preferences and the SVP setting apply to the new player.
Playback starts only after the refreshed page provides its primary manifest; a
website play gesture may still be required. Cancel Playback cancels this preparation.

Destinations must be discovered on the current page and belong to the linked item
and season. Gaps and season boundaries disable the corresponding button; the app
does not guess a URL or skip to a different season. While a linked episode is
playing, the buttons are disabled if the browser shows a different episode or
title. Return to the playing episode or stop playback to navigate from that page.
This is manual navigation; reaching EOF does not automatically start another episode.

Movies opened on their linked base title page can be tracked as one movie.
Unlinked website browsing, other seasons, arbitrary diagnostic streams and pages
without a concrete episode are playable but do not record Shikimori-associated
progress. Open the title through Catalog/Watchlist and correct its season match
when needed. The app does not guess split-cour offsets or watched episode counts.

## Implementation

EpisodeContext captures Shikimori ID/title, Kinopub item ID, season and episode.
A ResumeRecorder is created for one mpv session and retains that immutable context.
Browsing another website episode cannot relabel an already playing session.
Episode links are extracted only from the current main-frame document; the native
picker performs a full navigation. History playback uses only the main-frame
video source's same-origin primary manifest, not resource-timing or iframe matches.

SwiftDataResumeStore keeps its ModelContext on an actor and saves explicitly.
The local database is Application Support/BakaThreesome/playback.store; SQLite may
also create companion journal files. It stores episode identity, numeric position,
duration and update time. No media URL, website query, cookie, header, OAuth token
or password is part of the history schema. Confirmed title mappings remain in
their separate episode-mappings.json file.

The player is sampled every two seconds. Changed progress is saved at most every
five seconds during ordinary playback, immediately on a sampled pause transition,
and on Stop, replacement playback or normal Quit. If the player closes externally,
the last sample is flushed. A crash or forced quit may lose progress since the
last successful checkpoint; closing mpv can lose up to a polling interval.
Storage failures leave playback running and display a retry warning. Failed writes
remain eligible for retry with the latest sample.

Resume time is a per-file mpv start option delivered over private JSON IPC. It
cannot carry over to another file. keep-open preserves EOF information long enough
for polling; EOF removes the local continuation entry. This is a local navigation
state, not proof of watched content. Seeking to the end can also reach EOF.
Automatic Shikimori updates use separate watched-coverage and delivery policies;
local EOF handling alone never triggers them.

## Verification

Adjacent-navigation tests cover previous/next boundaries, missing episodes, foreign
items and seasons, movies, and browsing away from the playing episode. A live
Kakegurui S01E02 to S01E03 transition launched video/audio with Japanese audio and
Russian subtitles. The reverse transition required a real website play gesture
before continuing automatically with S01E02's saved start position.

The default suite covers real SwiftData memory/disk persistence, explicit restart,
stale-write protection, per-episode separation, checkpoints, pause, flush, EOF,
invalid snapshots and failed-write retry. URL tests reject ambiguous destinations
and build episode links without query tokens. The optional installed-mpv suite
verifies start offsets and EOF using generated local media:

```sh
BAKA_MPV_INTEGRATION=1 swift test --package-path Packages/BakaKit
node scripts/check-episode-discovery.mjs
node scripts/check-media-discovery.mjs
```

The JavaScript checks cover episode filtering/deduplication, rescanning and a
single web-player activation per pending Continue action. A live linked episode was played with video/audio and SVP. Navigating the browser
from S01E02 to S01E03 did not change the playing episode's saved identity. After
Stop and a full application restart, Continue Watching retained S01E02 at 0:42.
Continue reopened that episode; this mirror needed one real web-player gesture,
then mpv launched automatically with a measured position of 42.25 seconds.
The test player was paused and stopped after verification. Long-session stability and full
crash-recovery scenarios remain unverified.

Reference: [mpv playback control and EOF properties](https://mpv.io/manual/stable/).

Optional watched-count synchronization is independent of resume positions. See
[Automatic Shikimori progress](automatic-progress.md) for explicit numbering and delivery.
