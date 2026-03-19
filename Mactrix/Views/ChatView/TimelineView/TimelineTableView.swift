import AppKit
import MatrixRustSDK
import OSLog
import SwiftUI
import UI

enum TimelineItemRowInfo {
    case message(event: EventTimelineItem, content: MsgLikeContent)
    case state(event: EventTimelineItem)
    case virtual(virtual: VirtualTimelineItem)

    var reuseIdentifier: NSUserInterfaceItemIdentifier {
        switch self {
        case .message:
            return NSUserInterfaceItemIdentifier("message")
        case .state:
            return NSUserInterfaceItemIdentifier("state")
        case .virtual:
            return NSUserInterfaceItemIdentifier("virtual")
        }
    }
}

extension TimelineItem {
    var rowInfo: TimelineItemRowInfo {
        if let virtual = asVirtual() {
            return .virtual(virtual: virtual)
        }

        if let event = asEvent() {
            switch event.content {
            case .msgLike(content: let content):
                return .message(event: event, content: content)
            default:
                return .state(event: event)
            }
        }

        fatalError("unreachable state: item must be either virtual or event")
    }
}

class TimelineViewController: NSViewController {
    let coordinator: TimelineViewRepresentable.Coordinator

    private var dataSource: NSTableViewDiffableDataSource<TimelineSection, TimelineUniqueId>?

    let scrollView = NSScrollView()
    let tableView = BottomStickyTableView()

    let timeline: LiveTimeline
    var timelineItems: [TimelineItem]
    let scrollState = TimelineScrollState()

    init(coordinator: TimelineViewRepresentable.Coordinator, timeline: LiveTimeline, timelineItems: [TimelineItem]) {
        self.coordinator = coordinator
        self.timeline = timeline
        self.timelineItems = timelineItems
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.addTableColumn(NSTableColumn())
        tableView.headerView = nil
        tableView.style = .plain
        tableView.allowsColumnSelection = false
        tableView.selectionHighlightStyle = .none

        tableView.rowHeight = -1
        tableView.usesAutomaticRowHeights = true

        oldWidth = tableView.frame.width

        dataSource = .init(tableView: tableView) { [weak self] tableView, _, row, _ in
            guard let self else { return NSView() }

            let item = timelineItems[row]
            let rowView: TimelineMessageRowNSView
            if let recycled = tableView.makeView(withIdentifier: item.rowInfo.reuseIdentifier, owner: self)
                as? TimelineMessageRowNSView
            {
                rowView = recycled
            } else {
                rowView = TimelineMessageRowNSView()
                rowView.identifier = item.rowInfo.reuseIdentifier
                rowView.autoresizingMask = [.width, .height]
            }
            rowView.scrollState = scrollState
            rowView.configure(
                rowInfo: item.rowInfo,
                timeline: timeline,
                appState: coordinator.appState,
                windowState: coordinator.windowState
            )
            return rowView
        }

        tableView.delegate = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        tableView.backgroundColor = .clear
        view = scrollView

        // Subscribe to view resize notifications
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTableResize),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(viewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        listenForFocusTimelineItem()
    }

    @objc func handleTableResize(_ notification: Notification) {
        if oldWidth != tableView.frame.width {
            oldWidth = tableView.frame.width

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false

                let visibleRect = tableView.visibleRect
                let visibleRows = tableView.rows(in: visibleRect)
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: visibleRows.lowerBound ..< visibleRows.upperBound))
            }
        }
    }

    var timelineFetchTask: Task<Void, Never>?
    private var scrollHoverTimer: Timer?

    @objc func viewDidScroll(_ notification: Notification) {
        // Suppress hover during scrolling
        scrollState.suppressHover = true
        scrollHoverTimer?.invalidate()
        scrollHoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self else { return }
            scrollState.suppressHover = false
            reactivateHoverUnderMouse()
        }

        // Dismiss hover on all visible message rows
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        for row in visibleRows.lowerBound..<visibleRows.upperBound {
            if let rowView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TimelineMessageRowNSView {
                rowView.dismissHover()
            }
        }

        let currentOffset = scrollView.contentView.bounds.origin.y
        let timelineHeight = scrollView.contentView.documentRect.height
        let viewHeight = scrollView.contentView.documentVisibleRect.height

        let distanceFromTop = timelineHeight - viewHeight - currentOffset
        let threshold: CGFloat = 200.0 // Pixels from the top to trigger load

        if distanceFromTop <= threshold, timelineFetchTask == nil {
            Logger.timelineTableView.info("Fetching older messages (scroll near top)")
            timelineFetchTask = Task {
                do {
                    try await timeline.fetchOlderMessages()
                } catch {
                    Logger.timelineTableView.error("Failed to fetch older messages: \(error)")
                }

                timelineFetchTask = nil
            }
        }
    }

    private func reactivateHoverUnderMouse() {
        guard let window = tableView.window else { return }
        let windowPoint = window.mouseLocationOutsideOfEventStream
        let tablePoint = tableView.convert(windowPoint, from: nil)
        let row = tableView.row(at: tablePoint)
        guard row >= 0,
              let rowView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TimelineMessageRowNSView
        else { return }
        rowView.activateHover()
    }

    func listenForFocusTimelineItem() {
        Logger.timelineTableView.debug("Listen for focus timeline item")

        let focusedTimelineEventId = withObservationTracking {
            timeline.focusedTimelineEventId
        } onChange: {
            Task { @MainActor in self.listenForFocusTimelineItem() }
        }

        guard let focusedTimelineEventId,
              let rowIndex = timelineItems.firstIndex(where: {
                  $0.asEvent()?.eventOrTransactionId == focusedTimelineEventId
              }) else { return }

        tableView.animateRowToVisible(rowIndex)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    enum TimelineSection {
        case main
        case typingIndicator
    }

    func updateTimelineItems(_ timelineItems: [TimelineItem]) {
        Logger.timelineTableView.info("update timeline items")

        let oldIds = self.timelineItems.map { $0.uniqueId().id }
        self.timelineItems = timelineItems.reversed()
        let newIds = self.timelineItems.map { $0.uniqueId().id }

        // If the IDs haven't changed, reload all rows in place (content-only update: reactions, read receipts, etc.)
        // Reloads all rows rather than just visible ones to avoid stale content in NSTableView's prepared/cached views.
        if oldIds == newIds {
            tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<self.timelineItems.count),
                                 columnIndexes: IndexSet(integer: 0))
            return
        }

        var snapshot = NSDiffableDataSourceSnapshot<TimelineSection, TimelineUniqueId>()
        snapshot.appendSections([.main])

        for item in self.timelineItems {
            snapshot.appendItems([.init(id: item.uniqueId().id)], toSection: .main)
        }

        dataSource?.apply(snapshot, animatingDifferences: false)

        // Re-measure visible rows after hosting views settle
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: visibleRows.lowerBound..<visibleRows.upperBound))
        }
    }

    // values used to track width changes
    var oldWidth: CGFloat?
}

extension TimelineViewController: NSTableViewDelegate {
    func selectionShouldChange(in tableView: NSTableView) -> Bool {
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let item = timelineItems[row]

        switch item.rowInfo {
        case .message(_, let content):
            if case .message(let msg) = content.kind {
                switch msg.msgType {
                case .image(let img):
                    let maxH: CGFloat = min(CGFloat(img.info?.height ?? 300), 300)
                    return maxH + 60
                case .video(let vid):
                    let maxH: CGFloat = min(CGFloat(vid.info?.height ?? 300), 300)
                    return maxH + 60
                default:
                    break
                }
            }
            return 44
        case .state:
            return 30
        case .virtual:
            return 40
        }
    }
}

class BottomStickyTableView: NSTableView {
    // By returning false, the table starts drawing from the bottom up
    override var isFlipped: Bool {
        return false
    }
}
