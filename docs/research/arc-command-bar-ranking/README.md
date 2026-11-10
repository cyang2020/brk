# How Arc 1.170 orders the command bar's suggestions

This is a research note. It changes no product code. Everything was read from Arc 1.170.0 (build 89123):

- the arm64 slice of `/Applications/Arc.app/Contents/MacOS/Arc`, which this note calls "the binary";
- `ArcCore.framework`;
- a header file that ships inside `ArcCore.framework`;
- the user's Arc data folder (structure and counts only);
- the real Arc, driven on 2026-11-10.

Addresses are virtual addresses in the binary's arm64 slice. Scripts are in `tools/` (see the last section).

## Summary

**The ranking in use is hand-tuned, not a trained model.** Arc's command bar is ranked by a scorer in the Swift module `ASE2`.
- The scorer has fixed weights that ship inside the binary. They can be overridden by a JSON file that only a debug window writes.
- For each query it turns 21 features of every candidate into z-scores across that query's candidates.
- It averages the z-scores with weights, first inside 6 categories and then across the categories.
- It adds 14 kinds of boosts into that same weighted average.

All weights, boost values and missing-feature values are recovered exactly (`ase2-defaults.json`).

**The trained model is present but unused.** The on-device model the brief found (`LocalCommandBarRanking`, `rankCommandBar`, `trainCommandBarRanking`) is in the binary.
- Nothing in Arc's command bar calls it.
- It would run inside an AI service library that Arc downloads. That library is not installed on this machine, and no model files exist.
- The same binary carries Dia's AI service URLs (`*.diabrowser.engineering`). This code is most likely shared with Dia, The Browser Company's other browser.

**What "learns" in Arc.** Arc keeps a small usage file (`StorableCommandBarAdditionalRanking.json`). From it, one boost uses how often each command was run. Arc also reads Chromium's history signals: visit count, typed count, last visit, site engagement and the most-visited rank.

**The debug window can't be opened on this account.** It sits in the Developer menu. Arc shows that menu only to accounts on The Browser Company's own email domains, and to a "qa" access level that this research did not trace. No setting was changed, so nothing had to be reverted. Instead, the order the real Arc shows was recorded for 11 queries.

## 1. The pipeline, from a keystroke to the rows

### Known (from the binary)

**Request.** Each keystroke updates `CommandBar.CommandBarState.query`. The command bar then calls `CommandBar.SearchClient.search`, passing a `CommandBar.InputWithContext` (field lists are in `tools/swiftfieldtypes.py` output; the types are in `__swift5_fieldmd`). That carries an `ASE2.Input` with these fields:
- `query`;
- `sourceTypes`;
- `maxSuggestions`;
- `configuration`, which holds the weights;
- `preferredMaxRankConfig`;
- `derankCurrentItemURLEnabled`;
- `dedupByTitleAndHostList`;
- `tidyTabTitles`;
- `scopedSearchType`;
- `timeoutValue`.

The context around it adds `currentItemInfo` (the current tab's id and URL), `isFirstSearch`, `destination`, `typeTravelContext` and `featureFlags`.

**Candidate sources.** `SearchClientManager.SearchClientManager` keeps one candidates provider per `ASE2.SourceType`. There are 13 source types:

| Source type | Provider type in the binary | What it supplies |
|---|---|---|
| `sidebar` | `SidebarCandidatesProvider` (caches tabs per window and global, and tab titles) | open tabs, including Favorites and pinned tabs |
| `chromium` | `ChromiumCandidatesProvider` | Chromium's omnibox (the Chromium address bar) results (see the archetypes below) |
| `topDomains` | `TopDomainsCandidatesProvider` | Arc's popular-sites list |
| `searchOrNavigateWhatYouTyped` | `SearchOrNavigateWhatYouTypedProvider` | Arc's own "search/open what you typed" row (gated by `searchWhatYouTypedProviderEnabled`) |
| `documents`, `easels` | `DocumentsCandidateProvider`, `EaselCandidatesProvider` | Arc notes and Easels |
| `typeTravel` | `TypeTravelCandidatesProvider` (a snapshot of the main menu) | commands: menu items, settings panes, spaces, folders, extensions, split actions and so on (35 kinds in `ASE2.TypeTravelCandidate`) |
| `askGPT` | `AskGPTCandidateProvider` | the "Ask ChatGPT" row (gated by `isGPTArchetypeEnabled`) |
| `instantLinks` | `InstantLinksCandidateProvider` | Arc's instant links |
| `recentAssistantQueries`, `onboardingSuggestions`, `staticQuerySuggestions`, `memorySearch` | (no provider type found) | other sources; not used for normal typing |

**Timing.** The signpost names `ArcSignpostName.CommandBarType` are `syncSearch`, `prepareRankingPipeline`, `asyncRank`, `fetchBrowserHistory` and `endToEnd`. Together with `candidateProviderSync` / `candidateProviderSearch` and `SearchClientManager.TimeoutError`, they show two passes: the fast local sources first, then a ranking pass once Chromium's history answers or the timeout passes. The exact timeout value was not read.

**The archetype.** The archetype is what a candidate *is*: which kind of row it is and what choosing it does. `ASE2.Archetype` has 12 cases:
- `chromiumArchetype`, `navigateWhatYouTyped`, `searchWhatYouTyped`, `askGPTWhatYouTyped`;
- `tab` (`TabInfo`: tabID, url, originalURL, title, customTitle, isVisible, savedContext, containerID);
- `document`, `easel`, `typeTravel`;
- `topDomain` (url, siteName);
- `instantLinks`, `askAssistant`, `assistantHistory`.

`ASE2.ChromiumArchetype` has 9 cases:
- `chromiumSearchWhatYouTyped`, `chromiumNavigateWhatYouTyped`;
- `chromiumSearchSuggestion`, `chromiumSearchHistory`;
- `chromiumNavigateSuggestion`, `chromiumHistory`;
- `chromiumSearchOtherEngine`, `chromiumSearchCalculatorAnswer`;
- `chromiumBookmark`.

So Chromium's own autocomplete supplies:
- the typed search and the typed URL;
- the engine's suggestions;
- history pages;
- past searches;
- bookmarks;
- the calculator.

Each archetype has a base value in the configuration (see section 3). That base value is the first feature.

**Candidates.** A candidate is `ASE2.Candidate { sourceInfo, archetype, featureScores: [Feature: Double] }`. The output is `ASE2.Output { input, allSuggestions: [Suggestion], responseTime }`. Each `ASE2.Suggestion` is `{ archetype, sourceInfo, score, debugInfo }`, where `debugInfo` holds `features`, `perFeatureScores`, `perCategoryScores` and `boosts`.

**Merging duplicates.** Duplicates merge by `ASE2.DedupKey`, which has these cases:
- `search(query)`;
- `normalizedHumanReadableURL`;
- `titleAndHost(title, host)`;
- `tab(id)`, `document`, `easel`, `project`;
- `typeTravel(id)`;
- `custom`.

`titleAndHost` applies only to hosts on the server list `dedupByTitleAndHostList`. The copy on this machine is `~/Library/Application Support/Arc/RemoteAssetDirectory/CommandBarRemoteConfiguration_*`, and it lists figma.com, maps.google.com, notion.so, zoom.us, opentable.com, zillow.com, github.com, app.mode.com and console.cloud.google.com. Which duplicate wins was not traced.

**Other inputs.**
- `ASE2.AdditionalFeatureInfo` passes these into ranking: `mostVisitedRank` (Chromium's most-visited URLs, in order), `siteEngagementScores` (origin to score), `recentlySwitchedToTabs`, `queriesToSelectedArchetypes`, `currentItemInfo`, `typeTravelUsage` and `menuItemIDsToBoost`.
- `SearchClientManager.ProfileSpecificState` caches `mostVisitedSites` and `siteEngagementScores` per profile.

**Rows built and rows shown.** `CommandBar.SearchOutput` is `{ query, maxCountToDisplay, suggestions }`. The ranked list is longer than what is shown (see section 5).

**Fixed places.** There are no hard-coded positions in the scorer. The rows that are usually on top get there through boosts (section 3). These include Chromium's default match, an exact domain, an exact word of a title, a Favorite and a just-used tab.

The exceptions found are:
- `preferredMaxRankConfig`, which holds an optional Int per archetype (23 fields). Its default values were not recovered.
- `derankCurrentItemURLEnabled`, together with `currentItemInfo`, which pushes the current tab's own URL down. The exact rule was not read.

### Seen in the real Arc (section 5)

- Exactly 5 rows are drawn. The accessibility tree held 6 to 15 rows behind them, so the built list is longer than the 5 drawn.
- The first row is selected.
- The input shows an inline completion only when the first row is a site whose host starts with the typed text:
  - "githu" → github.com, with the GitHub Favorite as row 1;
  - "yout" → youtube.com;
  - "wiki" → wikipedia.org.
- No completion appears when row 1 is a search, a command or a tab matched by a word of its title. The input's leading icon follows row 1 (magnifier, globe or the command's icon).

**Inline completion (partly known).** `CommandBar.CommandBarAutocompleteSuggestion` is `{ query, autocompleteString, iconType, faviconURL, highlightedIndex, archetype, iconColor }`. The completion is tied to one archetype, which matches the "first row" behaviour seen. Where `autocompleteString` comes from was not traced.

## 2. The features

There are 21 features (`ASE2.Feature`, in this order), and every one is a `Double`. The table below has these columns:
- **missing** is the value used when a candidate lacks the feature (table at `0x10378e6b0`, read by `0x101d76a94`, filled in by `ASE2/Candidates+MissingFeatures.swift` code at `0x101d3ab1c`).
- **dir** is the direction. "low" means lower raw values are better, and the z-score is negated (bit mask `0x54924` in `0x101d76e48`; the same set as mask `0xab6db` in the normaliser at `0x101d3e74c`).
- **category** is where the feature's weight lives.

| # | feature | missing | dir | category | meaning (names are from the binary; the units come from the missing values) |
|---|---|---|---|---|---|
| 0 | archetype | 0 | high | its own (weight 35) | the archetype's base value from the configuration |
| 1 | urlMatchScore | 0 | high | match | how well the query matches the human-readable URL |
| 2 | urlMatchPosition | 30 | low | match | where in the URL the match starts (characters) |
| 3 | urlMatchPercentage | 0 | high | match | share of the URL covered by the match |
| 4–6 | titleMatchScore / Position / Percentage | 0 / 30 / 0 | high / low / high | match | the same three measures against the title |
| 7–9 | hotWordsMatchScore / Position / Percentage | 0 / 30 / 0 | high / low / high | match | the same three measures against "hot words" (`ASE2.SearchableProperty.hotWords`: a command's trigger phrases, a tab's words) |
| 10 | fuzzySearchConfidence | 0 | high | match | fuzzy-match confidence (`fuzzyMatchScoreCache`, `TokenizedTextMatchingInfo` in ARCFoundationBase) |
| 11 | lastNavigated | 5 184 000 (60 days) | low | recency | seconds since the last visit |
| 12 | frequencyEver | 0 | high | importance | visit count |
| 13 | typedCountEver | 0 | high | importance | typed count (Chromium's `typed_count`) |
| 14 | mostVisitedRank | 20 | low | importance | position in Chromium's most-visited list |
| 15 | siteEngagementScore | 0 | high | importance | Chromium's site-engagement score for the origin |
| 16 | globalSiteRank | 505 | low | importance | rank in Arc's popular-sites list |
| 17 | typeTravelCandidateBump | 0 | high | importance | a command's built-in `candidateBump` / `bump` |
| 18 | chromiumRank | 11 | low | chromium | position in Chromium's autocomplete result |
| 19 | chromiumRelevanceScore | 0 | high | chromium | Chromium's relevance number |
| 20 | saveLevel | 8 | low | save | how "saved" the item is (lower is more saved) |

**Known.**
- The feature list, its order, the missing values and the directions.
- The categories (`ASE2.Category`: archetype, match, importance, recency, chromium, save) and which features sit in each (`ASE2.Configuration` sections).

**Guesses.**
- The exact formulas behind the three match measures and the fuzzy confidence. The names and the "30 characters" default suggest character positions and coverage ratios.
- The saveLevel scale (Favorite, pinned, Today …). The default of 8 is "not saved".

**The trained model's inputs are different.** For comparison, the dormant trained model (section 3) would take:
- a `queryEmbedding` (the query embedded by Nomic Embed Text);
- per candidate: `id`, `archetype`, `destination`, `title`, `url`, `lastNavSeconds`, `freqEver`, `typedCount`, `siteEngagement`, `isExactURLMatch`, `isBaseDomainMatch`, `isTitlePrefix` and `titleEmbedding`.

That is a subset of the hand-tuned features plus two text embeddings. These are the "5 strings, 3 ints, a float, 3 bools and a float vector" in `arc::CommandBarRankingCandidate`.

## 3. The model and how it learns

### 3a. The ranking in use: the ASE2 weighted scorer (known)

For one query, with all candidates collected:

1. **Fill in missing features.** Any missing feature gets the "missing" value from section 2 (`0x101d3ab1c`).
2. **Normalise.** For each feature, take the mean and standard deviation over *this query's* candidates (`ASE2.Normalizer { dataByFeature: [Feature: NormalizerData { mean, standardDeviation }] }`, built at `0x101d3df80`). For a value `x`:
   - `z = (x − mean) / standardDeviation`;
   - `z = −z` for the "low" features;
   - `z = 0` when the deviation is 0 (`0x101d3e6dc`).

   Nothing is stored between queries.
3. **Score each category.** A category's score is the weighted mean of its features' z-scores, using the item weights: `Σ zᵢ·wᵢ / Σ wᵢ` (`0x101d3bb48`, which calls `0x101d81cd4`).
4. **List the boosts that apply** (`0x101d65bd8`, a switch over `ASE2.Boost`). Each applying boost adds an entry `(score, weight)`.
5. **Compute the final score.** It is one weighted mean (`0x101d81cd4`, the code from `ASE2/ScoreAndWeights.swift`: weights summed, then `Σ score·weight / Σ weight`) over:
   - the archetype z-score, with weight 35;
   - the five category scores, with weights match 2, importance 10, recency 15, chromium 25 and save 15;
   - every applying boost, with its own weight and score.

   A NaN result is logged and replaced by 0 (`0x101d3b2b8`).
6. **Sort and trim.** Rows are sorted by score, merged by dedup key and cut to the display count.

Because z-scores are usually between −2 and +2, a boost's score of 3 or 15 at weight 15 to 100 outweighs all the features. Boosts decide most first rows.

**Default weights.** These are built at `0x101d35e94`–`0x101d36070` when no saved configuration loads. They are reproduced by `tools/extract_defaults.py` into `ase2-defaults.json`.

| category | weight | items (weight) |
|---|---|---|
| archetype | 35 | base values: tab 101, list 101, project 101, document 103.5, easel 103.5, typeTravel 104, topDomains 96.1, memoryStore 105, askAssistant 106, assistantHistory 107, chromiumSearchWhatYouTyped 100, chromiumNavigateWhatYouTyped 100, chromiumHistory 100, chromiumSearchHistory 99, chromiumNavigateSuggestion 96, chromiumSearchOtherEngine 96.2, chromiumSearchSuggestion 95, searchAutocomplete 73, askGPTWhatYouTyped 2, navigateWhatYouTyped 1, searchWhatYouTyped 1, scopedSearch 1, please 1, instantLinks 1, chromiumSearchCalculatorAnswer 1 |
| match | 2 | urlMatchScore 1, urlMatchPosition 1, urlMatchPercentage 1, titleMatchScore 0.5, titleMatchPosition 0.5, titleMatchPercentage 0.5, hotWords* 1.5 each, fuzzySearchConfidence 20 |
| importance | 10 | frequencyEver 3, typedCountEver 4, mostVisitedRank 2, siteEngagementScore 2, globalSiteRank 1, typeTravelCandidateBump 1 |
| recency | 15 | lastNavigated 3 |
| chromium | 25 | chromiumRank 5, chromiumRelevanceScore 3 |
| save | 15 | level 3 |

**Default boosts.** Weight and score come from tables `0x10378e130` and `0x10378e0c0`, built at `0x101d73324`. The conditions were read from `0x101d65bd8`. The left-hand column below is the boost's weight / score.

| boost | weight / score | when it applies (known = read from code; guess = inferred) |
|---|---|---|
| exactBaseDomain | 100 / 15 | the query equals the candidate's base domain (helpers `0x101d67684` and `0x101d679c4` compare the lower-cased query, never one starting `arc://`, with the URL); the exact split between this and exactURL is a guess |
| exactURL | 40 / 3 | the query equals the candidate's URL (same helpers; guess on details) |
| exactHotWord | 100 / 15 | the query equals one of the candidate's hot words (`0x101d67dc4` compares the lower-cased query with each word): known. The words come from the candidate's archetype (`0x101d53854`), and only `typeTravel` (commands) has any, so in Arc a tab never gets this boost (read 2026-11-11) |
| baseDomain | 40 / 3 | the query matches the base domain without being exact (guess) |
| autocompleteDefault | 15 / 3 | the candidate is Chromium's default match (guess, from the name and section 5) |
| autocompleteSearchOnly | 15 / 2 | the default match is the typed search (guess) |
| chromiumSpecialSearchFunction | 40 / 3 | a Chromium row whose chromiumRank is 1, and the query looks like `word:word` but is not a known URL scheme (regex built at `0x101d67f20`, 1004 characters, `^(?!aaas?|about|…|z39\.50[rs])\w+:\w+$`): known |
| customTitlePrefix | 15 / 3 | a tab whose custom title, or a document whose title, starts with the query (lower-cased `hasPrefix`): known |
| veryRecentTabOrDocumentBoost | 15 / 3 | a tab, document or easel whose lastNavigated is under 3600 s: known |
| topApp | 15 / 3 | a tab/document/easel with a "global" saved context, which is a Favorite (Arc's code name for Favorites is "Top Apps"); the field reading is a guess |
| recentlyUseTypeTravel | 15 / 3 | a command whose `typeTravelUsage` entry has more than one recorded run: known |
| typeTravelPrefixForLongQuery | 40 / 3 | a command, query longer than 2 characters, and the command's title or trigger starts with the query: known in outline |
| unboxingPromotedAction | 40 / 3 | a command whose menu item id is in `menuItemIDsToBoost` (onboarding): known in outline |
| highFuzzySearchConfidence | 100 / 15 | fuzzySearchConfidence above a threshold (threshold not read) |

**Overrides and the fallback order (known).** The weights come from `ASE2.ASEConfigurationClient`, read in `0x101d35c38`.
1. If `StorableASEConfiguration.json` loads and its version matches, it is used.
2. Otherwise the built-in defaults are used.

Only the debug window writes that file. It does not exist on this machine, so the defaults above are what this Arc ranks with.

### 3b. The trained model: compiled in, never called

**What it is (known).**
- **Model.** `AIInfraProtocols.LocalCommandBarRanking { modelDirectory: URL, version: Int }` is a folder plus a version.
- **API.** The calls are in the shipped header `ArcCore.framework/Versions/A/Resources/arc/services/ai/public/mojom/ai_service.mojom-c_api.h`:
  - `AIService_LoadCommandBarRanking(model)`;
  - `AIService_RankCommandBar(input, candidates)`, which returns `{id, score}` per candidate;
  - `AIService_EvaluateCommandBarRanking(examples)`, which returns `{metrics: [name: Double], numExamplesEvaluated, evaluationDurationMs}`;
  - `AIService_TrainCommandBarRanking(examples)`.
- **Training examples.** A training example is `{input, candidates, selectedIndex}`. The candidate the user picked is the positive example and the others are the negatives.
- **Training result.** It holds:
  - `outcome` (completed, failed, cancelled, gated) and `failureReason` (lossNaN, **mlxError**, taskCancelled, internalError);
  - `delta: [Tensor {name, shape, data}]`;
  - `modelName`, `modelVersion` and `numSamples`;
  - `lossesPerEpoch`, `gradientNormMean`, `gradientNormMax`, `deltaNorm` and `deltaToWeightRatio`;
  - `trainingDurationMs`.

  Training runs on Apple's MLX and returns a weight *difference*, not a new model file. A result built around a weight difference, its size and the sample count is what a client sends back for averaging across users in federated learning (that reading is a guess; no upload code for it was found in Arc).
- **Where the code lives.** The service is a library that ArcCore loads at run time:
  - `AIServiceConfiguration.libraryPath` and `libraryVersion`;
  - errors `InvalidLibraryPath`, `LibraryNotFound` and `LibraryMissingRequiredSymbols`;
  - a symbol table `AIServiceSymbol` of the 19 `AIService_*` functions;
  - in Swift, `AIServiceParameters { displayName, dylibURL, version, usageType, … }`, where `usageType` is classification, llm, nomicEmbedText or commandBarRanking.

**Why it is dormant in Arc (known, from references).**
- The ObjC call sites of `rankCommandBar:candidates:completion:`, `trainCommandBarRanking:completion:`, `evaluateCommandBarRanking:completion:` and `loadCommandBarRanking:completion:` are one each, all inside the `ArcAIService` bridge (`0x100521808`, `0x100522bf0`, `0x100522208`, `0x10052107c`; `tools/stubcalls.py`).
- The bridge's Swift entry points are referenced only from the `ArcAIService: AIService` witness table (`0x1041c40b0`). That table is used only by the `createAIService` implementation (`0x1004afea4`).
- No Swift type in Arc stores an `AIService` (`tools/swiftfieldtypes.py`; only `ADKClient.createAIService`, a closure field, mentions it).
- The metadata accessors of `CommandBarRankingInput` (`0x10093976c`) and `CommandBarRankingExample` (`0x100939c40`) have no callers.
- `SearchClientManager.Dependencies` and `SearchContext` hold no AI service and no embeddings.
- On disk there is no AI service library, no Nomic model and no ranking model anywhere under `~/Library/Application Support/Arc` or `~/Library/Caches`.
- The same binary has `https://ai-service.diabrowser.engineering/aiproxy` and related URLs.

So: no shipped weights, no stored trained model, and no training or evaluation runs in Arc 1.170.

**Unknown.**
- When Dia trains, and whether `evaluate` gates a new model. The `gated` outcome exists, but the deciding code is not in Arc.

### 3c. What Arc records about the user (known)

`~/Library/Application Support/Arc/StorableCommandBarAdditionalRanking.json` (`CommandBarAdditionalRankingDataStoreClient`) has `version` 2 and `dataByProfile[profile]` with three fields:
- **`typeTravelUsage`** is a list of pairs: a command's dedup key, then `{ executed: CappedStack<Date> (maxSize 15), frequency: Int }`.
  - It is written by `executedTypeTravelAction` and pruned by `pruneTypeTravelUsage`.
  - It feeds the `recentlyUseTypeTravel` boost.
  - This user: 20 commands, run counts from 1 to 91, with up to 15 timestamps kept each.
- **`queriesToSelectedArchetype`** maps a query string to `{ archetype, selectedAt }`. It is written by `selectedArchetype` and passed in as `AdditionalFeatureInfo.queriesToSelectedArchetypes`.
  - This user has 4 entries, all commands.
  - No feature or boost reads it, and the code that consumes it was not traced.
- **`recentlySwitchedToTabs`** maps a tab to dates and is written by `switchedToTab`. This user's is empty, and its consumer was not traced.

Chromium's own data (visits, typed counts, site engagement, most visited) is read live through ADK.

## 4. The debug window and the in-row ranking info

**What exists (known).**
- `Arc.DeveloperMainMenuProvider` has two items, both backed by `SharedAppFeature.DeveloperMainMenu.State` (`commandBarRankingWindowIsOpen`, `commandBarIncludeRankingInfoInUIEnabled`):
  - "Toggle Command Bar Ranking Window" (id `toggleCommandBarRankingWindow`, string at `0x1039520b0`);
  - "Toggle Command Bar Ranking Info in Suggestion Views" (id `commandBarRankingDebugMode`, `0x103952030`).
- The window is `CommandBar.CommandBarDebugView`, titled "Command Bar Ranking Configuration" (`0x103a02890`). It has a text box with the current `ASE2.Configuration` as JSON, plus Submit and Reset. Submit saves `StorableASEConfiguration.json`.
- The in-row info is `SuggestionViewState.aseDebugInfo` / `DebugState { archetype, score, boosts }`, drawn by `archetypeAndScoreLabel` / `rankingInfoTextField`.

**Why it could not be turned on (known).**
- The Developer menu is shown by `DeveloperMenuAccessLevel` (notAllowed, employee, qa).
- "employee" means the signed-in email ends in `@thebrowser.company`, `@bcny.com` or `@latacora.com` (`0x10076f86c`, the last two decoded from mov/movk string constants). The user's account is none of these.
- How "qa" is granted was not traced.
- A user default `commandBarDebugMode` exists (`ArcUserDefaultSettings`, raw value at `0x10396bf80`), but what reads it was not traced. Trying it would have needed an Arc restart, which the rules forbid.
- No defaults, flags or files were changed, so nothing needed reverting.

Because the window could not be opened, the default weights it would show were read from the binary instead (section 3a, `ase2-defaults.json`), and the real Arc's order was recorded (section 5).

## 5. What the real Arc shows

**Method.** Each query was run under `/tmp/brk-core-native.lock`, with the top window at the press point checked to be Arc. The script (`tools/probe1.sh`) did this:
1. Bring Arc to the front.
2. Press ⌘T.
3. Type the query with human-like pauses.
4. Wait 2.5 s.
5. Capture Arc's window and read the row texts through Accessibility.
6. Press Esc twice.

No tab was opened and no setting was changed.

The pictures are cropped to the command bar and use fixture pages or public sites only. The raw accessibility dumps are not committed because they list the user's private history.

| query (kind) | row 1 | row 2 | rows 3–5 | inline completion | rows built (AX) |
|---|---|---|---|---|---|
| `visual fix` (start of an open tab's title) | search "visual fix" | open tab "Visual fixture" (Switch to Tab) | history "Visual fixture", 2 engine suggestions | none | 13 |
| `githu` (site prefix; GitHub is a Favorite) | Favorite tab GitHub (Switch to Tab) | search "githu" | 3 engine suggestions | github.com | 6 |
| `yout` (site prefix, not open) | youtube.com (site row) | search "yout" | 3 engine suggestions | youtube.com | 15 |
| `wiki` (site prefix; Wikipedia is a Favorite) | Favorite tab Wikipedia | search "wiki" | Wikimedia, Fandom, wikiHow (sites) | wikipedia.org | 15 |
| `fixture` (a whole word of an open tab's title) | open tab "Visual fixture" | search "fixture" | history "Media fixture (playing)", 2 engine suggestions | none (globe icon) | 13 |
| `best pizza dough recipe` (multi-word search) | search | 4 engine suggestions | | none | 10 |
| `how tall is the eiffel tower` (question) | search | 4 engine suggestions | | none | 10 |
| `dark mode` (command) | "Switch to Dark Mode" | search | 3 engine suggestions | none (command icon) | 11 |
| `new space` (command) | "New Space…" | search | 3 engine suggestions | none | 11 |
| `secondary ref` (history page title, not open) | search | history "Secondary reference" | 3 engine suggestions | none | 14 |
| `long title` (history page title, not open) | search | history "Long title for truncation…" | 3 engine suggestions | none | 8 |

Pictures: the real Arc's command bar for these queries. They are Arc's own screens, so they are kept outside the repository, in `~/brk-arc-reference/research-command-bar/` on the build Mac.

(Arc's screen: `~/brk-arc-reference/research-command-bar/t0-fixture.png`)

**`visual fix`.** The typed search leads and the open tab is second, although the tab's title starts with the query. A partial word gets no tab boost.

(Arc's screen: `~/brk-arc-reference/research-command-bar/q2-open-tab-word.png`)

**`fixture`.** With a whole word of the same title, the tab leads. This looked like the `exactHotWord` boost (100 / 15), but the binary gives that boost to commands only, so why the tab leads was not read. Brk gets the same result by giving a tab its title's words. A later probe (2026-11-11, a fixture tab "Quillfen Marrowby" open behind the current tab) narrows it down: `quillfen` and `marrowby` put the tab first, and `quillfen marrowby` put the typed search first and the tab second. With a tab "Price Watch (fixture)", `price watch` listed the search, the tab, then six Google suggestions that start with "price watch": a visited tab stays above them, because its page is also a visited-page candidate and the two show as one row.

(Arc's screen: `~/brk-arc-reference/research-command-bar/q1-site-prefix-githu.png`)

**`githu`.** A Favorite whose domain starts with the query leads, and the input completes to its host.

(Arc's screen: `~/brk-arc-reference/research-command-bar/q6-history-title.png`)

**`secondary ref`.** A history page whose title matches sits at row 2, right under the typed search and above the engine's suggestions.

**How this fits section 3 (a reading, not measured scores).**
- The typed search is first whenever no strong boost fires. That fits `autocompleteDefault` (15 / 3) on Chromium's default match.
- Exact words, domains and commands beat it: `exactHotWord` (commands) and `exactBaseDomain` (100 / 15), or `typeTravelPrefixForLongQuery` (40 / 3). A tab beats it for one whole word of its title, not for the whole title (see `fixture` above).
- Matching history outranks engine suggestions without any boost. Its archetype value is 100 against 95, and it has recency and visit counts against the suggestions' missing values.

## 6. Brk compared with Arc

**Brk today (`Sources/BrkOverlays/Suggest.swift`).** `rank` is a fixed order with per-source caps (tabs 3, history 3, actions 3, suggestions 3, top domains 1). For a query with no completion the order is:
1. the top command hit;
2. matching tabs;
3. the typed row;
4. top domains;
5. bookmarks;
6. engine suggestions;
7. history (newest first);
8. actions.

`completion` uses only open tabs and Arc's top-domain list.

**Where Brk differs from the real Arc on these queries.**

1. **Partial title matches.** Brk puts every matching open tab above the typed row ("visual fix" would show the tab first). Arc does that only for a whole-word or domain match; a partial title match goes below the search.
2. **History.** Brk puts history after the engine's suggestions, so with 5 rows it rarely shows. Arc puts a matching history page at row 2, above the suggestions ("secondary ref", "long title", "visual fix").
3. **Learning from use.** Brk has none. Arc boosts commands run more than once and uses visit and typed counts, site engagement and the most-visited rank.
4. **Inline completion.** Brk's completion never uses history. Arc's follows row 1, which can be a history or most-visited site.
5. **Same as Arc.** The site-prefix cases (githu, yout, wiki) and the command cases (dark mode, new space) already come out in Arc's order in Brk.

**What Brk would need to rank like Arc.**

Data to keep:
- **Per URL:** the visit count (Brk's history is already one entry per visit, so this can be counted), the last visit (already kept) and a **typed count**. Brk's `HistoryEntry` has no transition type, so a visit that came from the command bar or the address field must be marked.
- **Per origin:** a site-engagement score. CEF does not expose Chromium's `SiteEngagementService`, so Brk would compute its own from visits and time on page, or drop the feature.
- A **most-visited list** (derivable from visit counts).
- **globalSiteRank**, which is the order of Brk's top-domain table.
- **Command usage:** for each command, up to 15 run timestamps and a run count, like Arc's `typeTravelUsage`.
- **Optionally**, Arc's query-to-chosen-row log and the tab-switch log. Arc keeps them, but what reads them was not traced, so they are low priority.
- Per suggestion from the engine, its **position** (for `chromiumRank`). Chromium's relevance numbers are not available to Brk; a fixed value per row kind would stand in.

Logic:
- Collect all sources into one candidate list (up to about 15).
- Fill in the missing-feature values.
- Z-score each feature over this query's candidates, negating the "low" features.
- Average with Arc's category weights, adding the boosts into the same weighted mean.
- Sort, merge by dedup key, show 5, and take the inline completion from row 1 when its host starts with the typed text.

Every constant needed for this is in `ase2-defaults.json`.

Still unknown, to be fitted against the real Arc if exactness matters:
- the three match measures and the fuzzy confidence formula;
- the fuzzy threshold;
- `preferredMaxRankConfig` defaults;
- which duplicate survives a merge;
- the exact domain-boost conditions.

**Can Arc's model or weights be reproduced?**
- **The hand-tuned scorer: yes, exactly.** Its weights are constants in the binary and nothing about it is learned per user beyond the usage data above.
- **The trained model: no, and there is no need.** No weights ship, none are stored on this machine, and Arc 1.170 never calls it.

## Tools

The scripts read `/tmp/cbr/arc` (`lipo -thin arm64 /Applications/Arc.app/Contents/MacOS/Arc -output /tmp/cbr/arc`) and `/tmp/cbr/funcs.txt` (`llvm-objdump --macho --function-starts`). Edit the paths to reuse them.

| script | what it does |
|---|---|
| `macho.py` | Mach-O helpers: segments, reads, chained-fixup pointers, adrp references, containing function |
| `who.py <addr>…` | every reference to an address: branches, adrp pairs, 64-bit pointers, 32-bit relative pointers |
| `stubcalls.py <selector>…` / `selxref.py` | callers of ObjC methods through `objc_msgSend$` stubs |
| `swiftfieldtypes.py <out>` | every Swift field descriptor, with field names and resolved field types |
| `conformances.py [filter]` | Swift protocol conformance records |
| `dconst.py` / `constblobs.py` | find double constants built in code or loaded from `__const` tables |
| `extract_defaults.py` | prints `ase2-defaults.json` from the binary |
| `dis.sh <addr>` / `dec.sh <addr>…` + `Dec.java` | disassemble with llvm-objdump; decompile with Ghidra headless (`-noanalysis`) |
| `probe1.sh`, `probeall.sh`, `axrows.applescript` | the live probes in section 5 (run under the native lock) |
