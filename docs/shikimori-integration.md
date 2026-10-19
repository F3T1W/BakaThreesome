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
uses a fixed-size placeholder without blocking the title list. A poster metadata
error offers Reload Posters. Metadata and decoded images are shared between views;
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
