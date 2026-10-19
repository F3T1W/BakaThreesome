# Shikimori catalog and tracking

The native app uses ShikimoriSharp by JustRoxy through a private .NET child process.
The adapted source, original MIT license, source commit and patch list are in
[Vendor/ShikimoriSharp](../Vendor/ShikimoriSharp/PATCHES.md).

## Available behavior

- Public ranked catalog and submitted title search, 30 entries per page.
- Signed-in anime lists: Watching, Planned, Completed, On Hold, Dropped and Rewatching.
  All Lists combines statuses; each page contains up to 50 entries.
- Opening a title loads its current user rate before enabling edits.
- Add a title, set an absolute watched episode count, change status, and rate 1–10.
  Unrated sets the score to 0. A successful save refreshes the watchlist.
- Statuses and scores change only after an explicit Save. Automatic watched counts
  are opt-in, use confirmed episode numbering and a persistent account-bound outbox.
  Progress-only updates preserve ratings and statuses; automatic completion, remote
  version conflict resolution and custom named playlists are not implemented.
- Continue Watching stores local linked-episode positions independently of watched counts.
  See [Automatic progress](automatic-progress.md) for threshold, retry and gap handling.

These lists are Shikimori status lists, not Kinopub playlists or collections.
The REST endpoints used here are supported but documented as deprecated by
Shikimori. Poster metadata uses public GraphQL through the same ShikimoriSharp
transport and rate limits. Requests batch up to 50 distinct IDs and select the
`main2xUrl` derivative; account tokens are not needed for artwork.

Catalog, Watchlist and Continue Watching share a responsive native thumbnail grid.
Each card shows the poster with its title underneath; details/progress, Kinopub
matching and continuation actions remain available. Missing or unavailable artwork
uses a fixed-size placeholder without blocking the title list. Missing artwork is
distinguished from metadata/image request failures. Failed posters offer Reload
Posters for the current page or Reload Poster in a card context menu.
Metadata and decoded images are shared between views;
HTTP responses also use a dedicated URL cache. No credentials or browser cookies
are attached to image requests.

The poster field is described in the [Shikimori GraphQL schema](https://github.com/shikimori/shikimori/blob/master/app/graphql/types/poster_type.rb).

## Local sign-in

1. Open [Shikimori applications](https://shikimori.io/oauth/applications) and create
   an application named `BakaThreesome`.
2. Use redirect URI `urn:ietf:wg:oauth:2.0:oob` and the `user_rates` permission.
3. In Settings > Accounts > Shikimori, enter the client ID and secret locally.
4. Choose Authorize in Browser, approve access on Shikimori, then paste its
   authorization code into the app and choose Connect Shikimori.

The client name is also the required HTTP User-Agent. The browser receives only
the client ID, redirect URI, response type and scope. The secret and code are
sent in the token request body to Shikimori, never in command-line arguments.
The manual authorization-code flow follows the service's documented OOB flow;
it does not use an automatic URL callback.

The complete client credentials, access/refresh token pair, expiry and profile
are stored in the login Keychain under the separate `shikimori-session` item.
Tokens are refreshed before expiry. Concurrent callers share rotation; a failed
Keychain write retains the rotated pair in memory so retrying persistence does
not consume another refresh token. Tokens are persisted before profile lookup.
Sign Out waits for a pending refresh, then removes this app's local credentials.
It does not revoke the OAuth grant remotely. Revoke access on Shikimori separately.
Do not put credentials or authorization codes in repository files or chat.

## Process boundary and failure behavior

Xcode's Embed Shikimori Helper phase publishes the .NET helper and license notices
into `Contents/Resources/Bridge`. Xcode's `TARGETNAME` environment variable is
removed for MSBuild to preserve distinct assembly names. The current development
build requires a local .NET 10 runtime; this is not a standalone distribution.

Swift owns one lazy process per ApplicationServices instance. JSON lines over
private stdin/stdout pipes carry version, UUID request ID, method and parameters.
The transport serializes requests off MainActor, frames partial reads, verifies
response IDs, limits request/response sizes, and bounds I/O to 25 seconds. HTTP
requests have a 15-second timeout and share the library's rate limit buckets.
Redirects/cookies, secret logging, implicit refresh and implicit write retries
are disabled. Errors exposed to the UI use fixed messages, not server bodies.

Navigation may cancel reads and stop their helper. Token operations and writes
finish once started so returned tokens or mutation results are not discarded
just because a view closes. Application shutdown waits for active account/save
operations and then stops its helper. A failed/uncertain write disables another
save until current progress is reloaded; it might already have reached the server.
Concurrent edits from other clients are not versioned: explicit saves use the
server's normal last-write behavior.

## Verification

`./scripts/check.sh` runs language checks, .NET builds, fake-HTTP adapter checks,
helper protocol recovery, and Swift tests. Shikimori tests cover numeric IDs,
protected writes, response correlation, safe errors, corrupt storage, refresh
coalescing, rotated-token persistence retry, logout during rotation, and real
pipe framing/process restart using a local synthetic helper.

Public search and unauthenticated anime details were verified against the live
API on 2026-10-18 through the packaged helper. Native catalog search, signed-out
tracking sheet and account settings were also checked in the running app.
Real OAuth authorization, private lists, and create/update on a user's account
remain unverified until credentials are entered locally. Contract tests use only
synthetic tokens and do not alter any remote account.

References: [official OAuth guide](https://shikimori.io/oauth),
[API documentation](https://shikimori.io/api/doc).

## Attribution in version control

The README and app credits retain the upstream link and author. A suitable commit
subject is `feat(shikimori): integrate ShikimoriSharp by JustRoxy`; include the
upstream URL and exact revision in its body. A commit alone does not notify the
author. Use Co-authored-by only for actual coauthorship. No public fork or upstream
message has been created as part of this integration.

## Poster loading resilience

A dedicated actor coalesces image downloads by URL and permits at most six active
requests globally. Extra requests wait outside URLSession, so queue time does not
consume their network timeout. The session also limits connections per host to six.
Thumbnail decoding and pixel caching use ImageIO off MainActor, with a 640-pixel
maximum dimension and a 64 MiB decoded-image cache. URLSession keeps its HTTP cache.
Requests carry no account credentials or browser cookies.

Image timeouts, temporary connection failures, HTTP 408/429 and 5xx responses retry
twice with backoff. Backoff releases the request slot so healthy images can proceed.
Retry-After is respected for waits up to a minute; longer waits require a later manual
retry. Permanent HTTP errors and invalid image data are surfaced without automatic
retry. Failed HTTP responses and invalid image bodies are evicted from the HTTP
cache so a manual retry does not keep receiving a cached error. Failed results
are never cached as a missing poster. Transient poster-metadata
requests also retry twice; a failed batch cannot clear another batch's error.

View cancellation removes its subscription. A shared image continues for remaining
consumers; when the last consumer disappears, queued or active work is cancelled.
Reloading a failed image at the same URL changes only that card's retry token rather
than cancelling every image whenever shared metadata changes. Error banners refer
only to the current page's titles. Metadata loading, confirmed missing artwork and
request failure have separate presentation states. A network/decode failure shows
Could not load poster; No artwork is reserved for a successful null-poster response.

Swift tests exercise real ImageIO decoding of generated PNGs with synthetic image
transport: parallel bounded loading, URL deduplication, cached reuse, retries after
timeout/503, Retry-After, permanent failures, cancellation/slot reuse, and retrying an
unchanged image URL through the view model. These checks do not alter remote accounts.

ImageIO validates the actual image bytes even when a CDN sends a generic
Content-Type. On 2026-10-19 the rebuilt Catalog rendered live posters and its
Reload Poster context action was exercised. The restarted app requested Shikimori
sign-in for private lists, so the private-list live check was not completed.

## Session recovery

Startup restores the saved account from Keychain without requiring a network
request. A missing item shows the sign-in form. A read or decoding failure shows
Could Not Restore Shikimori in Watchlist and Session unavailable in Accounts,
with a retry action. The saved item is preserved; a failed read is not treated as
an absent account. Forget Saved Session remains an explicit user action.

Watchlist reads, progress-detail reads and Check Session retry once after an
unauthorized response, using a refreshed token pair. Concurrent requests share
token renewal; a delayed rejection of an older token reuses the current pair.
Repeated rejection, refresh failure and network errors remain visible and never
silently delete the saved account. Mutations are not replayed automatically by
this recovery path. Check Session also updates and persists the account profile.

Regression tests cover recovery after a temporary Keychain read failure, a failed
new authorization while an unread session exists, rejected tokens, concurrent
renewal and restoration of the rotated pair by a new account service. A live
normal Quit and relaunch restored the existing Watchlist without reauthorization
on 2026-10-19. Forced token revocation and a locked login keychain have not been
exercised against the real account.
