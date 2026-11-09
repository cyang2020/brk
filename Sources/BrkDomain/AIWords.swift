import BrkBase
import Foundation

// Brk's own AI words (docs/design/ai-panel.md, "文字的语言"): what Brk itself says in a conversation, its notices, the
// steps' plain-language lines and the approval card's sentence, in the language the user writes in that conversation,
// Chinese or English, and before the first message in the system's. The system language here is English while the user
// talks to the agent in Chinese; following the system put English lines into Chinese conversations. Arc's own UI that
// Brk copies keeps its words.

/// The two languages Brk's AI words come in.
public enum AILanguage: String, Hashable, Sendable, Codable {
    case zh, en

    /// The language a message is written in: Chinese when it has any Han character, English when it has Latin letters
    /// and no Han, nil when it has neither (a link, an emoji, digits).
    public static func of(text: String) -> AILanguage? {
        var latin = false
        // Addresses say nothing about the language the user writes in.
        let words = text.split(whereSeparator: \.isWhitespace).filter { !$0.contains("://") && !$0.hasPrefix("www.") }
        for scalar in words.joined(separator: " ").unicodeScalars {
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return .zh
            case 0x41...0x5A, 0x61...0x7A: latin = true
            default: break
            }
        }
        return latin ? .en : nil
    }

    /// The system's: Chinese for any "zh" language ("zh-Hans-CN"), else English.
    public static func system(_ code: String) -> AILanguage { code.lowercased().hasPrefix("zh") ? .zh : .en }

    /// The conversation's: its latest user message that tells, else the system's.
    public static func of(_ items: [AIConversationItem], system: String) -> AILanguage {
        for item in items.reversed() {
            if case .user(let text) = item, let language = of(text: text) { return language }
        }
        return Self.system(system)
    }
}

/// What Brk itself writes into a conversation's transcript, by language.
public enum AIWords {
    public static func with(_ names: [String], _ language: AILanguage) -> String {
        language == .zh ? "附上 " + names.joined(separator: " · ") : "With " + names.joined(separator: " · ")
    }

    /// The tab names a `with` line lists, without its folders and Spaces; nil for any other line.
    public static func attachedNames(_ line: String) -> [String]? {
        let rest: Substring
        if line.hasPrefix("附上 ") { rest = line.dropFirst(3) } else if line.hasPrefix("With ") { rest = line.dropFirst(5) } else { return nil }
        let group = try? NSRegularExpression(pattern: #"(（\d+ 个 tab）|\(\d+ tabs?\))$"#)
        return rest.components(separatedBy: " · ").filter { name in
            guard !name.isEmpty else { return false }
            return group?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) == nil
        }
    }

    /// One attached folder or Space and how many tabs it gave.
    public static func group(_ title: String, tabs: Int, _ language: AILanguage) -> String {
        language == .zh ? "\(title)（\(tabs) 个 tab）" : "\(title) (\(tabs) \(tabs == 1 ? "tab" : "tabs"))"
    }

    public static func workingIn(_ folder: String, _ language: AILanguage) -> String {
        language == .zh ? "在 \(folder) 里工作。工具已打开，agent 运行命令或改文件之前会先在这里问你。"
            : "Working in \(folder). Tools are on; the agent asks here before it runs a command or changes a file."
    }

    public static func stopped(_ language: AILanguage) -> String { language == .zh ? "已停止。" : "Stopped." }

    /// One of Brk's notices written before the user's first message, in the system's language, written again in the
    /// language of that message; any other text as it is.
    public static func reword(_ text: String, to language: AILanguage) -> String {
        for from in [AILanguage.zh, .en] where from != language {
            if text == cannotReadTabs(from) { return cannotReadTabs(language) }
            let working = workingIn("\u{0}", from).components(separatedBy: "\u{0}")
            if working.count == 2, text.hasPrefix(working[0]), text.hasSuffix(working[1]), text.count > working[0].count + working[1].count {
                return workingIn(String(text.dropFirst(working[0].count).dropLast(working[1].count)), language)
            }
        }
        return text
    }

    public static func agentChanged(_ language: AILanguage) -> String {
        language == .zh ? "Max 换了 agent。再问一次，就是和新的 agent 说话。" : "Max's agent changed. Ask again to talk to the new one."
    }

    public static func cannotReadTabs(_ language: AILanguage) -> String {
        language == .zh ? "这次对话不能读 tab。先关掉它，再把 tab 拖进来，就会开一个能读 tab 的对话。"
            : "This conversation cannot read tabs. Close it, then drop the tabs again to start one that can."
    }

    /// A refresh that changed the page's data: when, and the agent's one line on what changed (else the page's title).
    public static func refreshed(_ title: String, at time: String, summary: String?, _ language: AILanguage) -> String {
        let line = summary.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : String($0.prefix(Self.summaryLimit)) }
        if language == .zh { return line.map { "\(time) 已更新 · \($0)" } ?? "\(time) 已更新「\(title)」" }
        return line.map { "\(time) Updated · \($0)" } ?? "\(time) Updated “\(title)”"
    }
    static let summaryLimit = 120

    public static func refreshStopped(_ title: String, why: String?, _ language: AILanguage) -> String {
        language == .zh ? "已停止更新「\(title)」：\(why ?? "Brk 觉得读到的内容可疑")。页面没有改动。"
            : "Stopped the refresh of “\(title)”: \(why ?? "Brk flagged what it read"). Nothing changed."
    }

    public static func refreshFailed(_ title: String, why: String?, _ language: AILanguage) -> String {
        language == .zh ? "「\(title)」这次没有更新成：\(why ?? "agent 没有做完")。页面没有改动。"
            : "The refresh of “\(title)” failed: \(why ?? "the agent did not finish"). Nothing changed."
    }

    /// "11:32": the hour and minute of `instant` in `calendar`'s time zone.
    public static func clock(_ instant: Instant, calendar: Calendar) -> String {
        let date = Date(timeIntervalSince1970: Double(instant.milliseconds) / 1000)
        let parts = calendar.dateComponents(in: calendar.timeZone, from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// A step's line, a run of steps summed up in plain words, and an approval's sentence (docs/design/ai-panel.md, "对话内容"
/// and "授权框").
public enum AIStepWords {
    /// One step as the expanded list shows it.
    public static func title(_ step: AIAgentStep, _ language: AILanguage) -> String {
        guard let kind = step.kind else { return step.title }
        return phrase(kind, subject: step.subject, language)
    }

    /// One thing done, with what it was done on when there is one.
    static func phrase(_ kind: AIStepKind, subject: String?, _ language: AILanguage) -> String {
        let s = subject.map { AgentLine.oneLine($0, limit: 80) }.flatMap { $0.isEmpty ? nil : $0 }
        func with(_ zh: String, _ en: String) -> String {
            guard let s else { return language == .zh ? zh : en }
            return language == .zh ? zh + "：" + s : en + ": " + s
        }
        switch kind {
        case .listTabs: return language == .zh ? "看了 tab 列表" : "Listed tabs"
        case .searchTabs: return with("搜了 tab", "Searched tabs")
        case .readTab: return with("读了一个 tab", "Read a tab")
        case .openTab: return with("打开了一个 tab", "Opened a tab")
        case .showTab: return language == .zh ? "切到一个 tab" : "Showed a tab"
        case .closeTabs: return language == .zh ? "关了 tab" : "Closed tabs"
        case .moveTabs: return language == .zh ? "移动了 tab" : "Moved tabs"
        case .groupTabs: return language == .zh ? "给 tab 分了组" : "Grouped tabs"
        case .splitTabs: return language == .zh ? "把 tab 并排显示" : "Split tabs"
        case .listConversations: return language == .zh ? "看了对话列表" : "Listed conversations"
        case .searchConversations: return with("搜了以前的对话", "Searched conversations")
        case .readConversation: return language == .zh ? "读了一次对话" : "Read a conversation"
        case .previewPage: return language == .zh ? "预览了页面" : "Previewed a page"
        case .makePage: return with("做了一个页面", "Made a page")
        case .keepPage: return language == .zh ? "把页面存成了 tab" : "Kept a page as a tab"
        case .changePage: return language == .zh ? "改了页面" : "Changed a page"
        case .readSource: return with("读了一个网页", "Read a web page")
        case .writeData: return language == .zh ? "写了页面的数据" : "Wrote the page's data"
        case .command: return with("运行了命令", "Ran")
        case .readFile: return with("读了文件", "Read")
        case .writeFile: return with("写了文件", "Wrote")
        case .editFile: return with("改了文件", "Edited")
        case .searchFiles: return with("搜了文件", "Searched files")
        case .fetchPage: return with("打开了网页", "Fetched")
        case .searchWeb: return with("在网上搜了", "Searched the web")
        case .helper: return with("找了个帮手", "Started a helper")
        case .taskList: return language == .zh ? "更新了任务列表" : "Updated the task list"
        case .skill: return with("用了技能", "Used the skill")
        }
    }

    /// A run of steps in one line, by what was done: "读了 3 个 tab，做了一个页面". Kinds keep the order they first came in.
    public static func summary(_ steps: [AIAgentStep], _ language: AILanguage) -> String {
        var groups: [(group: Group, count: Int)] = []
        for step in steps {
            let group = Group(step.kind)
            if let index = groups.firstIndex(where: { $0.group == group }) { groups[index].count += 1 } else { groups.append((group, 1)) }
        }
        // Reading tabs already says the agent looked at them: "看了 tab，读了 3 个 tab" says the same thing twice.
        if groups.contains(where: { $0.group == .readTabs }) { groups.removeAll { $0.group == .lookTabs } }
        let parts = groups.map { $0.group.words($0.count, language) }
        return parts.joined(separator: language == .zh ? "，" : ", ")
    }

    /// Kinds that read as one thing in a summary.
    enum Group: Hashable {
        case lookTabs, readTabs, openTabs, changeTabs, conversations, makePages, changePages, keepPages, readSources
        case commands, readFiles, changeFiles, searchFiles, web, other

        init(_ kind: AIStepKind?) {
            switch kind {
            case .listTabs?, .searchTabs?, .showTab?: self = .lookTabs
            case .readTab?: self = .readTabs
            case .openTab?: self = .openTabs
            case .closeTabs?, .moveTabs?, .groupTabs?, .splitTabs?: self = .changeTabs
            case .listConversations?, .searchConversations?, .readConversation?: self = .conversations
            case .makePage?, .previewPage?: self = .makePages
            case .changePage?, .writeData?: self = .changePages
            case .keepPage?: self = .keepPages
            case .readSource?, .fetchPage?: self = .readSources
            case .command?: self = .commands
            case .readFile?: self = .readFiles
            case .writeFile?, .editFile?: self = .changeFiles
            case .searchFiles?: self = .searchFiles
            case .searchWeb?: self = .web
            case .helper?, .taskList?, .skill?, nil: self = .other
            }
        }

        func words(_ n: Int, _ language: AILanguage) -> String {
            let zh = language == .zh
            func count(_ zhUnit: String, _ one: String, _ many: String) -> String {
                zh ? (n == 1 ? "一" + zhUnit : " \(n) " + zhUnit) : (n == 1 ? one : "\(n) " + many)
            }
            switch self {
            case .lookTabs: return zh ? "看了 tab" : "looked through tabs"
            case .readTabs: return zh ? "读了" + count("个 tab", "", "") : "read " + count("", "a tab", "tabs")
            case .openTabs: return zh ? "打开了" + count("个 tab", "", "") : "opened " + count("", "a tab", "tabs")
            case .changeTabs: return zh ? "整理了 tab" : "rearranged tabs"
            case .conversations: return zh ? "翻了以前的对话" : "looked through past conversations"
            case .makePages: return zh ? "做了" + count("个页面", "", "") : "made " + count("", "a page", "pages")
            case .changePages: return zh ? "改了页面" : "changed a page"
            case .keepPages: return zh ? "存成了 tab" : "kept it as a tab"
            case .readSources: return zh ? "读了" + count("个网页", "", "") : "read " + count("", "a web page", "web pages")
            case .commands: return zh ? "运行了" + count("条命令", "", "") : "ran " + count("", "a command", "commands")
            case .readFiles: return zh ? "读了" + count("个文件", "", "") : "read " + count("", "a file", "files")
            case .changeFiles: return zh ? "改了" + count("个文件", "", "") : "changed " + count("", "a file", "files")
            case .searchFiles: return zh ? "搜了文件" : "searched files"
            case .web: return zh ? "在网上搜了" : "searched the web"
            case .other: return zh ? "做了" + count("步", "", "") : "took " + count("", "a step", "steps")
            }
        }
    }

    /// The approval card's first line: who wants to do what, and where. "Claude 想在 ~/Desktop 里运行一条命令".
    public static func approval(_ approval: AIAgentApproval, agent: String?, folder: String?, _ language: AILanguage) -> String {
        let who = agent ?? (language == .zh ? "agent" : "The agent")
        let place = folder.map(Self.folderName)
        guard let kind = approval.kind else {
            return language == .zh ? "\(who) 想：\(approval.title)" : "\(who) wants to: \(approval.title)"
        }
        let zhWhat: String, enWhat: String
        switch kind {
        case .command: (zhWhat, enWhat) = ("运行一条命令", "run a command")
        case .writeFile: (zhWhat, enWhat) = ("写一个文件", "write a file")
        case .editFile: (zhWhat, enWhat) = ("改文件", "change files")
        case .readFile: (zhWhat, enWhat) = ("读一个文件", "read a file")
        case .fetchPage: (zhWhat, enWhat) = ("打开一个网页", "fetch a web page")
        case .searchWeb: (zhWhat, enWhat) = ("在网上搜索", "search the web")
        case .openTab:
            let address = approval.subject.map { AgentLine.oneLine($0, limit: 80) }
            (zhWhat, enWhat) = address.map { ("在新 tab 里打开 \($0)", "open \($0) in a new tab") } ?? ("打开一个新网址", "open a new address")
        case .showTab:
            (zhWhat, enWhat) = approval.subject.map { ("切到「\($0)」", "show “\($0)”") } ?? ("切到一个 tab", "show a tab")
        case .closeTabs: (zhWhat, enWhat) = ("关掉" + tabs(approval.subject, .zh), "close " + tabs(approval.subject, .en))
        case .moveTabs: (zhWhat, enWhat) = ("移动" + tabs(approval.subject, .zh), "move " + tabs(approval.subject, .en))
        case .groupTabs: (zhWhat, enWhat) = ("把" + tabs(approval.subject, .zh) + " 分组", "group " + tabs(approval.subject, .en))
        case .splitTabs: (zhWhat, enWhat) = ("把" + tabs(approval.subject, .zh) + " 并排显示", "show " + tabs(approval.subject, .en) + " side by side")
        default:
            return language == .zh ? "\(who) 想：\(approval.title)" : "\(who) wants to: \(approval.title)"
        }
        if let place, [.command, .writeFile, .editFile, .readFile].contains(kind) {
            return language == .zh ? "\(who) 想在 \(place) 里\(zhWhat)" : "\(who) wants to \(enWhat) in \(place)"
        }
        return language == .zh ? "\(who) 想\(zhWhat)" : "\(who) wants to \(enWhat)"
    }

    /// "3 个 tab" / "3 tabs" for a count given as the subject; "tab" / "tabs" without one.
    private static func tabs(_ count: String?, _ language: AILanguage) -> String {
        guard let n = count.flatMap({ Int($0) }) else { return language == .zh ? " tab" : "tabs" }
        if language == .zh { return n == 1 ? "一个 tab" : " \(n) 个 tab" }
        return n == 1 ? "a tab" : "\(n) tabs"
    }

    /// A folder in one sentence: "~/Desktop" when that is short, otherwise only the folder's own name, so the sentence
    /// stays one line ("/tmp/a/b/c/ai-work" as "ai-work"). The full path is in the sentence's tooltip and the command.
    public static func folderName(_ path: String) -> String {
        let short = shortPath(path)
        guard short.count > 24 else { return short }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? short : name
    }

    /// "/Users/me/Desktop" as "~/Desktop".
    public static func shortPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// An answered approval's quiet line: what was chosen, then the sentence.
    public static func answered(_ approval: AIAgentApproval, option: AIAgentApproval.Option, agent: String?, folder: String?, _ language: AILanguage) -> String {
        let choice: String = switch option.kind {
        case .allowOnce: language == .zh ? "允许了" : "Allowed"
        case .allowSession: language == .zh ? "这次对话里都允许" : "Allowed for this conversation"
        case .deny: language == .zh ? "拒绝了" : "Denied"
        }
        return choice + (language == .zh ? "：" : ": ") + Self.approval(approval, agent: agent, folder: folder, language)
    }
}

/// One line of text from many.
public enum AgentLine {
    public static func oneLine(_ text: String, limit: Int) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return line.count > limit ? String(line.prefix(limit)) + "…" : line
    }
}
