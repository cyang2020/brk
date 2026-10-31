# Profiles, incognito, scoped data removal and their restart receipts

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Finish the data-lifecycle rows. The sites-extensions slice delivered real clearing; the parent's independent review found the after-restart assertions prove localStorage only (`verify/completion/sites-extensions-parent/review`, finding EV1).

A042: add post-restart receipts, in native scenarios, for host, domain and HttpOnly cookies, IndexedDB, Cache Storage, service-worker registrations and the HTTP cache, plus survival of an unrelated origin and of another profile, for both Clear Cookies and Refresh and Clear Cache and Refresh. A093: prove profile-scoped extension catalog, pins and enable state; storage classes beyond cookies per profile; active download ownership when a space is reassigned to another profile or the profile is deleted; clear-data separated from deletion; keep the initialization readiness and incarnation and focus protections. A094: closing and reopening the last private window resets every storage class without quitting (fixture proof exists; extend it), define and test active-download behavior when the private context expires, and run a disk and diagnostic-log audit for private titles and paths after quit with the exact audited set stated. A095: implement the active-protected-operation clear-data matrix natively (clear during an active download, a pending output, an open Find, a frozen page), implement profile-wide origin-storage deletion through an origin index or the request context, or state the exact unsupported scope in the UI; two profiles and unrelated origins; truthful privacy controls in settings with correct scope labels instead of a History button.

Owned paths: `Sources/BrkCEF/{SiteData,CEFProfiles}.swift`, the request-context lifecycle parts of `Sources/BrkCEF/CEFEngine.swift`, `Sources/BrkDomain/Rules/{Profiles,Library}.swift` clear-data rules, the clear-data UI in `Sources/BrkLibrary` and `Sources/BrkSettings`, and your new `DataScenarios.swift`. `WebsitePolicy.swift` and `Extensions.swift` belong to extensions-sites; add only additive hooks there and list them.

## Owned feature acceptance

### A042 Clear cookies or cache and refresh

Clear Cookies and Refresh and Clear Cache and Refresh delete the explicitly scoped data in the originating profile, wait for completion, and reload only the still-valid target page.

Current assessment: partial.
- Parent review: after-restart assertions prove localStorage only. Cookies, HttpOnly/domain cookies, IndexedDB, Cache Storage, service workers, HTTP cache and unrelated origin/profile survival need post-restart receipts in the merged native run before verified.

Current behavior: Actual host/domain/all-path cookie removal, HttpOnly handling, context-wide HTTP-cache deletion, immutable preflight, partial results and guarded refresh are implemented.

Existing pointers: `Sources/BrkBase/Sites.swift`, `Sources/BrkDomain/Rules/SitePolicies.swift`, `Sources/BrkCEF/SiteData.swift`

### A093 Profiles

Spaces can use independent profiles with isolated cookies/storage, Favorites, search, archive/download preferences and extensions; reassignment/deletion cannot leak old context callbacks.

Current assessment: partial.
- Complete profile-scoped extension management, and test storage classes beyond cookies.
- Fix active download ownership on reassignment/deletion and separate clear-data from deletion.
- Keep initialization readiness and incarnation/focus protections.

Current behavior: Profile dialogs/Favorites/settings and persistent CEF contexts work; custom-profile cookie separation is tested. Extension behavior is absent.

Existing pointers: `Sources/BrkDomain/Rules/Profiles.swift`, `Sources/BrkDomain/Rules/Library.swift`, `Sources/BrkCEF/CEFEngine.swift`, `Sources/BrkCEF/CEFProfiles.swift`, `Vendor/CefSwift/Sources/CefKit/CefProfile.swift`

### A094 Incognito window

Incognito uses off-the-record contexts; no private tabs/history/archive/download metadata persist, private links/popups retain context, last-window disposal resets the private session, and explicitly downloaded files may remain.

Current assessment: partial.
- Verify close-last-private/reopen without quitting resets cookies and other storage.
- Define active download behavior when the private context expires.
- Audit diagnostic logs and all relevant disk storage before claiming broadly no saved data; ChromePage currently logs titles/download paths as public.

Current behavior: Private scratch trees/context and metadata omission work with preserved native privacy fixes.

Existing pointers: `Sources/BrkDomain/Rules/Windows.swift`, `Sources/BrkDomain/Rules/Tabs.swift`, `Sources/BrkDomain/Rules/Library.swift`, `Sources/BrkDomain/Codec.swift`, `Sources/BrkCEF/CEFEngine.swift`, `Sources/BrkCEF/ChromePage.swift`

### A095 Privacy and clear browsing data

Per-profile privacy controls and confirmed Clear Browsing Data remove only the requested data classes/scope, report completion/errors, work for default/custom profiles, and do not delete a live profile as a side effect.

Current assessment: partial.
- Design explicit clear-data requests and completion separately from unused-profile deletion and private-context expiry.
- Implement cookie/cache/storage/history selection with scoped completion and restart proof.
- Test two profiles and unrelated origins; protect active operations and retain profile records/settings.
- Provide actual privacy controls rather than a History button with misleading scope.

Current behavior: History clearing now removes only Brk visits and is labeled Clear History. It no longer calls profile disposal. Full scoped Cookie, cache and site-storage removal remains unimplemented.

Existing pointers: `Sources/BrkDomain/Rules/Library.swift`, `Sources/BrkApp/AppStore.swift`, `Sources/BrkCEF/CEFEngine.swift`, `Sources/BrkCEF/CEFProfiles.swift`, `Sources/BrkLibrary/LibraryPages.swift`, `Vendor/CefSwift/Sources/CCef/include/include/capi/cef_request_context_capi.h`

## Deliverable

Commit implementation, production tests, native scenarios (names start with `Data`) and evidence under `verify/completion/batch2-privacy-data/REPORT.md`. Include `proposal.json` with exactly the assigned IDs (A042, A093, A094, A095), truthful final status, remaining work and repository-local evidence for the parent, in the shape of the existing `verify/completion/batch-tabs/proposal.json`. Do not edit the canonical inventory. Final reply: PASS, ISSUES or BLOCKED; starting and final commit; changed files; actual commands and results; limitations; clean-worktree status. No PR or publishing.
