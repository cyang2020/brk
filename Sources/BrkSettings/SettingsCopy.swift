import BrkBase
import BrkDomain
import Foundation

/// Arc's settings copy (anatomy-m 4.2, visual-and-copy.md "Settings page labels", "Auto-archive options and
/// durations", "Little Arc", "Peek", "Air Traffic Control"). "Arc" in a sentence becomes the product name. Strings
/// of 15 bytes or less did not survive in Arc's binary (only their comments did), so the pane titles, section
/// labels and short menu items are ours unless a line says "observed". The Max pane uses Brk's own words where the
/// user's decision replaced Arc Max (the local command-line tool instead of Arc's AI partners).
public enum SettingsCopy {
    // MARK: Panes

    /// The toolbar item labels and the window title (the Settings package titles the window with the pane's title).
    /// Names from the "Preferences pane title; ..." comments; the visible text is short and was not recovered.
    public static func title(_ pane: SettingsPane) -> String {
        switch pane {
        case .general: "General"
        case .max: "Max"
        case .profiles: "Profiles"
        case .shortcuts: "Shortcuts"
        case .links: "Links"
        case .icon: "Icon"
        case .advanced: "Advanced"
        }
    }

    /// Observed per-pane strings ("General Preferences", "Profile Preferences", "Link Preferences", "Shortcuts
    /// Preferences", "Advanced Preferences"); Max has none in the binary, so its line follows the pattern. Used as
    /// the pane's accessibility label.
    public static func paneDescription(_ pane: SettingsPane) -> String {
        switch pane {
        case .general: "General Preferences"
        case .max: "Max Preferences"
        case .profiles: "Profile Preferences"
        case .shortcuts: "Shortcuts Preferences"
        case .links: "Link Preferences"
        case .icon: "Icon Preferences"
        case .advanced: "Advanced Preferences"
        }
    }

    /// SF Symbols for the toolbar, the closest to Arc 1.170's own toolbar drawings (P38): a gear, a person, Max's
    /// four-petal mark, two windows, a keyboard, the app's squircle, three sliders.
    public static func symbol(_ pane: SettingsPane) -> String {
        switch pane {
        case .general: "gearshape"
        case .max: "circle.grid.cross"
        case .profiles: "person"
        case .shortcuts: "keyboard"
        case .links: "macwindow.on.rectangle"
        case .icon: "app"
        case .advanced: "slider.horizontal.3"
        }
    }

    public static let back = "Back"

    // MARK: General

    /// Observed: " is not your default web browser." after the app's name.
    public static var notDefaultBrowser: String { "\(Product.name) is not your default web browser." }
    /// The menu row's title (row 5, observed).
    public static let setAsDefaultBrowser = "Set as Default Browser"
    public static let dismissNotice = "Not Now"
    /// Observed.
    public static let profileSettingsHint = "Manage your default search engine, Auto-Archive, and downloads in Profile Settings."
    /// Observed.
    public static let profileSettingsButton = "Profile Settings…"
    /// Observed.
    public static let warnBeforeQuitting = "Warn before quitting"
    public static let appearanceLabel = "Appearance:"
    /// Observed (P38-a).
    public static let previews = "Previews"
    public static let previewsSettingsButton = "Previews Settings…"
    /// The Previews sheet (P13-settings-arc.png): Arc's title and paragraph with the product's name.
    public static var showPreviews: String { "Show \(Product.name) Previews:" }
    public static var previewsExplanation: String {
        "Save a click! Hover your mouse over a \(Product.name) Folder, Pinned, or Favorited tab to quickly preview what you need from that site!"
    }
    public static let learnMore = "Learn more"
    public static var previewsDetail: String {
        "Hover a folder to see the tabs inside it, or a Pinned or Favorited tab to see its page and address. Links on a page preview after a deliberate hover. Max’s 5-Second Previews add a short summary, written by your local AI tool."
    }
    public static var folderAndTabPreviews: String { "\(Product.name) Folders, Pinned and Favorited tabs, and links" }
    public static let maxLinkPreviews = "5-Second Previews (Max)"
    public static let done = "Done"
    public static let numberedFavorites = "Include Favorites in numbered tab shortcuts"
    /// View > Appearance's heading (observed).
    public static let webAppearance = "Websites, Easels, and Notes will use:"

    public static func appearance(_ appearance: WebAppearance) -> String {
        switch appearance {
        case .automatic: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The "Warn before quitting" dialog (`QuitWarning`). Arc's title and message are short strings that were not
    /// recovered (their comments were: "Dialog of user closing Arc application.").
    public static var quitTitle: String { "Quit \(Product.name)?" }
    public static let quitMessage = "Are you sure you want to quit?"
    public static let quitButton = "Quit"
    public static let cancelButton = "Cancel"
    /// Observed.
    public static let quitDontAskAgain = "Quit, and don’t ask again"

    // MARK: Profiles

    /// Observed.
    public static let profilesIntro = "Profiles help keep your data separate across Spaces — like history, logins, cookies, and extensions. You can use any Profile across one or more Spaces."
    /// Arc has a description for 0, 1 and N spaces (comments observed, text not recovered).
    public static func spaceCount(_ count: Int) -> String {
        switch count {
        case 0: "No Spaces"
        case 1: "1 Space"
        default: "\(count) Spaces"
        }
    }
    /// "Archive tabs after" (observed; the colon is the label column's).
    public static let autoArchive = "Archive tabs after:"
    /// "Default Search Engine" (observed).
    public static let searchEngine = "Default Search Engine:"
    /// Observed.
    public static let searchSuggestions = "Include search engine suggestions"
    /// "Download location" (observed); its menu has Arc's three kinds of item (`arc.folder`, `arc.promptForDownload`,
    /// `arc.other`).
    public static let downloadLocation = "Download location:"
    /// The system folder a nil `downloadsDirectory` means.
    public static let downloadsFolder = "Downloads"
    public static let useDownloadsFolder = "Use Downloads"
    public static let promptForDownloadLocation = "Ask where to save each download"
    public static let otherFolder = "Other…"
    /// The folder panel: its title is Arc's "Download Location" (observed), its button ours.
    public static let chooseFolderTitle = "Download Location"
    public static let chooseFolderPrompt = "Select"

    // MARK: Links

    /// Observed.
    public static var linksIntro: String { "Choose where links open inside \(Product.name)." }
    /// "Air Traffic Control…" is Arc's button (observed); the route list sits in the pane here.
    public static let airTrafficControl = "Air Traffic Control:"
    /// Observed.
    public static var routesIntro: String {
        "Routes let you choose where specific sites open inside \(Product.name). For example, you can route Spotify links to always open inside your Personal space."
    }
    /// Observed.
    public static let mostRecentSpace = "Most Recent Space"
    public static let littleArc = "Little Arc"
    public static let otherLinksOpenIn = "Other links open in:"
    public static let routePatternPlaceholder = "open.spotify.com"
    public static let addRoute = "Add Route"
    public static let removeRoute = "Remove Route"
    public static let moveRouteUp = "Move Up"
    public static let moveRouteDown = "Move Down"
    public static let noRoutes = "No routes yet."

    public static let peekLabel = "Peek:"
    /// Observed.
    public static let peekDescription = "Peek is a way to preview a link without opening a new tab. It’s perfect for quickly looking at a link from an email, news article, or tweet."
    /// Observed.
    public static let peekFromPinnedAndFavorites = "Open a Peek window when clicking on links to other sites"
    /// Observed.
    public static let peekNote = "Note: This only affects Favorites and Pinned tabs"
    /// Observed.
    public static let shiftClickPeek = "Open a Peek window when clicking on links with Shift held"

    public static let littleArcLabel = "Little Arc:"
    /// Observed ("a smaller, simpler Arc window"), with the product's name for both.
    public static var littleArcDescription: String {
        "Little \(Product.name) is a smaller, simpler \(Product.name) window. It’s perfect for quick lookups and reading funny tweets your friends send you."
    }
    /// Observed ("Links from other apps open in Little Arc").
    public static var externalLinksInLittleArc: String { "Links from other apps open in Little \(Product.name)" }
    /// Observed.
    public static var optionCommandClickLittleArc: String { "Open Little \(Product.name) when clicking on links with ⌥⌘ held" }
    /// Observed ("Archive Little Arcs after:").
    public static var littleArcAutoArchive: String { "Archive Little \(Product.name)s after:" }
    /// Observed ("Open Little Arc when I press " then the shortcut, " in any app"): the New Little Window shortcut as
    /// the Shortcuts pane has it.
    public static func globalLittleArcShortcut(_ shortcuts: [ShortcutRow]) -> String {
        let state = shortcuts.first { $0.action == .showLittleArc }?.state
        let chord: String = if case .valid(let key)? = state { KeyGlyphs.text(key) } else { "its shortcut" }
        return "Open Little \(Product.name) when I press \(chord) in any app"
    }
    /// Under the switch when the system-wide shortcut could not be taken (Brk's wording; Arc's was not recovered).
    public static func globalShortcutNote(_ status: GlobalShortcutStatus?) -> String? {
        switch status {
        case .unavailable(let chord, _)?: "\(KeyGlyphs.text(chord)) is used by another app, so it only works inside \(Product.name). Choose another shortcut in Shortcuts."
        case .needsModifier(let chord)?: "\(KeyGlyphs.text(chord)) has no modifier key, so it only works inside \(Product.name)."
        case .registered?, .off?, nil: nil
        }
    }
    /// Air Traffic Control moved one level down (observed button "Air Traffic Control…").
    public static let airTrafficControlButton = "Air Traffic Control…"
    /// Arc's ad blocker row ("Use Arc's built-in protection against ads, pop-ups, and trackers…", observed, cut
    /// short) and "Block Cookie Banners" (observed).
    public static var blockAds: String { "Use \(Product.name)'s built-in protection against ads and trackers" }
    public static let hideCookieBanners = "Block Cookie Banners"
    /// Observed (Q06-links-bottom: "Choose where links open inside Arc." with an ⓘ).
    public static var routesSummary: String { "Choose where links open inside \(Product.name)." }

    // MARK: Shortcuts

    /// Observed.
    public static let customShortcuts = "Custom Shortcuts"
    /// Observed.
    public static var shortcutsIntro: String {
        "Change shortcuts for your favorite actions, and even choose whether \(Product.name) or a website takes priority."
    }
    /// Observed.
    public static let customizedShortcuts = "Customized Shortcuts"
    /// Observed.
    public static let defaultShortcuts = "Default Shortcuts"
    /// Observed.
    public static let resetAllShortcuts = "Reset All Shortcuts"
    /// Observed.
    public static let resetShortcut = "Reset Shortcut to Default"

    /// A shortcut as the pane lists it: the chord as macOS menus show it, or Arc's conflict sentence.
    public static func state(_ state: KeyBindingState, titles: (ActionID) -> String = { $0.spec.title }) -> String {
        switch state {
        case .valid(let chord): KeyGlyphs.text(chord)
        case .conflict(let chord, let others):
            // Observed formats: " is already in use by “%@”", "… and one other action", "… and %d other actions".
            switch others.count {
            case 0: KeyGlyphs.text(chord)
            case 1: "\(KeyGlyphs.text(chord)) is already in use by “\(titles(others[0]))”"
            case 2: "\(KeyGlyphs.text(chord)) is already in use by “\(titles(others[0]))” and one other action"
            default: "\(KeyGlyphs.text(chord)) is already in use by “\(titles(others[0]))” and \(others.count - 1) other actions"
            }
        case .unset: "None"
        }
    }

    // MARK: Max

    /// Observed.
    public static var maxIntro: String {
        "Let \(Product.name) do more for you with Max, so you can do less. Power up your browsing with AI and spend time on the things that matter — on or off screen."
    }
    /// Replaces Arc's "Max features require that we send data to our AI partners." (user decision: local tools).
    public static var maxPrivacy: String {
        "Max runs a coding agent installed on this Mac (claude, codex, gemini, cursor-agent or opencode) with your own signed-in account. The selected agent may send your question and requested page text to its service. No API key is required."
    }
    public static let aiProvider = "AI provider:"

    public static func provider(_ choice: AIProviderChoice) -> String {
        switch choice {
        case .off: "Off"
        case .auto: "Automatic"
        case .claude: "claude"
        case .codex: "codex"
        case .gemini: "gemini"
        case .cursor: "cursor-agent"
        case .opencode: "opencode"
        }
    }

    public static func detected(_ kinds: [AIProviderKind], active: AIProviderKind?) -> String {
        let found = kinds.isEmpty ? "No local AI command-line tool found on PATH." : "Found on PATH: \(kinds.map(\.executableNames[0]).joined(separator: ", "))."
        return active.map { "\(found) Using \($0.executableNames[0])." } ?? found
    }

    /// One line per tool the app knows how to run.
    public static func toolStatus(_ kind: AIProviderKind, found: Bool) -> String {
        "\(kind.executableNames[0]): \(found ? "found" : "not found")"
    }

    /// An agent's line in the Max pane's Local AI agent card.
    public static func agentStatus(_ status: AIAgentStatus) -> String {
        let name = status.kind.displayName + (status.version.map { " " + $0 } ?? "")
        switch status.state {
        case .missing: return "\(status.kind.displayName): not installed"
        case .checking: return "\(name): checking…"
        case .ready: return "\(name): signed in"
        case .notSignedIn: return "\(name): not signed in. In Terminal, run \(signInCommand(status.kind))."
        case .failed(let reason): return "\(name): \(reason)"
        }
    }
    private static func signInCommand(_ kind: AIProviderKind) -> String {
        switch kind {
        case .claude: "claude"
        case .codex: "codex login"
        case .gemini: "gemini"
        case .cursor: "cursor-agent login"
        case .opencode: "opencode auth login"
        }
    }

    public static let maxFeatures = "Features:"
    /// Arc Max's name for renamed pinned tabs (the short name is not in the binary).
    public static let renamePinnedTabs = "Tidy Titles"
    /// Observed.
    public static let renamePinnedTabsDescription = "Have your tabs automatically renamed with tidier, shorter titles when you Pin them."
    public static let tidyTabs = "Tidy Tabs"
    /// Arc's description is stored obfuscated (`tidyTabsDescription`); ours.
    public static let tidyTabsDescription = "Group your Today tabs into folders by topic, with one click."

    // MARK: Advanced (all observed)

    /// The buttons under the Advanced cards (P38-g, observed).
    public static let moreSettings = "More Settings…"
    public static let moreSettingsTitle = "More Settings"
    public static let resetTranslatedSitePrompts = "Reset Translated-site Prompts"
    public static let exportData = "Export Data"
    /// Observed (P38-g): the Shared Quotes row's subtitle.
    public static let sharedQuotesNote = "If disabled, you can still copy URL as a quote using ⌃⇧⌘C."
    public static let defaultBrowser = "Default browser"
    public static var isDefaultBrowser: String { "\(Product.name) is your default web browser." }
    public static let importBrowserFile = "Import File…"
    public static let importBrowserFileTitle = "Import an exported browser file"
    public static let tourTitle = "Learn the basics"
    public static let sidebarData = "Sidebar Data: Import, Sync and Export"
    public static var tour: String { "Open \(Product.name) 101" }

    public static var restoreWindowsOnLaunch: String { "When opening \(Product.name), restore windows from previous session" }
    public static var soundEffects: String { "Play \(Product.name) sound effects" }
    public static let hapticsOnReorder = "Haptic feedback when reordering tabs"
    public static let showFullURLInToolbar = "Show full URL when Toolbar is enabled"
    public static let windowDraggingFromPages = "Allow window dragging from the top of webpages"
    public static let autoPictureInPicture = "Enable Picture in Picture when you leave a video tab"
    public static let themeToCSS = "Allow websites to get your theme data"
    public static let boostsEnabled = "Enable Boosts on websites you visit"
    public static let sharedQuotes = "Enable Shared Quotes when highlighting text."

    /// The Advanced pane's section icons, in the order the binary lists them next to the switches
    /// (`paintpalette.fill`, `rectangle.topthird.inset.filled`, `speaker.wave.2.fill`; observed names, grouping
    /// inferred from string order).
    public static let advancedWebSymbol = "paintpalette.fill"
    public static let advancedWindowSymbol = "rectangle.topthird.inset.filled"
    public static let advancedFeedbackSymbol = "speaker.wave.2.fill"

    // MARK: Shared

    /// A threshold as Arc's pickers list it, " (default)" after the default one (P38-d "12 hours (default)", P38-f
    /// "6 hours (default)").
    public static func threshold(_ threshold: AutoArchiveThreshold, default standard: AutoArchiveThreshold) -> String {
        threshold == standard ? "\(Self.threshold(threshold)) (default)" : Self.threshold(threshold)
    }

    /// Arc's seven choices (visual-and-copy.md "Auto-archive options and durations").
    public static func threshold(_ threshold: AutoArchiveThreshold) -> String {
        switch threshold {
        case .oneHour: "1 hour"
        case .sixHours: "6 hours"
        case .twelveHours: "12 hours"
        case .twentyFourHours: "24 hours"
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        case .never: "Never"
        }
    }
}

/// A chord as macOS menus show it: ⌃⌥⇧⌘ in that order, then the key.
enum KeyGlyphs {
    static func text(_ chord: KeyChord) -> String {
        var text = ""
        if chord.modifiers.contains(.control) { text += "⌃" }
        if chord.modifiers.contains(.option) { text += "⌥" }
        if chord.modifiers.contains(.shift) { text += "⇧" }
        if chord.modifiers.contains(.command) { text += "⌘" }
        return text + glyph(chord.key)
    }

    private static func glyph(_ key: Key) -> String {
        switch key {
        case .tab: "⇥"
        case .space: "Space"
        case .escape: "⎋"
        case .returnKey: "↩"
        case .f12: "F12"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .downArrow: "↓"
        case .upArrow: "↑"
        default: key.menuKeyEquivalent.uppercased()
        }
    }
}
