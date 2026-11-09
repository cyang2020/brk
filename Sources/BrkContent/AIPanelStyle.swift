import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Every color the AI panel and the conversation tab paint with, from the window's Space theme (docs/design/ai-panel.md,
/// the table under "改法"). Each part copies a part of the sidebar: messages and the composer are the current tab's row,
/// the step line, notices, chips and @ rows the URL pill's fill, secondary text the "Today" header, lines the sidebar's
/// separator, pages the web card; the send button, links and the new-data dot are the Space's own color
/// (`Palette.focusColor`). Nothing is a system color, so a new Space, color or scheme changes the panel with it.
struct AIPanelStyle: Equatable {
    let scheme: Scheme
    let tokens: SidebarTokens
    let onCard: Bool
    /// The answer's text: the sidebar's title ink (`sidebarInk`) on light, white 0.9 on dark.
    let text: NSColor
    let secondary: NSColor
    let accent: NSColor
    /// The arrow on the send button: white on the light shade, dark on the light one a dark theme gets.
    let onAccent: NSColor
    /// The web card's color: pages and the conversation tab's background.
    let card: NSColor
    let cardText: NSColor

    init(_ theme: ResolvedTheme, onCard: Bool = false) {
        let palette = Palette(theme)
        scheme = theme.scheme
        tokens = theme.tokens
        self.onCard = onCard
        let ink = sidebarInk(palette.accent)
        text = scheme == .light ? NSColor(srgbRed: ink.red, green: ink.green, blue: ink.blue, alpha: 1) : NSColor(white: 1, alpha: 0.9)
        secondary = palette.color(tokens.foregroundStrong)
        accent = palette.focusColor
        onAccent = scheme == .light ? .white : NSColor(srgbRed: 0x1F / 255, green: 0x1E / 255, blue: 0x24 / 255, alpha: 1)
        card = Self.cardColor(scheme)
        cardText = scheme == .light ? NSColor(srgbRed: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255, alpha: 1) : NSColor(white: 1, alpha: 0.9)
    }

    static func cardColor(_ scheme: Scheme) -> NSColor {
        scheme == .light ? .white : NSColor(srgbRed: 0x20 / 255, green: 0x21 / 255, blue: 0x24 / 255, alpha: 1)
    }
    static func cardRGBA(_ scheme: Scheme) -> RGBA { scheme == .light ? RGBA(1, 1, 1) : RGBA(hex: "#202124") }

    func color(_ rgba: RGBA) -> NSColor { NSColor(srgbRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha) }
    var item: NSColor { color(tokens.itemBackground) }
    var itemHover: NSColor { color(tokens.itemHover) }
    var separator: NSColor { color(tokens.separator) }
    /// A user message's fill: the current tab's row on the Space's background; on the tab's white card the URL pill's.
    var bubble: NSColor { onCard ? item : color(tokens.tabCurrent) }
    /// The composer's fill: the current tab's row, or the card's own color with a hairline on the tab.
    var composer: NSColor { onCard ? card : color(tokens.tabCurrent) }
    /// The current row's shadow line under its lower edge; none on a dark theme (its token is clear).
    var shadow: NSShadow? {
        guard tokens.tabShadow.alpha > 0 else { return nil }
        let shadow = NSShadow()
        shadow.shadowColor = color(tokens.tabShadow)
        shadow.shadowBlurRadius = 1
        shadow.shadowOffset = CGSize(width: 0, height: -1)
        return shadow
    }
}

/// Brk's own words in the panel (docs/design/ai-panel.md, "文字的语言"): Chinese or English as the user writes in this
/// conversation (`AILanguage`), the system's before the first message. Arc's copied UI keeps its words.
struct AIPanelCopy {
    let language: AILanguage
    private var zh: Bool { language == .zh }

    var newConversation: String { zh ? "新对话" : "New conversation" }
    var openInTab: String { zh ? "在 tab 里打开，它会接着运行" : "Open in a tab. It keeps running." }
    var close: String { zh ? "关闭" : "Close" }
    var cancel: String { zh ? "取消" : "Cancel" }
    var working: String { zh ? "正在做事" : "Working" }
    var placeholderTabs: String { zh ? "继续问，或输入 @ 添加 tab" : "Ask a follow-up, or type @ to add a tab" }
    var placeholderFresh: String { zh ? "问问这些 tab，或输入 @ 添加 tab" : "Ask about these tabs, or type @ to add one" }
    var placeholderFolder: String { zh ? "告诉 agent 在这里做什么" : "Tell the agent what to do here" }
    var placeholderPlain: String { zh ? "继续问" : "Ask a follow-up" }
    var send: String { zh ? "发送" : "Send" }
    var stop: String { zh ? "停止" : "Stop" }
    var more: String { zh ? "更多" : "More" }
    var workInFolder: String { zh ? "在文件夹里工作…" : "Work in a Folder…" }
    var workInFolderTip: String {
        zh ? "开一个能在你选的文件夹里运行命令、改文件的对话，每一步都先问你。" : "Start a session that may run commands and change files in a folder you choose. It asks you first."
    }
    var agentSettings: String { zh ? "agent 设置…" : "Agent Settings…" }
    var agentSettingsTip: String { zh ? "在 设置 → Max 里选 agent、模型和思考强度。" : "Choose the agent, model and effort in Settings → Max." }
    var chooseAgentTip: String { zh ? "在 设置 → Max 里换 agent 和模型，下一条消息就用新的。" : "Change the agent and model in Settings → Max; the next message uses them." }
    func permissions(folder: String?, tabs: Bool) -> String {
        if let folder { return zh ? "在 \((folder as NSString).lastPathComponent) 里可以用工具，每次先问" : "Tools on in \((folder as NSString).lastPathComponent), each one asks" }
        if tabs { return zh ? "tab 工具直接用，其他都先问" : "Tab tools on · others ask" }
        return zh ? "不能用工具" : "Tools off"
    }
    func permissionsTip(folder: String?, tabs: Bool) -> String {
        if let folder { return folder }
        if tabs {
            return zh ? "agent 能读这个 profile 的 tab。第一次关掉或移动 tab 之前会先问；它自己的命令、改文件和其他工具每次都先问。"
                : "The agent reads this profile's tabs. It asks before it first closes or moves them, and before every command, file change or other tool of its own."
        }
        return zh ? "这次对话不能运行命令，也不能改文件。" : "This conversation cannot run commands or change files."
    }
    var localAgent: String { zh ? "本机 agent" : "Local agent" }
    var showCommand: String { zh ? "查看命令" : "Show Command" }
    var hideCommand: String { zh ? "收起命令" : "Hide Command" }
    var showDetail: String { zh ? "查看详情" : "Show Details" }
    var hideDetail: String { zh ? "收起详情" : "Hide Details" }
    func option(_ option: AIAgentApproval.Option) -> String {
        switch option.kind {
        case .allowOnce: zh ? "允许" : "Allow"
        case .allowSession: zh ? "这次对话都允许" : (option.title.isEmpty ? "Allow for Session" : option.title)
        case .deny: zh ? "拒绝" : "Deny"
        }
    }
    var keep: String { zh ? "存成 tab" : "Keep as Tab" }
    var keepTip: String { zh ? "把这个页面存成侧边栏里的一个 tab，带着它的数据和这次对话。" : "Keep this page as a tab in the sidebar, with its data and this conversation." }
    var showTab: String { zh ? "在 tab 里打开" : "Show Tab" }
    func schedule(_ schedule: AIPageSchedule) -> String {
        switch schedule {
        case .hourly: return zh ? "每小时" : "Hourly"
        case .daily(let hour, let minute): return zh ? String(format: "每天 %02d:%02d", hour, minute) : String(format: "Daily at %02d:%02d", hour, minute)
        case .weekly(let weekday, let hour, let minute):
            let names = zh ? ["周日", "周一", "周二", "周三", "周四", "周五", "周六"] : ["Sundays", "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays"]
            let day = names[max(0, min(6, weekday - 1))]
            return zh ? String(format: "每\(day) %02d:%02d", hour, minute) : String(format: "\(day) at %02d:%02d", hour, minute)
        }
    }
    var stepsRunning: String { zh ? "正在" : "Working:" }
    func failedSteps(_ n: Int) -> String { zh ? "\(n) 步没成功" : "\(n) failed" }
    var removeChip: String { zh ? "拿掉" : "Remove" }
    func dropHint() -> String { zh ? "松手就放进对话" : "Drop to add to the conversation" }
    var noMatches: String { zh ? "没有匹配的 tab" : "No matching tabs" }

    init(_ items: [AIConversationItem]) {
        language = AILanguage.of(items, system: Locale.preferredLanguages.first ?? "en")
    }
}
