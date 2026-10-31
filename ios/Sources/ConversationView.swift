import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CmuxRemoteCore
import CmuxRemoteClient

struct ConversationView: View {
    @State private var model: ConversationModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @State private var atLatest = true
    @State private var userScrolling = false
    @State private var latestVisible = true
    @State private var initiallyScrolled = false
    /// Whether this visit has already opened the page; a return from a pushed page must not re-open it.
    @State private var openedConversation = false
    /// The opening scroll, which waits for the stored copy to appear before it settles.
    @State private var initialScroll: Task<Void, Never>?
    /// Retries the opening jump: a row's height is known only after it lays out.
    @State private var settleTask: Task<Void, Never>?
    /// The reader opened or closed a card: the page stays where it is until they scroll or ask for the latest.
    @State private var holdingPlace = false
    /// A prompt this phone just sent, held at the top of the page until the reader scrolls or asks for the latest.
    ///
    /// It starts as the outgoing bubble, which the transcript then replaces with the recorded message; the pin
    /// follows the text into that row so the page does not move when the swap happens.
    @State private var pinnedSent: PinnedPrompt?
    /// The content height before the page's blank tail, which decides how much tail still fits.
    @State private var timelineContentHeight: CGFloat = 0
    /// The scrolling page's own height: the filler is laid out in the scroll view's coordinates, not the
    /// screen's, so it must be the scroll view's height that fills it.
    @State private var scrollHeight: CGFloat = 0
    /// The pinned prompt's own height, which with the page's foot is all the room its tail leaves.
    @State private var pinnedRowHeight: CGFloat = 0
    @State private var scrollTrace = ScrollTrace()
    /// A message opened on its own page to select part of it.
    @State private var selecting: SelectTextPage.Request?
    @State private var showProject = false
    @State private var selectedFile = ""
    @State private var showFeed = false
    @State private var showTiming = false
    @State private var confirmHardStop = false
    @State private var showingPhotos = false
    @State private var showingImageFiles = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var confirmPendingReset = false
    @State private var showRename = false
    @State private var renameDraft = ""
    @State private var selectedImage: ConversationImageReference?
    @State private var selectedToolDetail: ToolDetailReference?
    /// The page's height above the keyboard; the composer may use half of it.
    @State private var pageHeight: CGFloat = 700
    @FocusState private var composerFocused: Bool
    /// This Mac's link, shown above the conversation while it is not up.
    @State private var linkState: LinkState?
    /// When another page of earlier messages may load. Scrolling past the top fires a geometry change for every
    /// layout pass, and a prepended page changes the layout again: without a pause the loader chained page after
    /// page, each one re-laying the whole list and scrolling, and a long conversation simply froze.
    @State private var nextPageAllowed = Date.distantPast
    /// Set while the pull gesture's own refresh control is on screen, so the timeline does not draw a second spinner
    /// for the same load.
    @State private var pulling = false
    private let hostName: String
    init(model: ConversationModel, hostName: String = "") {
        _model = State(initialValue: model); self.hostName = hostName
    }
    /// The first history read has not answered yet: the page is loading, not empty.
    ///
    /// Drawn as a centred overlay instead of a row, because the empty timeline's blank tail rests an only row
    /// against the composer, where the label would sit half under it.
    private var showsInitialLoading: Bool { model.messages.isEmpty && model.error == nil && model.historyGeneration == nil }
    var body: some View {
        timelineScroller()
        .background(Color.white.ignoresSafeArea())
        .background(InteractivePopInstaller())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 6) {
                header
                ConnectionStatusBar(state: linkState) { Task { await reconnect() } }
            }
            // A translucent white veil, like the page itself: content shows faintly under it, with no material
            // tint and no per-row rasterization.
            .background(Color.white.opacity(0.95))
        }
        .task { for await state in model.client.linkStates() { linkState = state } }
        // The first page lands, then the rest of the conversation is filled into the store in the background.
        .onChange(of: model.historyGeneration) { _, _ in model.startBackfill() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                SpeechDraftStrip(model: model.speech, useText: model.useSpeechDraft)
                if model.imageDraft.loading { ProgressView(String(localized: "image.preparing")) }
                if let error = model.imageDraft.error { Text(error).font(.footnote).foregroundStyle(.red) }
                if (model.pendingSend != nil || model.recoveryFailed) && !model.busy {
                    HStack {
                        if model.pendingSend != nil { Button(String(localized: "operation.check")) { Task { await model.checkPendingSend() } }.disabled(model.busy) }
                        Button(String(localized: "operation.inspected")) { confirmPendingReset = true }.disabled(model.busy)
                    }.font(.footnote).buttonStyle(FloatingButtonStyle())
                }
                // Tasks the agent detached outlive the turn that started them, so this shows whenever any run.
                if !model.backgroundTasks.isEmpty { BackgroundTasksBar(tasks: model.backgroundTasks, sessionID: model.session.id, client: model.client) }
                if model.stopRequested {
                    Label(String(localized: "chat.stop_requested"), systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary)
                } else if model.hasActiveResponse {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        if let start = model.runningSince { LiveRunLabel(since: start, compacting: model.compacting, showsMark: false) }
                        else { Text(String(localized: "chat.working")).font(.footnote) }
                        Spacer(); Label(model.session.agent.capitalized, systemImage: "sparkles").font(.caption)
                    }.foregroundStyle(.secondary).padding(.horizontal, 12)
                } else if model.canResume {
                    // The Agent's terminal is gone but its session can be reopened, so the page offers that instead
                    // of a composer that would have nowhere to type.
                    Button { Task { await model.resume() } } label: {
                        Label(String(localized: "sessions.resume"), systemImage: "arrow.clockwise.circle")
                    }
                    .buttonStyle(FloatingButtonStyle(prominent: true)).disabled(model.busy)
                    .accessibilityIdentifier("sessions.resume")
                } else if !model.canSend { Text(String(localized: "sessions.read_only")).font(.caption).foregroundStyle(.secondary) }
                composer
            }.padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
            .background(Color.white.opacity(0.95))
        }
        .photosPicker(isPresented: $showingPhotos, selection: $photoItems, maxSelectionCount: max(1, 4 - model.imageDraft.images.count), selectionBehavior: .ordered, matching: .images)
        .fileImporter(isPresented: $showingImageFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                photoLoadTask?.cancel(); model.imageDraft.cancelLoading()
                let selections = urls.map { url in ImageSelection(name: url.lastPathComponent, load: { try await ImageFileLoader().load(url) }) }
                photoLoadTask = Task { await model.imageDraft.load(selections, encode: ImageAttachmentEncoder().encode) }
            case .failure(let error):
                if (error as NSError).code != CocoaError.userCancelled.rawValue { model.imageDraft.error = String(localized: "error.image_load") }
            }
        }
        .onChange(of: photoItems) { _, selected in
            photoLoadTask?.cancel(); model.imageDraft.cancelLoading()
            let selections = selected.enumerated().map { index, item in
                ImageSelection(name: "Image-\(index + 1).jpg", load: {
                    guard let data = try await item.loadTransferable(type: PhotoSelectionFile.self) else { throw BridgeError("invalid_image", "The selected image is unavailable.", status: 422) }
                    return data.data
                })
            }
            photoLoadTask = Task { await model.imageDraft.load(selections, encode: ImageAttachmentEncoder().encode) }
        }
        .onDisappear { model.speech.suspend(); model.suspendReads(); photoLoadTask?.cancel(); model.imageDraft.cancelLoading() }
        .onChange(of: phase) { _, value in if value == .background { model.speech.suspend() }; if value != .active { model.suspendReads(); photoLoadTask?.cancel(); model.imageDraft.cancelLoading() } }
        .alert(String(localized: "model.confirm_title"), isPresented: Binding(get: { model.modelAwaitingConfirmation != nil }, set: { if !$0 { model.modelAwaitingConfirmation = nil } })) {
            Button(String(localized: "model.switch")) {
                if let pending = model.modelAwaitingConfirmation { Task { await model.switchModel(to: pending.name, label: pending.label, confirmed: true) } }
            }
            Button(String(localized: "pair.cancel"), role: .cancel) {}
        } message: { Text(String(format: String(localized: "model.confirm_note"), model.modelAwaitingConfirmation?.label ?? "")) }
        .alert(String(localized: "chat.rename_title"), isPresented: $showRename) {
            TextField(String(localized: "chat.rename_placeholder"), text: $renameDraft)
            Button(String(localized: "chat.rename_save")) { let title = renameDraft; Task { await model.rename(to: title) } }
            Button(String(localized: "pair.cancel"), role: .cancel) {}
        } message: { Text(String(localized: "chat.rename_note")) }
        .alert(String(localized: "operation.inspected"), isPresented: $confirmPendingReset) {
            Button(String(localized: "operation.release")) { Task { await model.acknowledgePendingSend() } }
            Button(String(localized: "pair.cancel"), role: .cancel) {}
        } message: { Text(String(localized: "operation.inspect_note")) }
        .navigationDestination(isPresented: $showProject) { ProjectView(session: model.session, client: model.client, initialPath: selectedFile) }
        .navigationDestination(isPresented: $showFeed) { FeedView(client: model.client) }
        .navigationDestination(isPresented: Binding(get: { selectedImage != nil }, set: { if !$0 { selectedImage = nil } })) {
            if let reference = selectedImage { HistoricalImageView(reference: reference, sessionID: model.session.id, client: model.client) }
        }
        .navigationDestination(isPresented: Binding(get: { selectedToolDetail != nil }, set: { if !$0 { selectedToolDetail = nil } })) {
            if let reference = selectedToolDetail { ToolDetailView(reference: reference, sessionID: model.session.id, client: model.client) }
        }
        .navigationDestination(isPresented: $showTiming) {
                WhitePage(title: String(localized: "chat.timing")) {
                    VStack(alignment: .leading, spacing: 18) {
                        if let seconds = model.recordedRunSeconds {
                            ResponseRunLabel(seconds: seconds, recorded: true)
                            Text(String.localizedStringWithFormat(String(localized: "chat.recorded_turns"), model.recordedTurnCount)).font(.footnote).foregroundStyle(.secondary)
                        } else { Text(String(localized: "chat.no_timing")).foregroundStyle(.secondary) }
                        Text(String(localized: "chat.timing_note")).font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(MobileDesign.pageInset)
                }
        }
        .alert(String(localized: "chat.hard_stop"), isPresented: $confirmHardStop) {
            Button(String(localized: "chat.hard_stop"), role: .destructive) { Task { await model.interrupt(hard: true) } }
            Button(String(localized: "pair.cancel"), role: .cancel) {}
        } message: { Text(String(localized: "chat.hard_stop_note")) }
        .sheet(item: $selecting) { request in SelectTextPage(request: request) }
        // Read on every visit and every return to the foreground, so an edit on the Mac shows without a relaunch.
        .task(id: model.canSend && phase == .active) { if phase == .active { await model.loadModelChoices() } }
        .task(id: phase) {
            guard phase == .active else { model.suspendReads(); return }; model.resumeReads()
            await model.observeChanges()
        }
        .environment(\.colorScheme, .light)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
        .accessibilityAction(.escape) { dismiss() }
    }
    /// The message list. Separate from `body` so the page stays type-checkable.
    @ViewBuilder private func timeline(bottom: CGFloat, tailFirst: Bool, reachedTop: @escaping () -> Void) -> some View {
        // Lookups are built once per change, not once per body evaluation: a scroll re-evaluates this page many
        // times a second, and rebuilding three dictionaries over every message each time was the cost of reading
        // back through a long conversation.
        let index = TimelineIndexCache.shared.index(key: model.timelineIndexKey) {
            TimelineIndexCache.Index(
                firstResponse: Dictionary(model.responses.map { ($0.firstMessageID, $0) }, uniquingKeysWith: { _, latest in latest }),
                lastResponse: Dictionary(model.responses.map { ($0.lastMessageID, $0) }, uniquingKeysWith: { _, latest in latest }),
                imagesByMessage: Dictionary(grouping: model.images, by: \.messageID))
        }
        let firstResponse = index.firstResponse, lastResponse = index.lastResponse, imagesByMessage = index.imagesByMessage
        let runningSince = model.runningSince
        // The live label belongs at the top of the reply in progress; before the first reply it has its own row.
        let activeAnchor: String? = runningSince == nil ? nil : model.responses.last.flatMap { $0.completed ? nil : $0.firstMessageID }
        VStack(spacing: 0) {
        // The blank tail goes above the rows while the page shows its end: a conversation shorter than the
        // page then rests against the composer. A prompt this phone sent takes the tail below itself instead,
        // so the reply grows into the room under it; the total is the same either way, so the page does not move.
        if tailFirst && !showsInitialLoading { Color.clear.frame(height: max(0, bottom - timelineContentHeight)) }
        // The rows' own height, measured where nothing else can stretch it.
        LazyVStack(alignment: .leading, spacing: 6) {
            if model.hasMore {
                // Reaching the top while reading back pages in the earlier messages; the page opens at the latest.
                // It is also a button: the geometry trigger needs the marker to move, so a page already resting at
                // the top would otherwise wait for a scroll it cannot make.
                Group {
                    if model.loadingOlder && !pulling { ProgressView() }
                    else { Button(String(localized: "chat.load_earlier")) { reachedTop() }.buttonStyle(.plain).font(.footnote) }
                }
                .frame(maxWidth: .infinity).frame(height: 32).padding(.top, 12)
                    // Position, not appearance: a lazy row stays alive offscreen, so its appearance fires only once.
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .named("chatTimeline")).minY > -240 } action: { near in
                        // No state is written here: the page must not re-evaluate on every scroll frame.
                        if near && !atLatest { reachedTop() }
                    }
            }
            else if model.clipped { Text(String(localized: "chat.clipped")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 12).accessibilityIdentifier("chat.clipped") }
            if model.messages.isEmpty && model.error == nil && !showsInitialLoading {
                ContentUnavailableView(String(localized: "chat.empty"), systemImage: "bubble.left.and.bubble.right")
            }
            ForEach(model.timelineItems) { item in
                timelineRow(item, firstResponse: firstResponse, lastResponse: lastResponse, imagesByMessage: imagesByMessage, activeAnchor: activeAnchor, runningSince: runningSince, bottom: bottom)
                    .id(item.id)
                    .modifier(PinnedHeightProbe(pinned: isPinned(item)) { height in if abs(height - pinnedRowHeight) > 0.5 { pinnedRowHeight = height } })
            }
            if activeAnchor == nil, let runningSince {
                LiveRunLabel(since: runningSince, compacting: model.compacting, showsDivider: true, font: .subheadline)
            }
            // The live tail changes on every poll; keeping that read in its own view stops the whole timeline
            // from being rebuilt for each delta.
            LivePreviewRow(model: model)
            ForEach(model.outgoing) { prompt in
                OutgoingPromptRow(prompt: prompt).id(prompt.id)
                    .modifier(PinnedHeightProbe(pinned: pinnedSent?.outgoing == prompt.id) { height in if abs(height - pinnedRowHeight) > 0.5 { pinnedRowHeight = height } })
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading).background(Color.red.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))

            }
        }
        // The rows' own height, measured on a stack that holds no filler: a value that cannot depend on
        // what it sizes. (Measuring the same stack the filler lives in made the difference always zero.)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if abs(height - timelineContentHeight) > 0.5 { timelineContentHeight = height }
        }

        // The whole difference between the page and its content; above the rows when the end is showing.
        // Below a pinned prompt it is the room left after the rows under that prompt, so its top can reach
        // the page's top; the reply then grows into that room without moving the prompt.
        if !tailFirst { Color.clear.frame(height: max(0, bottom - PinnedPrompt.foot - pinnedRowHeight)) }
        // The page's foot, so the marker below it is the true end of the content: anchoring that to the
        // bottom lands exactly where a drag to the end does.
        Color.clear.frame(height: 18)
        Color.clear.frame(height: 1).id("latest")
        }
        .padding(.horizontal, 18).padding(.top, 12)
            // A tap on the conversation puts the keyboard away; rows keep their own taps.
            .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
    }
    /// One timeline item: its duration label, content and footer. Separate so the page body stays type-checkable.
    @ViewBuilder private func timelineRow(_ item: ConversationTimelineItem, firstResponse: [String: ConversationResponse], lastResponse: [String: ConversationResponse],
                                          imagesByMessage: [String: [ConversationImageReference]], activeAnchor: String?, runningSince: Date?, bottom: CGFloat) -> some View {
        let images = item.messages.flatMap { imagesByMessage[$0.id] ?? [] }
        VStack(alignment: .leading, spacing: 12) {
            if item.id == activeAnchor, let runningSince {
                LiveRunLabel(since: runningSince, compacting: model.compacting, showsDivider: true, font: .subheadline)
            } else if let response = firstResponse[item.id], let seconds = response.durationSeconds {
                ResponseRunLabel(seconds: seconds, recorded: response.recordedDuration)
            }
            if item.isActivity { ActivityGroupView(item: item, projectRoot: model.session.cwd, openFile: model.client.allows(.projectRead) ? { selectedFile = $0; showProject = true } : nil, images: images, openImage: { selectedImage = $0 }, openDetail: openToolDetail, sessionID: model.session.id, client: model.client, generation: model.historyGeneration, isLatest: item.id == model.timelineItems.last?.id) }
            else {
                let prompt = item.first.kind.questionPrompt
                MessageRow(message: item.first, projectRoot: model.session.cwd, openFile: model.client.allows(.projectRead) ? { selectedFile = $0; showProject = true } : nil, images: images, openImage: { selectedImage = $0 }, openDetail: openToolDetail,
                           pendingQuestion: prompt.flatMap { model.pendingQuestions[$0] }, answering: model.answeringQuestion,
                           answerQuestion: model.client.canReplyFeed ? { answers in Task { await model.answer(prompt: prompt ?? "", selections: answers) } } : nil,
                           chosenAnswer: prompt.flatMap { model.answeredQuestions[$0] }, edgeBlur: bottom)
            }
            if let response = lastResponse[item.id], response.completed, case .prose = item.first.kind {
                ResponseFooter(response: response, text: model.responseText(response), quote: quote)
            }
        }
        // A waiting question's form blurs line by line instead (see `FeedQuestionView.edgeBlur`): as one row it
        // is taller than the screen, and rasterizing it whole on every frame made scrolling past it stutter. A
        // `visualEffect` rasterizes what it wraps even with every effect disabled, so this row opts out entirely.
    }
    /// Puts text into the follow-up draft as a Markdown quote, ahead of what is already typed.
    private func quote(_ text: String) {
        let quoted = text.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
        model.draft = quoted + "\n\n" + model.draft
    }
    private func openToolDetail(_ messageID: String, _ field: String) {
        guard let generation = model.historyGeneration else { return }
        selectedToolDetail = ToolDetailReference(messageID: messageID, generation: generation, initialField: field)
    }
    /// Pages in earlier messages and keeps the message that was on top where it was.
    /// `pull` is the reader asking with the pull gesture: that gesture answers with its own spinner, so it must do
    /// work even when an automatic page loaded a moment ago.
    private func loadOlder(_ proxy: ScrollViewProxy, pull: Bool = false) async {
        guard model.hasMore, !model.loadingOlder, pull || Date() >= nextPageAllowed, let anchor = model.timelineItems.first?.id else { return }
        nextPageAllowed = Date().addingTimeInterval(0.8)
        await model.older()
        // A page that brings nothing new is not the end of the record: the loader keeps its pause, and the reader
        // scrolling again asks for the next one. Only `hasMore == false` ends the paging.
        guard model.timelineItems.first?.id != anchor else { return }
        // A scroll in the same update as the insertion is overridden by its layout; restore once the rows exist.
        try? await Task.sleep(for: .milliseconds(50))
        scrollTrace.note("scroll older-page"); proxy.scrollTo(anchor, anchor: .top)
        // The next page waits for the reader to reach the top again: chaining here fired while the list was still
        // laying out, and a long conversation froze.
        diagLog(.info, category: "open", "older page loaded messages=\(model.messages.count) items=\(model.timelineItems.count)")
    }
    /// A pull reads earlier messages while there are any, otherwise the latest; it redials only a link that is down.
    private func pullToRefresh(_ proxy: ScrollViewProxy) async {
        if linkState != nil && linkState != .connected { await reconnect(); return }
        // The pull is the same load as the automatic one; only its indicator belongs to the system, so the row's
        // own spinner stays out of the way while it is on screen.
        pulling = true
        defer { pulling = false }
        if model.hasMore { await loadOlder(proxy, pull: true) } else { await model.refresh() }
    }
    /// Scrolls to the newest message, then again while the freshly inserted rows finish measuring.
    ///
    /// A row's height is known only after it lays out, so the opening scroll of a long conversation can land
    /// short and leave the page above the newest message with nothing left to correct it.
    private func settleAtBottom(_ proxy: ScrollViewProxy, retries: Int = 3) {
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            for attempt in 0...retries {
                guard !Task.isCancelled else { return }
                if attempt > 0 { try? await Task.sleep(for: .milliseconds(60)) }
                guard !Task.isCancelled, atLatest else { return }
                scrollTrace.note("scroll settle"); scrollToNewest(proxy)
            }
        }
    }
    /// Scrolls to the newest message.
    ///
    /// Anchoring the newest row itself puts its last line just above the composer, but leaves the page's own
    /// 18pt foot and the marker after it below the fold, so the page stops short of its real end: the reader
    /// still has to pull up once more to see the very bottom. The marker therefore takes the bottom anchor,
    /// which lands the page where a drag to the end would. That is right for a reply that fits, and wrong for
    /// one taller than the page: its first line would then be pushed off the top and the reader would open on
    /// the middle of it. A tall newest row starts at the top instead.
    ///
    /// Either way the newest row is the target rather than the page's end alone: a lazy stack estimates the
    /// height of a row it has not built, and one very tall reply above makes that estimate wrong by thousands
    /// of points, so asking for the marker first resolves into the middle of an earlier reply. Asking for the
    /// row builds it; the marker is then in place for the last attempt.
    private func scrollToNewest(_ proxy: ScrollViewProxy) {
        // A pinned prompt owns the page's position: the transcript refresh that records it, and the reply
        // that then grows, arrive as ordinary new rows, and following them to the end would carry the
        // prompt back off the top. The pin clears on a scroll or the latest button, which scrolls itself.
        guard pinnedSent == nil else { return }
        // The page's end is where a drag to the end lands, whatever the newest row's height: a reply
        // taller than the page opens at its last line too, because that is the newest content the reader
        // came back for. Asking for the row first builds it, so the end marker lands where it really is.
        if let newest = model.timelineItems.last?.id { proxy.scrollTo(newest, anchor: .bottom) }
        proxy.scrollTo("latest", anchor: .bottom)
    }
    /// The scrolling page: the timeline and everything that follows, moves or restores its position.
    private func timelineScroller() -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                timeline(bottom: scrollHeight, tailFirst: pinnedSent == nil) { Task { await loadOlder(proxy) } }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if abs(height - scrollHeight) > 0.5 { scrollHeight = height }
            }
            .scrollClipDisabled()
            .coordinateSpace(name: "chatTimeline")
            // Whether the newest content is in sight, measured by the scroll view itself. Its offset counts from
            // under the header while its container height leaves the header and composer out, so adding the two
            // stopped a header's height short of the end: a page dragged to its end by hand still read as away
            // from it and kept the latest button. The visible rect reaches under the composer; what the reader
            // sees ends where the composer begins. The page's foot and a pinned prompt's blank room are not content.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let seen = geometry.visibleRect.maxY - geometry.contentInsets.bottom
                return seen >= geometry.contentSize.height - pageTail - 8
            } action: { old, atEnd in
                _ = old
                bottomVisible(atEnd)
            }
            .modifier(TimelineScrollInteraction(userScrolling: $userScrolling, atLatest: $atLatest, latestVisible: latestVisible))
            .onChange(of: userScrolling) { _, scrolling in
                scrollTrace.note("userScrolling=\(scrolling)")
                if scrolling { holdingPlace = false; pinnedSent = nil }
            }
            .onChange(of: atLatest) { _, value in scrollTrace.note("atLatest=\(value) hold=\(holdingPlace)") }
            .modifier(ScrollJumpTrace(trace: scrollTrace))
            // A card opened at the newest message would otherwise be carried off by the next one to arrive.
            .environment(\.holdPlace) { scrollTrace.toggled("atLatest=\(atLatest) latestVisible=\(latestVisible)"); atLatest = false; holdingPlace = true }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await pullToRefresh(proxy) }
            // Offered only while newest content is out of sight: a page that rests at its end, by hand or after a
            // card closed, has nowhere to go back to. A pinned prompt follows its reply, so the button appears
            // once that reply runs under the composer.
            .overlay(alignment: .bottom) {
                if !latestVisible && (!atLatest || pinnedSent != nil) {
                    latestButton(proxy)
                }
            }
            // The first read's spinner sits in the middle of the page, not in the timeline: a timeline holding a
            // single row would rest it against the composer, half under it.
            .overlay {
                if showsInitialLoading {
                    ProgressView(String(localized: "chat.loading")).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onChange(of: model.timelineItems.last?.id) { _, _ in
                if !initiallyScrolled && !model.messages.isEmpty { settleAtBottom(proxy); initiallyScrolled = true }
                else if atLatest { scrollTrace.note("scroll new-item"); scrollToNewest(proxy) }
            }
            .onChange(of: model.latestMessageText) { _, _ in if atLatest { scrollTrace.note("scroll new-text"); scrollToNewest(proxy) } }
            .onChange(of: model.preview) { _, _ in if atLatest { scrollTrace.note("scroll preview"); scrollToNewest(proxy) } }
            // Opening a cached conversation re-enters with its follow state; start from the last message.
            .onAppear {
                diagLog(.info, category: "open", "page appeared messages=\(model.messages.count)")
                userScrolling = false
                // Coming back from a pushed page — the preview, a tool detail, the timing sheet — is not
                // opening the conversation again: the reader's place and any expanded card stay as they were.
                guard !openedConversation else { return }
                openedConversation = true
                atLatest = true; holdingPlace = false
                initialScroll = Task {
                    // Show the conversation read last, then settle once the fresh read lands.
                    await model.restoreStored()
                    guard !Task.isCancelled, !model.messages.isEmpty else { return }
                    initiallyScrolled = true; settleAtBottom(proxy, retries: 6)
                }
            }
            .onDisappear { settleTask?.cancel(); settleTask = nil; initialScroll?.cancel(); initialScroll = nil }
            // A prompt this phone sent lands with the page's newest row at the top and the reply taking the
            // room below it, which is where the reader looks next. Following resumes when they scroll down.
            .onChange(of: model.jumpToLatest) { _, _ in pinSentPrompt(proxy) }
            // The transcript replaces the bubble with the recorded message: keep the pin on that row so the
            // page does not move when the swap happens.
            .onChange(of: model.outgoing) { _, _ in handOverPin(proxy) }
            .onChange(of: model.timelineItems.count) { _, _ in handOverPin(proxy) }
            .environment(\.selectText) { text, monospaced in selecting = SelectTextPage.Request(text: text, monospaced: monospaced) }
        }
    }
    /// The input bar and the actions beside it; its own view keeps the page's body type-checkable.
    private var composer: some View {
        ChatComposer(draft: $model.draft, focused: $composerFocused, canSend: model.canSend, busy: model.busy, working: model.hasActiveResponse,
                     images: model.imageDraft.images, removeImage: model.imageDraft.remove,
                     send: { Task { await model.send() } }, stop: { Task { await model.interrupt() } },
                     canReadProject: model.client.allows(.projectRead), canReadFeed: model.client.allows(.feedRead),
                     showProject: { selectedFile = ""; showProject = true }, showFeed: { showFeed = true },
                     hasImages: !model.imageDraft.images.isEmpty,
                     sendBlocked: model.recoveryBlocked || model.imageDraft.loading || model.speech.active,
                     showPhotos: { showPhotos() },
                     dictating: model.speech.state == .recording,
                     startVoice: { Task { await model.speech.start() } }, finishVoice: { model.speech.finish() },
                     showImageFiles: { showingImageFiles = true },
                     maxLines: max(3, Int((pageHeight * 0.5 - 120) / 22)))
    }
    private func showPhotos() {
        guard model.imageDraft.images.count < 4 else { model.imageDraft.error = String(localized: "error.image"); return }
        photoItems = []; showingPhotos = true
    }
    /// Whether a recorded row is the one a pin holds, by the text the outgoing bubble showed.
    private func isPinned(_ item: ConversationTimelineItem) -> Bool {
        guard let pinned = pinnedSent, pinned.outgoing == nil else { return false }
        return PinnedPromptText.matches(item.first, pinned.text)
    }
    /// The blank height after the newest content: the page's foot and end marker, and below a pinned prompt the
    /// room it leaves for the reply. It has to match the filler and foot the timeline lays out.
    private var pageTail: CGFloat {
        19 + (pinnedSent == nil ? 0 : max(0, scrollHeight - PinnedPrompt.foot - pinnedRowHeight))
    }
    /// The page's follow decision, taken from the marker's position each time it is re-measured.
    private func bottomVisible(_ visible: Bool) {
        // Scrolling reports every frame; only a real change may invalidate the timeline.
        if latestVisible != visible { latestVisible = visible }
        if userScrolling || !atLatest {
            // While the page holds its place, the newest row coming into view does not resume following.
            if !holdingPlace, atLatest != visible { atLatest = visible }
        }
    }
    /// Holds the prompt this phone just sent at the top of the page, with a blank page left under it.
    private func pinSentPrompt(_ proxy: ScrollViewProxy) {
        holdingPlace = false
        guard let sent = model.outgoing.last else {
            scrollTrace.note("scroll after-send"); atLatest = true; scrollToNewest(proxy); return
        }
        // The tail and the scroll land in the same update, so the top anchor is reachable before the reply
        // starts growing. Following stays on: with the tail shrinking, the page's end and the prompt's top
        // are the same place until the reply fills the page.
        pinnedSent = PinnedPrompt(outgoing: sent.id, text: sent.text)
        atLatest = true
        withAnimation { scrollTrace.note("scroll sent-prompt"); proxy.scrollTo(sent.id, anchor: .top) }
        // The bubble is inserted and scrolled in the same update, so its top may not exist yet; ask again
        // once it has laid out, the same way the opening scroll does.
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            for _ in 0..<3 {
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled, pinnedSent?.outgoing == sent.id else { return }
                proxy.scrollTo(sent.id, anchor: .top)
            }
        }
    }
    /// Moves the pin from the outgoing bubble to the transcript row that recorded it.
    private func handOverPin(_ proxy: ScrollViewProxy) {
        guard let pinned = pinnedSent, let outgoing = pinned.outgoing, !model.outgoing.contains(where: { $0.id == outgoing }) else { return }
        let target = model.timelineItems.last { item in
            item.first.role == .user && PinnedPromptText.matches(item.first, pinned.text)
        }
        pinnedSent = PinnedPrompt(outgoing: nil, text: pinned.text)
        if let target { proxy.scrollTo(target.id, anchor: .top); scrollTrace.note("scroll pin-handover") }
    }
    /// The way back to the page's end after a scroll away or a pinned prompt.
    private func latestButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            holdingPlace = false; pinnedSent = nil; atLatest = true
            withAnimation { scrollTrace.note("scroll latest-button"); scrollToNewest(proxy) }
        } label: {
            Image(systemName: "arrow.down")
        }
        .floatingIconButton().accessibilityLabel(String(localized: "chat.latest"))
        // A tap that lands just outside a 44-point circle is a tap on the page; this keeps the whole visible
        // control, and a little more, his to press.
        .contentShape(Circle().inset(by: -8))
        .accessibilityIdentifier("chat.latest").padding(.bottom, 10)
    }
    /// The menu's refresh redials a link that may be dead before reading, and shows the dial while it happens.
    private func reconnect() async {
        if linkState != .connected { linkState = .connecting }
        await model.client.reconnect()
        await model.refresh()
    }
    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "chevron.left") }
                .floatingIconButton().accessibilityLabel(String(localized: "chat.back")).accessibilityIdentifier("chat.back")
            VStack(alignment: .leading, spacing: 3) {
                Text(model.shownTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                AgentModelMenu(subtitle: [model.session.agent.capitalized, model.modelLabel ?? "", hostName].filter { !$0.isEmpty }.joined(separator: " · "),
                               current: model.modelLabel, choices: model.canSwitchModel ? model.modelChoices : nil,
                               enabled: !model.busy && !model.working && model.pendingSend == nil) { name, label in
                    Task { await model.switchModel(to: name, label: label) }
                }
                .equatable()
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                if model.client.allows(.conversationControl) {
                    Button { renameDraft = model.shownTitle; showRename = true } label: { Label(String(localized: "chat.rename"), systemImage: "pencil") }.accessibilityIdentifier("chat.rename")
                }
                Button { showTiming = true } label: { Label(String(localized: "chat.timing"), systemImage: "clock") }.accessibilityIdentifier("chat.timing")
                if model.client.allows(.projectRead) { Button { selectedFile = ""; showProject = true } label: { Label(String(localized: "project.title"), systemImage: "doc.text.magnifyingglass") }.accessibilityIdentifier("chat.project") }
                if model.client.allows(.feedRead) { Button { showFeed = true } label: { Label(String(localized: "feed.title"), systemImage: "checkmark.bubble") }.accessibilityIdentifier("chat.feed") }
                Button { Task { await reconnect() } } label: { Label(String(localized: "chat.refresh"), systemImage: "arrow.clockwise") }
                if model.canSend {
                    Button { Task { await model.interrupt() } } label: { Label(String(localized: "chat.stop"), systemImage: "stop.circle") }
                    Button(role: .destructive) { confirmHardStop = true } label: { Label(String(localized: "chat.hard_stop"), systemImage: "stop.circle.fill") }
                }
            } label: { Image(systemName: "ellipsis").font(.system(size: 22, weight: .medium)).modifier(FloatingGlassCircle()) }
                .tint(.primary).accessibilityLabel(String(localized: "chat.more")).accessibilityIdentifier("chat.more")
        }.padding(.horizontal, MobileDesign.pageInset).padding(.vertical, 8)
    }
}

/// The agent's live tail. It is deliberately a separate view: reading `model.preview` in the timeline's body
/// made every delta re-evaluate the whole page.
private struct LivePreviewRow: View {
    let model: ConversationModel
    var body: some View {
        if let preview = model.preview {
            VStack(alignment: .leading, spacing: 10) {
                Label(String(localized: "chat.preview"), systemImage: "ellipsis.bubble").font(.caption).foregroundStyle(.secondary)
                MarkdownMessageView(text: preview)
            }
        }
    }
}
