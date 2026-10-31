# Website controls, data, permissions and extensions

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Complete C6 scoped clear-data preflight/ordering/results, effective website appearance/theme CSS, profile/private storage lifecycle acceptance, site control center, native permission prompts and policy persistence, actual network/cosmetic/cookie-banner blocking and exceptions, per-site keep-alive/suspension policies, plus real extension install/manage/remove/actions/pinning/popups/shortcuts. Probe the pinned Chrome runtime and actual supported APIs; raw command names and a chrome:// page alone are not action-button/permission/runtime evidence. Use harmless local extensions and deterministic fixture servers. Implement a real supported local/store installation flow, per-profile policy and private policy; verify extension popup lifetime/input/shutdown. Extension shortcuts coexist with the one Brk/page priority table. All callback answers are one-shot, bound to browser/document/frame/origin/context incarnation, and cancelled on invalidation. Clear-data is different from profile disposal: preflight host/domain/origin and global cache scope honestly, preserve unrelated origins/profiles/active operations, wait for actual completion, and verify restart. Scope theme injection/removal to live documents with opt-out cleanup. Keep-alive/suspension must affect actual page scheduling; media/PiP-specific behavior may depend on later media implementation and must remain explicit. Main focus: BrkCEF site policy/resources/context/extension adapters, BrkBase operation vocabulary, domain SitePolicies/Extensions rules, BrkSettings and site-control/prompt/picker views. Browser output and Find belong to other slices. Dedicated scenarios use SitePolicy/Extension names.

## Owned feature acceptance

### A042 Clear cookies or cache and refresh

Clear Cookies and Refresh and Clear Cache and Refresh delete the explicitly scoped data in the originating profile, wait for completion, and reload only the still-valid target page.

Current assessment: missing.
- Define host/domain/origin scope, including domain cookies; URL-only cookie deletion is narrower than all site cookies.
- Wrap asynchronous completion, context identity and errors; cache clear is context-wide in the raw API.
- Prove another profile and unrelated site data survive, including navigation/close races.

### A043 Website appearance

Automatic/light/dark appearance affects actual websites, Easels and Notes, follows the system in automatic mode, and persists with defined profile scope.

Current assessment: missing.
- Connect an engine appearance policy and verify CSS prefers-color-scheme changes on real pages.
- Determine whether request-context set_chrome_color_scheme supplies the required website behavior; test rather than assume.
- Apply equivalent behavior to Easels/Notes when implemented.

### A065 Theme colors for websites

Expose the current space theme to eligible webpages as CSS only when enabled and update it on theme or space change.

Current assessment: missing.
- Define CSS names, document lifetime, opt-out cleanup and private-context behavior with platform ownership.

### A093 Profiles

Spaces can use independent profiles with isolated cookies/storage, Favorites, search, archive/download preferences and extensions; reassignment/deletion cannot leak old context callbacks.

Current assessment: partial.
- Complete profile-scoped extension management, and test storage classes beyond cookies.
- Fix active download ownership on reassignment/deletion and separate clear-data from deletion.
- Keep initialization readiness and incarnation/focus protections.

### A094 Incognito window

Incognito uses off-the-record contexts; no private tabs/history/archive/download metadata persist, private links/popups retain context, last-window disposal resets the private session, and explicitly downloaded files may remain.

Current assessment: partial.
- Verify close-last-private/reopen without quitting resets cookies and other storage.
- Define active download behavior when the private context expires.
- Audit diagnostic logs and all relevant disk storage before claiming broadly no saved data; ChromePage currently logs titles/download paths as public.

### A095 Privacy and clear browsing data

Per-profile privacy controls and confirmed Clear Browsing Data remove only the requested data classes/scope, report completion/errors, work for default/custom profiles, and do not delete a live profile as a side effect.

Current assessment: partial.
- Design explicit clear-data requests and completion separately from unused-profile deletion and private-context expiry.
- Implement cookie/cache/storage/history selection with scoped completion and restart proof.
- Test two profiles and unrelated origins; protect active operations and retain profile records/settings.
- Provide actual privacy controls rather than a History button with misleading scope.

### A096 Install and manage

Users can install/manage/remove extensions through a supported store/local flow and management UI in Brk, with per-profile persistence, permissions, error reporting and correct private policy.

Current assessment: missing.
- Probe a harmless unpacked extension and chrome://extensions on pinned Chrome runtime after embedding.
- Verify installation confirmation, reload/restart, enable/disable/remove and profile/private isolation.
- No old load_extension/get_extensions API exists in these pinned headers; choose supported contracts after experiments.

### A097 Extension buttons and picker

Installed extension actions appear in a native picker/toolbar with per-profile pinning and usable popup/permission UI whose windows close safely.

Current assessment: missing.
- Prove a supported extension-action enumeration/invocation path and popup ownership.
- Implement native picker/pinning UI, profile/private scope and keyboard/teardown tests.
- get_chrome_toolbar only supplies a CEF view when toolbar is enabled; it does not prove a native Brk extension API.

### A098 Extension shortcuts

Extension command shortcuts can be inspected and configured per profile and coexist with Brk/page priorities, with duplicate and reserved-key handling.

Current assessment: missing.
- Probe chrome://extensions/shortcuts and actual installed command dispatch in hidden-toolbar host.
- Define extension vs page vs Brk priority and editable/native-window behavior without changing Downloads default.

### A107 Site control center

A site control popover shows the active origin/profile, effective permissions/settings and actions for Boosts, capture, copy URL and local file export with current readback.

Current assessment: missing.
- Design effective per-origin settings state and asynchronous update/error reporting.
- Connect popover to existing copy/export and future permission/Boost/capture work; verify navigation and private scope.

### A108 Site permissions

Native site prompts for camera, microphone, location and notifications show the correct origin/capability, support allow/deny/dismiss and settings readback, respect OS permissions, and cannot resolve stale prompts for a new page/profile.

Current assessment: missing.
- Wrap retained asynchronous callbacks with prompt/frame/origin/mask/context/incarnation identity and one-time resolution/release.
- Implement native prompt UI, persistence policy and cancellation on navigation/close/profile change.
- Validate built app/helper permission metadata, signing and actual OS allow/deny behavior.
- Treat desktop capture separately from device access; default Chrome permission bubbles are not a verified fallback.

### A109 Ad blocker

Built-in ad/tracker blocking and cookie-banner handling use defined rules, profile/site exceptions and updates, block relevant requests/cosmetic content and preserve normal navigation.

Current assessment: missing.
- Implement request filtering at correct callback/thread boundary, rule loading/update/error behavior and site exceptions.
- Implement cosmetic/cookie-banner behavior separately from network blocking.
- Verify main/subframe/subresource/redirect cases and profile/private isolation with deterministic fixtures.

### A110 Per-site behavior rules

Per-site keep-alive, PiP and suspension-exclusion rules have explicit matching/profile/private scope and affect real scheduling/media behavior without interrupting protected operations.

Current assessment: missing.
- Define and implement policy rules plus actual consumers; existing loaded-tab set is not suspension.
- Verify active media/download exemptions, navigation/profile change, persistence and private rules.

## Deliverable

Commit implementation, production tests, native scenarios and evidence under `verify/completion/batch-sites-extensions/REPORT.md`. Include `proposal.json` with exactly the assigned IDs, truthful final status, remaining work and repository-local evidence for the parent. Do not edit the canonical inventory. Final reply: PASS/ISSUES/BLOCKED, starting/final commit, changed files, actual commands/results, limitations, and clean-worktree status. No PR or publishing.
