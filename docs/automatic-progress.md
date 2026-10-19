# Automatic Shikimori progress

## Use

1. Connect Shikimori in Settings > Accounts and add the title to Watching.
2. Enable Automatically sync watched episodes in Settings > Progress. It is off by default.
3. Open the title from Watchlist or Catalog, choose the correct Kinopub season and episode.
4. In the Kinopub panel, enter the corresponding Shikimori episode number and choose
   Confirm Numbering. The confirmed offset applies to this account, anime, Kinopub
   item and season. For example, Kinopub episode 13 can map to Shikimori episode 1.
5. Play the linked episode in mpv. At least 90% of its unique timeline must be
   observed playing normally across player sessions. Partial coverage is saved
   locally for this account and confirmed episode mapping. Local resume positions
   remain independent.

Numbering is deliberately explicit: a title association alone does not prove how
split cours, combined seasons or specials are numbered. Reconfirm when correcting
an offset. Existing pending entries retain their original absolute number; discard
an incorrect entry in Settings > Progress before correcting its association.

## Counting and delivery

The playback monitor samples about every two seconds. Tracking compares media
position changes with elapsed monotonic time and playback speed. It merges
played intervals, excluding pauses, idle/audio-only states, reported seeking,
large jumps, repeated scenes and observation gaps longer than six seconds.
Changing media duration resets coverage. Sampling is conservative and cannot
prove every frame was displayed; small seeks between samples may be undetectable.
Reaching EOF or seeking to the end alone never completes an episode.

Partial coverage is checkpointed at most once every five seconds while it changes,
on sampled pause/EOF and when playback is stopped, replaced or shut down normally.
`~/Library/Application Support/BakaThreesome/watched-coverage.json` stores merged
numeric intervals, duration, account, title/episode identity, confirmed Shikimori
number and update time. No stream address, cookie, header or credential is saved.
A crash can lose coverage since the last successful checkpoint.

Restoration never restores the previous timing sample: the first new sample only
establishes a baseline. Overlapping replayed intervals count once; resume offsets
and seeks cannot fill unobserved gaps. Account, item, season, episode or confirmed
number changes select separate records. A duration change larger than 0.5 seconds
resets coverage for that media version. Corrupt archives are preserved and block
restoration until repaired; failed writes remain retryable. Turning sync off stops
new observations; already saved intervals are retained for later re-enabling.

After reaching the threshold, the app atomically records an account-bound intent
in `~/Library/Application Support/BakaThreesome/progress-sync.json`. The file also
stores confirmed numbering rules. It contains no streams, cookies or credentials.
Failed disk writes retry during playback. A watched episode is not considered
queued until its atomic write succeeds. Corrupt files are reported and preserved.

Delivery fetches current authenticated anime details first. It updates only an
existing rate in Watching, only when this is the next consecutive episode and
within the known episode count. Unknown totals are allowed. Missing rates, gaps,
other list statuses, invalid numbering and Rewatching wait for manual action.
Ratings and statuses are never sent by the progress-only PUT. The app does not
automatically complete a title or create a rate.

If the server already has that episode or a higher count, the entry is acknowledged
without another PUT. This also reconciles a lost response after an applied write.
The adapter never uses the increment endpoint. Manual saves and automatic writes
share the account model's mutation lock. Started writes finish during shutdown;
new deliveries stop. No remote version/CAS is available here: another client's
concurrent episode edit between GET and PUT can still conflict. Statuses and
ratings are unaffected because they are omitted from the PUT entirely.

Updates retry every minute while the app is open, enabled and signed in, on account
changes, and with Retry Now. They survive relaunch and remain bound to the original
user ID. Signing in as another user never sends the previous user's entries.
Disabling automatic sync pauses delivery; already started writes may finish.
Discard removes only the selected local pending intent and does not change Shikimori.

## Verification

Swift tests exercise unique coverage, seeking/pauses, repeated scenes, speed,
invalid samples, numbering offsets and account/season isolation, atomic outbox
round trips, cross-session restoration, coverage archive account/number isolation,
corrupt data preservation, blocked deliveries and retry after a lost
response. Synthetic bridge transport verifies read-before-write reconciliation,
protected mutations, numeric IDs and that a lost response does not increment twice.
An optional installed-mpv test plays generated local video in real time and verifies
that actual speed/seeking snapshots reach the coverage threshold. Run it with
`BAKA_MPV_INTEGRATION=1 swift test --package-path Packages/BakaKit --filter TrackingTests`.
This check and the native Progress settings layout were verified on 2026-10-19.
The .NET fake-HTTP check asserts that the actual ShikimoriSharp request body has
exactly one `user_rate` property: `episodes`.

Real OAuth progress mutations are not part of these checks; no user's Shikimori
list is modified for validation. Use the normal Settings flow for a live opt-in
trial with the next episode of a title in Watching.

The presentation-model test watches 50% in one instance, reopens its disk journal
and coverage archive, watches a further 40%, and verifies that exactly one pending
intent appears only at 90%. Its Shikimori transport is synthetic and offline.
