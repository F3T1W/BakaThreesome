# ShikimoriSharp integration

Based on [JustRoxy/ShikimoriSharp](https://github.com/JustRoxy/ShikimoriSharp),
commit `85491770f5e001eed2f266a9c5c5a6286fdd9c02` (MIT).
The original MIT license and attribution are preserved in LICENSE and shipped with the helper.

This is a vendored local adaptation, not a published GitHub fork. BakaThreesome
calls ShikimoriSharp through the .NET helper; it does not reimplement its API in Swift.

Local changes:

- Use shikimori.io, the current canonical API and OAuth host.
- Encode GET settings in the query string and serialize nested write settings as JSON.
- Correct v2 user-rate object responses and increment/delete HTTP methods.
- Accept long rate IDs and filter anime lists by status.
- Inject and reuse HttpClient, disable redirects and cookies, and bound request time.
- Remove token/body logging, implicit refresh and automatic request retries.
  Swift owns session rotation and Keychain persistence; writes are never retried implicitly.
- Replace the timer-based token bucket with a bounded sliding window.
- Update dependency versions and remove the unused Polly dependency.
- Keep the original netstandard2.1 target; suppress legacy nullable warnings in vendor code only.

Future changes should remain isolated here and be covered by the helper contract checks.
Any upstream contribution or public fork is a separate action.
