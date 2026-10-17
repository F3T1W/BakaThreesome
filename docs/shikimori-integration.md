# ShikimoriSharp Integration

Inspected on October 17, 2026, at upstream commit
`85491770f5e001eed2f266a9c5c5a6286fdd9c02`.
This was a static source review. The library was not built and no requests
were made using a user account.

## Decisions and integration proposal

- Application name: BakaThreesome.
- ShikimoriSharp is the selected integration foundation; a fork is acceptable
  when required.
- Swift remains the preferred UI language. The library is written in C# and
  targets netstandard2.1; it cannot be imported directly as a Swift Package.
- Proposed approach: a small .NET child process running ShikimoriSharp,
  communicating through JSON over stdin/stdout. This integration is not
  verified yet. It requires process management, an error protocol,
  architecture-specific builds, and a .NET runtime distribution strategy.
  NativeAOT compatibility with the current dependencies is not confirmed.
- The interface remains native. A local HTTP server is unnecessary for this
  bridge. Swift owns Keychain access. Secrets must not appear in process
  arguments or diagnostic output.

## Findings in the source

- Anime search and details: `Information/Animes.cs`.
- OAuth code exchange and token refresh: `AuthorizationManager.cs`;
  token updates are exposed through `OnNewToken` in `ApiClient.cs`.
- Reading, creating, and updating user entries:
  `UpdatableInformation/UserRates.cs`; the `episodes` field is defined in
  `Settings/UserRateSettings.cs`.
- Rate limiting: `ApiClient.cs` specifies 5 requests per second and
  90 requests per minute. These are implementation values, not an independent
  verification of the current API rules.
- License: MIT, Copyright (c) 2020 JustRoxy.

The presence of these methods does not establish compatibility with the current API.

## Potential fork changes

1. Confirmed in the source: `ApiClient.RequestTokenRefreshing` logs the refresh
   token at Information level. Remove the secret value before enabling regular
   application logging.
2. Verify user rate contracts: methods for fetching one entry, creating an entry,
   and updating an entry deserialize arrays. Compare them with current API responses.
3. Verify HTTP methods: `Increment` and `DeleteUserRate` do not specify a method
   explicitly, while the low-level client defaults to GET. Check the documentation.
4. Verify token refresh handling: the implementation refreshes after both 401
   and 400 responses. The inspected methods do not coordinate concurrent refreshes.
5. Verify retries for modifying requests: the shared retry policy covers network
   errors. Prefer setting an absolute episode count and reading the state back;
   retrying an increment could apply the change twice.

Items 2 through 5 require contract verification and reproduction before changing
upstream code. The library has not been modified in this workspace, and no GitHub
fork has been created.

## Attribution

The README contains permanent acknowledgments with upstream links. When bundling
the dependency, include its license in third-party notices and add application
credits. A suitable integration commit subject is:

`feat(shikimori): integrate ShikimoriSharp by JustRoxy`

Include the upstream URL and exact revision in the commit body. A commit message
does not notify the author by itself. Contacting the author or sending a PR requires
an explicit user request. Use Co-authored-by only for actual coauthorship.

## Next checks

1. Verify documented OAuth and user rate contracts, remove secret logging, and
   check deserialization against sanitized responses.
2. Exercise a small Swift to .NET to ShikimoriSharp search call and verify child
   process termination. Account requests and progress writes need separate checks.
3. Address the main playback risk first: retrieve a fresh Kinopub stream through
   the API, launch mpv, and confirm SVP. Kinopub documentation requires application
   client_id/client_secret credentials issued by support. An account subscription
   alone does not confirm that these credentials are available.

## Sources

- [Inspected source revision](https://github.com/JustRoxy/ShikimoriSharp/tree/85491770f5e001eed2f266a9c5c5a6286fdd9c02).
- [License](https://github.com/JustRoxy/ShikimoriSharp/blob/85491770f5e001eed2f266a9c5c5a6286fdd9c02/LICENSE).
- [Documented Kinopub authentication](https://kinoapi.com/authentication.html).
- [mpv process control and JSON IPC](https://mpv.io/manual/stable/).
- [SVP requirements for mpv](https://www.svp-team.com/wiki/SVP:mpv).

IINA documentation contains a historical example of SVP with libmpv, but
[Use SVP with IINA](https://github.com/iina/iina/wiki/Use-SVP-with-IINA)
was edited in 2020. It establishes that this approach existed, not that a future
BakaThreesome build will work on current macOS versions.
