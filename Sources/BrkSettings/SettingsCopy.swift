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
        case .advanced: "Advanced Preferences"
        }
    }

    /// SF Symbols for the toolbar. Arc draws General and Links with its own vectors (`PrefsGeneral`,
    /// `LinksPrefPaneIcon`, not shipped here) and uses `command.circle.fill` in the Shortcuts pane; the rest are ours.
    public static func symbol(_ pane: SettingsPane) -> String {
        switch pane {
        case .general: "gearshape"
        case .max: "sparkles"
        case .profiles: "person.crop.circle"
        case .shortcuts: "command"
        case .links: "link"
        case .advanced: "gearshape.2"
        }
    }

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
    /// Observed ("a smaller, simpler Arc window").
    public static var littleArcDescription: String {
        "Little Arc is a smaller, simpler \(Product.name) window. It’s perfect for quick lookups and reading funny tweets your friends send you."
    }
    /// Observed.
    public static let externalLinksInLittleArc = "Links from other apps open in Little Arc"
    /// Observed.
    public static let optionCommandClickLittleArc = "Open Little Arc when clicking on links with ⌥⌘ held"
    /// Observed.
    public static let littleArcAutoArchive = "Archive Little Arcs after:"

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
        "Max runs the AI command-line tool installed on this Mac (claude or codex) with your own account. \(Product.name) sends nothing anywhere itself."
    }
    public static let aiProvider = "AI provider:"

    public static func provider(_ choice: AIProviderChoice) -> String {
        switch choice {
        case .off: "Off"
        case .auto: "Automatic"
        case .claude: "claude"
        case .codex: "codex"
        }
    }

    public static func detected(_ kinds: [AIProviderKind], active: AIProviderKind?) -> String {
        let found = kinds.isEmpty ? "No local AI command-line tool found on PATH." : "Found on PATH: \(kinds.map(\.rawValue).joined(separator: ", "))."
        return active.map { "\(found) Using \($0.rawValue)." } ?? found
    }

    /// One line per tool the app knows how to run.
    public static func toolStatus(_ kind: AIProviderKind, found: Bool) -> String {
        "\(kind.rawValue): \(found ? "found" : "not found")"
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
