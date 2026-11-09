import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// A scroll view of the panel's that lets every scroll event go through the window, one at a time, as the sidebar's list
/// does (`TablistView`): with AppKit's responsive scrolling it would take a whole gesture after its first event, and the
/// panel's swipe between its pages would never see it.
@MainActor
final class AIPanelScrollView: NSScrollView {
    override class var isCompatibleWithResponsiveScrolling: Bool { false }
}

/// The AI panel's column (docs/design/ai-threads.md): two pages side by side, this Space's conversation list and then the
/// conversation, the way the sidebar holds the Library and then the Spaces. A two-finger swipe with the pointer over the
/// panel moves between them with the sidebar's own gesture, tracking and spring (`PageSwipeGesture`, `PagePager`); the
/// dots at its foot and the header's list icon do the same for a mouse. Only the page the fingers settle on reaches the
/// document (`AIIntent.panelPage`). A page drawn in the transcript that scrolls sideways (a wide table) takes the swipe
/// first, as a web card does. In an incognito or Little window the panel has no list: only the conversation page.
@MainActor
final class AIPanelView: NSView {
    private let dispatch: Dispatch
    let conversation: AIAnswerDocumentView
    let list: AIThreadListView
    private let clip = AIFlippedView()
    private let strip = AIFlippedView()
    private let dots = AIPanelDotsView()
    private let pager = PagePager<AIPanelPage>()
    private let gesture = PageSwipeGesture()
    private var panel: AIPanelSnapshot?
    private var answer: AIAnswerSnapshot?
    private var style: AIPanelStyle?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        conversation = AIAnswerDocumentView(dispatch: dispatch)
        list = AIThreadListView(dispatch: dispatch)
        super.init(frame: .zero)
        isHidden = true
        identify(.aiControl("panel"))
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        strip.addSubview(list)
        strip.addSubview(conversation)
        clip.addSubview(strip)
        addSubview(clip)
        addSubview(dots)
        conversation.onList = { dispatch(.assist(.panelPage(.list))) }
        list.onBack = { dispatch(.assist(.panelPage(.conversation))) }
        dots.onPick = { page in dispatch(.assist(.panelPage(page))) }
        pager.host = self
        pager.onMove = { [weak self] in self?.applyPosition() }
        pager.onSelect = { page in dispatch(.assist(.panelPage(page))) }
        pager.onSettled = { [weak self] in self?.applyPosition() }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    /// The conversation page's view, for the drop target and the page edits it commits.
    var answerView: AIAnswerDocumentView { conversation }

    func render(_ answer: AIAnswerSnapshot?, panel: AIPanelSnapshot?, agents: AIAgentMenu? = nil, in area: CGRect, theme: ResolvedTheme?) {
        guard answer != nil || panel != nil else {
            self.answer = nil; self.panel = nil
            isHidden = true
            gesture.reset(pager)
            conversation.render(nil, in: .zero)
            return
        }
        isHidden = false
        if frame != area { frame = area }
        let theme = theme ?? .fallbackLight
        let style = AIPanelStyle(theme)
        self.style = style
        self.answer = answer
        self.panel = panel
        conversation.agents = agents
        let reserve = panel == nil ? 0 : Metrics.ai.dotsHeight.value
        conversation.bottomReserve = reserve
        list.bottomReserve = reserve
        if let answer { conversation.render(answer, in: CGRect(origin: .zero, size: area.size), theme: theme) }
        else { conversation.render(nil, in: .zero) }
        conversation.showList(panel)
        list.isHidden = panel == nil
        if let panel { list.render(panel, style: style) }
        dots.isHidden = panel == nil || !(panel?.hasConversation ?? false)
        if let panel { dots.apply(style, language: panel.language) }
        // The row of pages: the list, then the conversation when there is one.
        var pages: [AIPanelPage] = []
        if panel != nil { pages.append(.list) }
        if answer != nil { pages.append(.conversation) }
        pager.update(pages: pages, widths: pages.map { _ in Double(area.width) })
        let wanted: AIPanelPage = panel?.page ?? .conversation
        if pager.selectedPage != wanted, !pager.isTracking, pages.contains(wanted) { pager.select(wanted, animated: true) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        clip.frame = bounds
        dots.frame = CGRect(x: 0, y: bounds.height - Metrics.ai.dotsHeight.value, width: bounds.width, height: Metrics.ai.dotsHeight.value)
        let width = bounds.width
        let pages = pager.pages
        list.frame = CGRect(x: CGFloat(pages.firstIndex(of: .list) ?? 0) * width, y: 0, width: width, height: bounds.height)
        conversation.frame = CGRect(x: CGFloat(pages.firstIndex(of: .conversation) ?? 0) * width, y: 0, width: width, height: bounds.height)
        strip.frame = CGRect(x: 0, y: 0, width: width * CGFloat(max(1, pages.count)), height: bounds.height)
        applyPosition()
    }

    /// The pages where the position says, and the dots' darkness between them.
    private func applyPosition() {
        let position = pager.position
        strip.setFrameOrigin(CGPoint(x: -position.rounded(), y: 0))
        let origins = pager.origins
        if let pair = PageSwipeRule.pair(at: max(0, position), origins: origins), pager.pages.count == 2 {
            let progress = pair.floor == pair.ceil ? Double(pair.floor) : Double(pair.floor) + pair.progress
            dots.progress = min(max(progress, 0), 1)
        } else {
            dots.progress = pager.pages.first == .conversation ? 1 : 0
        }
        // Keys and the pointer belong to the page that shows.
        let showing = pager.isActive ? nil : pager.selectedPage
        list.isHidden = panel == nil || (showing != nil && showing != .list && !pager.isActive)
        conversation.isHidden = answer == nil || (showing != nil && showing != .conversation && !pager.isActive)
    }

    // MARK: The swipe

    /// A two-finger gesture over the panel. False: not the panel's (the pointer was elsewhere, a vertical scroll, a page
    /// in the transcript that scrolls sideways).
    func handleScrollWheel(_ event: NSEvent) -> Bool {
        guard !isHidden, panel != nil, pager.pages.count > 1, window?.isVisible == true, window?.attachedSheet == nil else {
            gesture.reset(pager); return false
        }
        let point = convert(event.locationInWindow, from: nil)
        let starts = bounds.contains(point) && !conversation.scrollsSideways(atWindowPoint: event.locationInWindow)
        return gesture.handle(event, starts: starts, pager: pager, window: window) { _ in }
    }

    /// Tabs dragged from the sidebar are over the panel.
    func showDropTarget(_ on: Bool) { conversation.showDropTarget(on) }

    func commitPageEdits() async { await conversation.commitPageEdits() }
}
