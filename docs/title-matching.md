# Shikimori to Kinopub title matching

## User flow

Use Open in Kinopub beside a title in Watchlist or Catalog. The row context menu
also provides Open in Kinopub and Change Kinopub Match. Opening the title text
continues to show its Shikimori progress/rating editor.

A saved match opens the configured Kinopub mirror immediately. Otherwise the app
loads Shikimori details, searches Kinopub by the original title and its Russian,
English, Japanese, licensed and synonym titles, and ranks the resulting cards.
Searches use a separate WebKit view sharing the existing Kinopub website data
store. Cookies stay in WebKit; the visible website and playback are not replaced
until a destination is selected.

A unique exact normalized title with matching release year, a Shikimori TV type,
and exactly one discovered Kinopub season can open automatically. Punctuation,
case, width and accents are normalized; numbers and season markers are retained.
Missing metadata, multiple exact matches, multiple seasons and incomplete searches
require confirmation. Movies and other formats currently require confirmation.

Choose a candidate, inspect its title/year and select a season or Title page,
then choose Save Match and Open. This opens the destination website page without
starting mpv or updating Shikimori progress. A linked concrete episode can then
save its local playback position in Continue Watching. Start its web player to discover the
stream, then choose Play Episode in mpv as before.

If needed, expand Alternative title or manual match. Find Alternative Titles on
Google opens a normal browser search. Check that the alternative belongs to the
same anime, enter it in Alternative title, and choose Search Again. The app does
not currently scrape Google or automatically extract aliases from search results.
A Kinopub title URL from the configured mirror can also be selected manually;
the app inspects its title and seasons before saving the item ID. Query strings,
credentials, streaming URLs and playback tokens are not saved in a mapping.

No result means no confirmed match, not proof that the anime is absent. There is
no negative cache. Change Kinopub Match bypasses a saved mapping and lets you
replace the title or season.

## Boundaries and storage

- Catalog owns AnimeIdentity. The existing ShikimoriSharp detail model supplies
  aliases and release year; no upstream fork is needed.
- Kinopub owns the catalog port, title models and the website adapter. The adapter
  reads the real search form, submits its query parameter, follows up to five
  result pages per query and deduplicates cards by numeric item ID. It checks
  same-origin HTTPS, rejects credential-bearing URLs and detects login pages.
- Matching owns normalization, candidate ranking and confirmed EpisodeMapping
  persistence. Up to twelve distinct title queries are attempted. Limits produce
  an incomplete status, never an assertion that the title is absent.
- The website adapter bounds page startup to 20 seconds and each fetch to 15
  seconds. Closing the sheet cancels startup/fetch work. Network, expired-login,
  unsupported-markup and local-storage failures are displayed separately from
  an empty search result.
- Confirmed mappings are an atomically replaced JSON array in Application Support
  under BakaThreesome/episode-mappings.json. Only Shikimori ID, Kinopub item ID,
  season and an episode offset reserved for later use are stored. No complete
  website URLs are persisted. Corrupt storage is reported rather than overwritten.
  This small mapping store is separate from future playback/history persistence.

Season numbering and episode offsets across split cours, specials and franchise
collections are not inferred. Multi-season cards need the user's season choice.
Saved matches can become stale if Kinopub removes or reorganizes a title; use
Change Kinopub Match to replace them. Automatic playback progress remains separate.

## Verification

The default checks exercise alias fallback, title normalization, ambiguity,
missing/wrong years, multi-season cards, partial search results, errors,
cancellation, mapping persistence and malformed records. Synthetic .NET checks
verify that all detail aliases and the release year survive the bridge.

Opt-in real WebKit DOM checks use a nonpersistent browser with synthetic HTML
and intercepted fetch responses; no service credentials or network are needed:

```sh
BAKA_WEBKIT_INTEGRATION=1 swift test --package-path Packages/BakaKit --filter CatalogReaderTests
```

They cover duplicate title links, adjacent text nodes, pagination, season links
and options, expired login and unexpected redirects. The running app was checked
with a real Watchlist title: Kakegurui resolved to its Kinopub card, both seasons
were offered, season one was saved and opened, and a repeat action reused the
saved mapping. This check did not start playback or change Shikimori progress.
