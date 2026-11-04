import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

// Owner: W4 (dialogs). Arc's space icon popover (Change Space Icon…, and the icon button of Create a Space's name
// field), matched to the 2026-11-03 captures P10 c and P24 b: two pages, Emoji and Icon; the Emoji page has a search
// field, an 8-column emoji grid and a row of category buttons at the bottom; the Icon page is the named-icon grid
// (with "No icon" first). Choosing an entry reports it and the popover closes.

struct IconPickerMetrics: MetricGroup {
    let size = Metric(CGSize(width: 270, height: 272), .guess("popover content, measured on P10-c-arc.png and P24-b-arc.png (542 x 543 px at 2x)"))
    let columns = Metric(8, .guess("emoji per row, counted on P10 c"))
    let cell = Metric(CGSize(width: 30.85, height: 33), .anatomy("verify/visual-pairs/run-20261103/P10/P10-c-arc.png: the emoji's centres are 61.7 px apart, the rows 66 px"))
    let emojiSize = Metric(20.0, .anatomy("verify/visual-pairs/run-20261103/P10/P10-c-arc.png: an emoji is 40 px wide"))
    let searchRadius = Metric(14.0, .anatomy("verify/visual-pairs/run-20261103/P10/P10-c-arc.png: the search field's ends are round"))
    let tabsHeight = Metric(24.0, .guess("Emoji / Icon switch height, measured on P10 c"))
    let searchHeight = Metric(28.0, .guess("search field height, measured on P10 c"))
    let categoriesHeight = Metric(34.0, .guess("category bar height, measured on P10 c"))
    let radius = Metric(7.0, .guess("switch and search field corner radius, measured on P10 c"))
}

let IconPicker = IconPickerMetrics()

/// Arc's emoji categories in its bottom-bar order, each with the bar's symbol. The lists are the leading part of each
/// Unicode emoji group in the standard order (the grid in P10 c starts 😀 😃 😄 😁 😆 😅 🤣 😂).
enum EmojiCatalog {
    struct Category: Identifiable {
        let id: String
        let symbol: String
        let emoji: [String]
    }

    static let categories: [Category] = [
        Category(id: "Smileys & People", symbol: "face.smiling", emoji: split("""
        😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 🫠 😉 😊 😇 🥰 😍 🤩 😘 😗 ☺️ 😚 😙 🥲 😋 😛 😜 🤪 😝 🤑 🤗 🤭 🫢 🫣 🤫 🤔 🫡 🤐 🤨 😐 😑 \
        😶 🫥 😏 😒 🙄 😬 😮‍💨 🤥 😌 😔 😪 🤤 😴 😷 🤒 🤕 🤢 🤮 🤧 🥵 🥶 🥴 😵 🤯 🤠 🥳 🥸 😎 🤓 🧐 😕 🫤 😟 🙁 😮 😯 😲 😳 🥺 🥹 \
        😦 😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬 😈 👿 💀 ☠️ 💩 🤡 👹 👺 👻 👽 👾 🤖 😺 😸 😹 😻 😼 😽 🙀 😿 😾 \
        👋 🤚 🖐️ ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👈 👉 👆 🖕 👇 ☝️ 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 🫶 👐 🤲 🤝 🙏 ✍️ 💪 🧠 👀 👶 🧒 👦 \
        👧 🧑 👱 👨 🧔 👩 🧓 👴 👵 🧑‍💻 🧑‍🎨 🧑‍🚀 🧑‍🍳 🧑‍🏫 🧑‍🔬 🧑‍🎤 🦸 🦹 🧙 🧚 🧛 🧜 🧝 🧞 🧟
        """)),
        Category(id: "Animals & Nature", symbol: "sun.max", emoji: split("""
        🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐻‍❄️ 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🙈 🙉 🙊 🐒 🐔 🐧 🐦 🐤 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🪱 🐛 🦋 🐌 🐞 🐜 🪲 \
        🐢 🐍 🦎 🦖 🦕 🐙 🦑 🦐 🦞 🦀 🐡 🐠 🐟 🐬 🐳 🐋 🦈 🐊 🐅 🐆 🦓 🦍 🦧 🐘 🦛 🦏 🐪 🐫 🦒 🦘 🐃 🐂 🐄 🐎 🐖 🐏 🐑 🦙 🐐 🦌 \
        🐕 🐩 🐈 🐓 🦃 🦚 🦜 🦢 🦩 🕊️ 🐇 🦝 🦨 🦡 🦫 🦦 🦥 🐁 🐀 🐿️ 🦔 🌵 🎄 🌲 🌳 🌴 🪵 🌱 🌿 ☘️ 🍀 🎍 🪴 🎋 🍃 🍂 🍁 🍄 🐚 🪨 \
        🌾 💐 🌷 🌹 🥀 🌺 🌸 🌼 🌻 🌞 🌝 🌛 🌜 🌚 🌕 🌖 🌗 🌘 🌑 🌒 🌓 🌔 🌙 🌎 🌍 🌏 🪐 💫 ⭐️ 🌟 ✨ ⚡️ ☄️ 💥 🔥 🌪️ 🌈 ☀️ 🌤️ ⛅️ \
        🌥️ ☁️ 🌦️ 🌧️ ⛈️ 🌩️ 🌨️ ❄️ ☃️ ⛄️ 🌬️ 💨 💧 💦 ☔️ ☂️ 🌊 🌫️
        """)),
        Category(id: "Food & Drink", symbol: "cup.and.saucer", emoji: split("""
        🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥬 🥒 🌶️ 🫑 🌽 🥕 🫒 🧄 🧅 🥔 🍠 🥐 🥯 🍞 🥖 🥨 🧀 🥚 🍳 \
        🧈 🥞 🧇 🥓 🥩 🍗 🍖 🌭 🍔 🍟 🍕 🫓 🥪 🥙 🧆 🌮 🌯 🫔 🥗 🥘 🫕 🥫 🍝 🍜 🍲 🍛 🍣 🍱 🥟 🦪 🍤 🍙 🍚 🍘 🍥 🥠 🥮 🍢 🍡 🍧 \
        🍨 🍦 🥧 🧁 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🌰 🥜 🍯 🥛 🍼 🫖 ☕️ 🍵 🧃 🥤 🧋 🍶 🍺 🍻 🥂 🍷 🥃 🍸 🍹 🧉 🍾 🧊 🥄 🍴 🍽️ 🥣 🥡
        """)),
        Category(id: "Activity", symbol: "rosette", emoji: split("""
        ⚽️ 🏀 🏈 ⚾️ 🥎 🎾 🏐 🏉 🥏 🎱 🪀 🏓 🏸 🏒 🏑 🥍 🏏 🪃 🥅 ⛳️ 🪁 🏹 🎣 🤿 🥊 🥋 🎽 🛹 🛼 🛷 ⛸️ 🥌 🎿 ⛷️ 🏂 🪂 🏋️ 🤸 ⛹️ 🤺 \
        🤾 🏌️ 🏇 🧘 🏄 🏊 🤽 🚣 🧗 🚵 🚴 🏆 🥇 🥈 🥉 🏅 🎖️ 🏵️ 🎗️ 🎫 🎟️ 🎪 🤹 🎭 🩰 🎨 🎬 🎤 🎧 🎼 🎹 🥁 🪘 🎷 🎺 🪗 🎸 🪕 🎻 🎲 \
        ♟️ 🎯 🎳 🎮 🎰 🧩
        """)),
        Category(id: "Travel & Places", symbol: "box.truck", emoji: split("""
        🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐 🛻 🚚 🚛 🚜 🦯 🦽 🦼 🛴 🚲 🛵 🏍️ 🛺 🚨 🚔 🚍 🚘 🚖 🚡 🚠 🚟 🚃 🚋 🚞 🚝 🚄 🚅 🚈 🚂 🚆 🚇 \
        🚊 🚉 ✈️ 🛫 🛬 🛩️ 💺 🛰️ 🚀 🛸 🚁 🛶 ⛵️ 🚤 🛥️ 🛳️ ⛴️ 🚢 ⚓️ 🪝 ⛽️ 🚧 🚦 🚥 🚏 🗺️ 🗿 🗽 🗼 🏰 🏯 🏟️ 🎡 🎢 🎠 ⛲️ ⛱️ 🏖️ 🏝️ 🏜️ \
        🌋 ⛰️ 🏔️ 🗻 🏕️ ⛺️ 🛖 🏠 🏡 🏘️ 🏚️ 🏗️ 🏭 🏢 🏬 🏣 🏤 🏥 🏦 🏨 🏪 🏫 🏩 💒 🏛️ ⛪️ 🕌 🕍 🛕 🕋 ⛩️ 🛤️ 🛣️ 🗾 🎑 🏞️ 🌅 🌄 🌠 🎇 \
        🎆 🌇 🌆 🏙️ 🌃 🌌 🌉 🌁
        """)),
        Category(id: "Objects", symbol: "gift", emoji: split("""
        ⌚️ 📱 📲 💻 ⌨️ 🖥️ 🖨️ 🖱️ 🖲️ 🕹️ 🗜️ 💽 💾 💿 📀 📼 📷 📸 📹 🎥 📽️ 🎞️ 📞 ☎️ 📟 📠 📺 📻 🎙️ 🎚️ 🎛️ 🧭 ⏱️ ⏲️ ⏰ 🕰️ ⌛️ ⏳ 📡 🔋 \
        🔌 💡 🔦 🕯️ 🪔 🧯 🛢️ 💸 💵 💴 💶 💷 🪙 💰 💳 💎 ⚖️ 🪜 🧰 🪛 🔧 🔨 ⚒️ 🛠️ ⛏️ 🪚 🔩 ⚙️ 🪤 🧱 ⛓️ 🧲 🔫 💣 🧨 🪓 🔪 🗡️ ⚔️ 🛡️ \
        🚬 ⚰️ 🪦 ⚱️ 🏺 🔮 📿 🧿 💈 ⚗️ 🔭 🔬 🕳️ 🩹 🩺 💊 💉 🩸 🧬 🦠 🧫 🧪 🌡️ 🧹 🪠 🧺 🧻 🚽 🚰 🚿 🛁 🛀 🧼 🪥 🪒 🧽 🪣 🧴 🛎️ 🔑 \
        🗝️ 🚪 🪑 🛋️ 🛏️ 🛌 🧸 🪆 🖼️ 🪞 🪟 🛍️ 🛒 🎁 🎈 🎏 🎀 🪄 🪅 🎊 🎉 🎎 🏮 🎐 🧧 ✉️ 📩 📨 📧 💌 📥 📤 📦 🏷️ 🪧 📪 📫 📬 📭 📮 \
        📯 📜 📃 📄 📑 🧾 📊 📈 📉 🗒️ 🗓️ 📆 📅 🗑️ 📇 🗃️ 🗳️ 🗄️ 📋 📁 📂 🗂️ 🗞️ 📰 📓 📔 📒 📕 📗 📘 📙 📚 📖 🔖 🧷 🔗 📎 🖇️ 📐 📏 \
        🧮 📌 📍 ✂️ 🖊️ 🖋️ ✒️ 🖌️ 🖍️ 📝 ✏️ 🔍 🔎 🔏 🔐 🔒 🔓
        """)),
        Category(id: "Symbols", symbol: "heart", emoji: split("""
        ❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 ☮️ ✝️ ☪️ 🕉️ ☸️ ✡️ 🔯 🕎 ☯️ ☦️ 🛐 ⛎ ♈️ ♉️ ♊️ ♋️ ♌️ ♍️ ♎️ ♏️ ♐️ \
        ♑️ ♒️ ♓️ 🆔 ⚛️ 🉑 ☢️ ☣️ 📴 📳 🈶 🈚️ 🈸 🈺 🈷️ ✴️ 🆚 💮 🉐 ㊙️ ㊗️ 🈴 🈵 🈹 🈲 🅰️ 🅱️ 🆎 🆑 🅾️ 🆘 ❌ ⭕️ 🛑 ⛔️ 📛 🚫 💯 💢 ♨️ \
        🚷 🚯 🚳 🚱 🔞 📵 🚭 ❗️ ❕ ❓ ❔ ‼️ ⁉️ 🔅 🔆 〽️ ⚠️ 🚸 🔱 ⚜️ 🔰 ♻️ ✅ 🈯️ 💹 ❇️ ✳️ ❎ 🌐 💠 Ⓜ️ 🌀 💤 🏧 🚾 ♿️ 🅿️ 🛗 🈳 🈂️ \
        🛂 🛃 🛄 🛅 🚹 🚺 🚼 ⚧️ 🚻 🚮 🎦 📶 🈁 🔣 ℹ️ 🔤 🔡 🔠 🆖 🆗 🆙 🆒 🆕 🆓 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟 🔢 #️⃣ *️⃣ ⏏️ ▶️ \
        ⏸️ ⏯️ ⏹️ ⏺️ ⏭️ ⏮️ ⏩ ⏪ ⏫ ⏬ ◀️ 🔼 🔽 ➡️ ⬅️ ⬆️ ⬇️ ↗️ ↘️ ↙️ ↖️ ↕️ ↔️ ↪️ ↩️ ⤴️ ⤵️ 🔀 🔁 🔂 🔄 🔃 🎵 🎶 ➕ ➖ ➗ ✖️ 🟰 ♾️ \
        💲 💱 ™️ ©️ ®️ 〰️ ➰ ➿ 🔚 🔙 🔛 🔝 🔜 ✔️ ☑️ 🔘 🔴 🟠 🟡 🟢 🔵 🟣 ⚫️ ⚪️ 🟤 🔺 🔻 🔸 🔹 🔶 🔷 🔳 🔲 ▪️ ▫️ ◾️ ◽️ ◼️ ◻️ 🟥 \
        🟧 🟨 🟩 🟦 🟪 ⬛️ ⬜️ 🟫 🔈 🔇 🔉 🔊 🔔 🔕 📣 📢 💬 💭 🗯️ ♠️ ♣️ ♥️ ♦️ 🃏 🎴 🀄️
        """)),
        Category(id: "Flags", symbol: "flag", emoji: split("""
        🏳️ 🏴 🏁 🚩 🏳️‍🌈 🏳️‍⚧️ 🏴‍☠️ 🇦🇷 🇦🇺 🇦🇹 🇧🇪 🇧🇷 🇨🇦 🇨🇱 🇨🇳 🇨🇴 🇨🇿 🇩🇰 🇪🇬 🇫🇮 🇫🇷 🇩🇪 🇬🇷 🇭🇰 🇭🇺 🇮🇸 🇮🇳 🇮🇩 🇮🇪 🇮🇱 🇮🇹 🇯🇵 🇰🇪 🇲🇾 🇲🇽 🇳🇱 🇳🇿 🇳🇬 🇳🇴 🇵🇰 \
        🇵🇪 🇵🇭 🇵🇱 🇵🇹 🇷🇴 🇸🇦 🇸🇬 🇿🇦 🇰🇷 🇪🇸 🇸🇪 🇨🇭 🇹🇼 🇹🇭 🇹🇷 🇺🇦 🇦🇪 🇬🇧 🇺🇸 🇻🇳 🇪🇺 🇺🇳
        """)),
    ]

    private static func split(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\\" }).map(String.init)
    }

    /// Search by the emoji's Unicode names (every scalar's name, so 🧑‍💻 matches "computer"). Empty query: all.
    static func matching(_ query: String) -> [String] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let all = categories.flatMap(\.emoji)
        guard !words.isEmpty else { return all }
        return all.filter { emoji in
            let names = emoji.unicodeScalars.compactMap(\.properties.name).joined(separator: " ").lowercased()
            return words.allSatisfy { names.contains($0) }
        }
    }
}

/// What the picker reports: the chosen icon (`.none` from the Icon page's first cell).
@MainActor
final class IconPickerModel: ObservableObject {
    @Published var icon: SpaceIcon
    let pick: (SpaceIcon) -> Void
    init(icon: SpaceIcon, pick: @escaping (SpaceIcon) -> Void) {
        self.icon = icon
        self.pick = pick
    }
}

struct SpaceIconPickerView: View {
    @ObservedObject var model: IconPickerModel
    @State private var page = 0
    @State private var query = ""
    @State private var category = EmojiCatalog.categories[0].id
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var ink: Color { colorScheme == .dark ? .white : .black }
    private let m = IconPicker

    var body: some View {
        VStack(spacing: 0) {
            tabs.padding(.top, 14)
            if page == 0 { emojiPage } else { iconPage }
        }
        .frame(width: m.size.value.width, height: m.size.value.height)
        .onAppear { searchFocused = true }
        .spaceToolsID("icon-picker")
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(Array(["Emoji", "Icon"].enumerated()), id: \.offset) { index, title in
                Button { page = index } label: {
                    Text(title).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(page == index ? Color.white : ink.opacity(0.75))
                        .frame(width: 53, height: m.tabsHeight.value)
                        .background(RoundedRectangle(cornerRadius: m.radius.value, style: .continuous)
                            .fill(page == index ? Color(nsColor: OverlayColors.of(.light).focusRing) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .spaceToolsID("icon-picker-\(title.lowercased())")
            }
        }
        .background(RoundedRectangle(cornerRadius: m.radius.value, style: .continuous).fill(ink.opacity(0.07)))
    }

    private var emojiPage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(ink.opacity(0.5))
                TextField("Search", text: $query).textFieldStyle(.plain).font(.system(size: 14)).focused($searchFocused)
                    .spaceToolsID("icon-picker-search")
            }
            .padding(.horizontal, 6)
            .frame(height: m.searchHeight.value)
            .background(RoundedRectangle(cornerRadius: m.searchRadius.value, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: m.searchRadius.value, style: .continuous)
                .stroke(Color(nsColor: OverlayColors.of(.light).focusRing).opacity(searchFocused ? 0.75 : 0), lineWidth: 3))
            .padding(.horizontal, 9.5).padding(.top, 8).padding(.bottom, 3)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    if query.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(EmojiCatalog.categories) { group in grid(group.emoji).id(group.id) }
                        }
                    } else {
                        grid(EmojiCatalog.matching(query))
                    }
                }
                .onChange(of: category) { _, id in withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) } }
            }
            Rectangle().fill(ink.opacity(0.1)).frame(height: 0.5).padding(.horizontal, 12)
            HStack(spacing: 0) {
                ForEach(EmojiCatalog.categories) { group in
                    Button { query = ""; category = group.id } label: {
                        Image(systemName: group.symbol).font(.system(size: 14)).foregroundStyle(ink.opacity(0.55))
                            .frame(maxWidth: .infinity, minHeight: m.categoriesHeight.value).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help(group.id).accessibilityLabel(group.id)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func grid(_ emoji: [String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(m.cell.value.width), spacing: 0), count: m.columns.value), spacing: 0) {
            ForEach(Array(emoji.enumerated()), id: \.offset) { index, value in
                Button { model.pick(.custom(.emoji(value))) } label: {
                    Text(value).font(.system(size: m.emojiSize.value))
                        .frame(width: m.cell.value.width, height: m.cell.value.height).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value)
                .spaceToolsID(query.isEmpty ? "icon-emoji-\(value)" : "icon-result-\(index)")
            }
        }
        .padding(.horizontal, 12)
    }

    private var iconPage: some View {
        let columns = Array(repeating: GridItem(.fixed(m.cell.value.width + 4), spacing: 0), count: 7)
        return ScrollView(.vertical) {
            LazyVGrid(columns: columns, spacing: 2) {
                Button { model.pick(SpaceIcon.none) } label: {
                    Circle().fill(ink.opacity(0.5)).frame(width: 8, height: 8)
                        .frame(width: m.cell.value.width + 4, height: m.cell.value.height).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(OverlayCopy.noIcon).accessibilityLabel(OverlayCopy.noIcon).spaceToolsID("icon-none")
                ForEach(NamedIcon.allCases, id: \.self) { name in
                    Button { model.pick(.custom(.named(name))) } label: {
                        NamedIconImage(icon: name, size: 16).foregroundStyle(ink.opacity(0.7))
                            .frame(width: m.cell.value.width + 4, height: m.cell.value.height)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(model.icon == .custom(.named(name)) ? ink.opacity(0.08) : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help(name.rawValue.capitalized).accessibilityLabel(name.rawValue.capitalized)
                    .spaceToolsID("icon-named-\(name.rawValue)")
                }
            }
            .padding(12)
        }
    }
}

/// The popover around the picker. Closing it any way (a pick, a click outside, Esc) calls `closed` once.
@MainActor
final class IconPickerPopover: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let model: IconPickerModel
    private let closed: () -> Void
    private var reported = false

    init(icon: SpaceIcon, pick: @escaping (SpaceIcon) -> Void, closed: @escaping () -> Void) {
        self.closed = closed
        var finish: (() -> Void)?
        model = IconPickerModel(icon: icon) { icon in pick(icon); finish?() }
        super.init()
        finish = { [weak self] in self?.popover.performClose(nil) }
        // Closes on a click elsewhere in the browser window, not when the app is merely activated or left.
        popover.behavior = .semitransient
        popover.animates = false
        popover.contentSize = IconPicker.size.value
        popover.contentViewController = .firstClick(SpaceIconPickerView(model: model))
        popover.delegate = self
    }

    var isShown: Bool { popover.isShown }

    func show(relativeTo rect: CGRect, of view: NSView, scheme: Scheme) {
        popover.appearance = .of(scheme)
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
    }

    func dismiss() {
        reported = true
        popover.close()
    }

    func popoverDidClose(_ notification: Notification) {
        guard !reported else { return }
        reported = true
        closed()
    }
}

/// A named icon in SwiftUI: its SF Symbol at `size`, or the drawn glyph for the four Arc icons SF Symbols lacks
/// (`NamedIconArt`). Without a size it takes the surrounding font's (13 pt).
struct NamedIconImage: View {
    let icon: NamedIcon
    var size: Double? = nil
    var body: some View {
        if let art = NamedIconArt.drawnImage(icon, pointSize: size ?? 13) {
            Image(nsImage: art).renderingMode(.template)
        } else if let size {
            Image(systemName: NamedIconSymbol.of(icon)).font(.system(size: size))
        } else {
            Image(systemName: NamedIconSymbol.of(icon))
        }
    }
}
