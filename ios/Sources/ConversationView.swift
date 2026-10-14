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
    /// Retries the opening jump: a row's height is known only after it lays out.
    @State private var settleTask: Task<Void, Never>?
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
    @State private var selectedImage: ConversationImageReference?
    @State private var selectedToolDetail: ToolDetailReference?
    /// The page's height above the keyboard; the composer may use half of it.
    @State private var pageHeight: CGFloat = 700
    @FocusState private var composerFocused: Bool
    /// This Mac's link, shown above the conversation while it is not up.
    @State private var linkState: LinkState?
    /// Whether the marker above the first loaded message is within reach of the top of the page.
    @State private var topNear = false
    private let hostName: String
    init(model: ConversationModel, hostName: String = "") {
        _model = State(initialValue: model); self.hostName = hostName
    }
    var body: some View {
        GeometryReader { viewport in
        ScrollViewReader { proxy in
            ScrollView {
                timeline(bottom: viewport.size.height) { Task { await loadOlder(proxy) } }
            }
            .scrollClipDisabled()
            .modifier(InitialBottomAnchor())
            .coordinateSpace(name: "chatTimeline")
            .onPreferenceChange(TimelineBottomPreferenceKey.self) { bottom in
                // Scrolling reports every frame; only a real change may invalidate the timeline.
                let visible = bottom > 0 && bottom <= viewport.size.height + 32
                if latestVisible != visible { latestVisible = visible }
                if userScrolling || !atLatest { if atLatest != visible { atLatest = visible } }
                else if bottom.isFinite && !latestVisible { proxy.scrollTo("latest", anchor: .bottom) }
            }
            .modifier(TimelineScrollInteraction(userScrolling: $userScrolling, atLatest: $atLatest, latestVisible: latestVisible))
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await pullToRefresh(proxy) }
            .overlay(alignment: .bottom) {
                if !atLatest {
                    Button { atLatest = true; withAnimation { proxy.scrollTo("latest", anchor: .bottom) } } label: {
                        Image(systemName: "arrow.down").font(.system(size: 20, weight: .medium)).frame(width: 42, height: 42)
                            .background(Color.white, in: Circle()).shadow(color: .black.opacity(0.1), radius: 10, y: 4)
                    }.buttonStyle(.plain).accessibilityLabel(String(localized: "chat.latest")).accessibilityIdentifier("chat.latest").padding(.bottom, 10)
                }
            }
            .onChange(of: model.timelineItems.last?.id) { _, _ in
                if !initiallyScrolled && !model.messages.isEmpty { settleAtBottom(proxy); initiallyScrolled = true }
                else if atLatest { proxy.scrollTo("latest", anchor: .bottom) }
            }
            .onChange(of: model.latestMessageText) { _, _ in if atLatest { proxy.scrollTo("latest", anchor: .bottom) } }
            .onChange(of: model.preview) { _, _ in if atLatest { proxy.scrollTo("latest", anchor: .bottom) } }
            // Opening a cached conversation re-enters with its follow state; start from the last message.
            .onAppear {
                userScrolling = false; atLatest = true
                if !model.messages.isEmpty { initiallyScrolled = true; settleAtBottom(proxy, retries: 6) }
            }
            .onDisappear { settleTask?.cancel(); settleTask = nil }
            .onChange(of: model.jumpToLatest) { _, _ in atLatest = true; withAnimation { proxy.scrollTo("latest", anchor: .bottom) } }
        }
        }
        .background(Color.white.ignoresSafeArea())
        .background(InteractivePopInstaller())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 6) {
                header
                ConnectionStatusBar(state: linkState) { Task { await reconnect() } }
            }
        }
        .task { for await state in model.client.linkStates() { linkState = state } }
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
                if !model.backgroundTasks.isEmpty { BackgroundTasksBar(tasks: model.backgroundTasks) }
                if model.stopRequested {
                    Label(String(localized: "chat.stop_requested"), systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary)
                } else if model.hasActiveResponse {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        if let start = model.runningSince { LiveRunLabel(since: start, compacting: model.compacting, showsMark: false) }
                        else { Text(String(localized: "chat.working")).font(.footnote) }
                        Spacer(); Label(model.session.agent.capitalized, systemImage: "sparkles").font(.caption)
                    }.foregroundStyle(.secondary).padding(.horizontal, 12)
                } else if !model.canSend { Text(String(localized: "sessions.read_only")).font(.caption).foregroundStyle(.secondary) }
                ChatComposer(draft: $model.draft, focused: $composerFocused, canSend: model.canSend, busy: model.busy, working: model.hasActiveResponse,
                             images: model.imageDraft.images, removeImage: model.imageDraft.remove,
                             send: { Task { await model.send() } }, stop: { Task { await model.interrupt() } },
                             canReadProject: model.client.allows(.projectRead), canReadFeed: model.client.allows(.feedRead), showProject: { selectedFile = ""; showProject = true }, showFeed: { showFeed = true },
                             hasImages: !model.imageDraft.images.isEmpty, sendBlocked: model.recoveryBlocked || model.imageDraft.loading || model.speech.active, showPhotos: {
                                 guard model.imageDraft.images.count < 4 else { model.imageDraft.error = String(localized: "error.image"); return }
                                 photoItems = []; showingPhotos = true
                             }, dictating: model.speech.state == .recording, startVoice: { Task { await model.speech.start() } }, finishVoice: { model.speech.finish() }, showImageFiles: { showingImageFiles = true },
                             maxLines: max(3, Int((pageHeight * 0.5 - 120) / 22)))
            }.padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
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
        .task(id: phase) {
            guard phase == .active else { model.suspendReads(); return }; model.resumeReads()
            await model.observeChanges()
        }
        .environment(\.colorScheme, .light)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
        .accessibilityAction(.escape) { dismiss() }
    }
    /// The message list. Separate from `body` so the page stays type-checkable.
    @ViewBuilder private func timeline(bottom: CGFloat, reachedTop: @escaping () -> Void) -> some View {
        // Lookups are built once per update instead of searched again by every row.
        let firstResponse = Dictionary(model.responses.map { ($0.firstMessageID, $0) }, uniquingKeysWith: { _, latest in latest })
        let lastResponse = Dictionary(model.responses.map { ($0.lastMessageID, $0) }, uniquingKeysWith: { _, latest in latest })
        let imagesByMessage = Dictionary(grouping: model.images, by: \.messageID)
        let runningSince = model.runningSince
        // The live label belongs at the top of the reply in progress; before the first reply it has its own row.
        let activeAnchor: String? = runningSince == nil ? nil : model.responses.last.flatMap { $0.completed ? nil : $0.firstMessageID }
        LazyVStack(alignment: .leading, spacing: 6) {
            if model.hasMore {
                // Reaching the top while reading back pages in the earlier messages; the page opens at the latest.
                Group { if model.loadingOlder { ProgressView() } else { Color.clear } }
                    .frame(maxWidth: .infinity).frame(height: 32).padding(.top, 12)
                    // Position, not appearance: a lazy row stays alive offscreen, so its appearance fires only once.
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .named("chatTimeline")).minY > -240 } action: { near in
                        topNear = near
                        if near && !atLatest { reachedTop() }
                    }
                    // A lazy row can be dropped far offscreen without reporting its last position.
                    .onDisappear { topNear = false }
            }
            else if model.clipped { Text(String(localized: "chat.clipped")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 12).accessibilityIdentifier("chat.clipped") }
            if model.messages.isEmpty && model.error == nil {
                // Until the first history read returns, an empty list means "loading", not "no conversation".
                if model.historyGeneration == nil { ProgressView(String(localized: "chat.loading")).frame(maxWidth: .infinity).padding(.top, 40) }
                else { ContentUnavailableView(String(localized: "chat.empty"), systemImage: "bubble.left.and.bubble.right") }
            }
            ForEach(model.timelineItems) { item in
                timelineRow(item, firstResponse: firstResponse, lastResponse: lastResponse, imagesByMessage: imagesByMessage, activeAnchor: activeAnchor, runningSince: runningSince, bottom: bottom)
            }
            if activeAnchor == nil, let runningSince {
                LiveRunLabel(since: runningSince, compacting: model.compacting, showsDivider: true, font: .subheadline).modifier(HeaderContentEffect(bottom: bottom))
            }
            if let preview = model.preview {
                VStack(alignment: .leading, spacing: 10) {
                    Label(String(localized: "chat.preview"), systemImage: "ellipsis.bubble").font(.caption).foregroundStyle(.secondary)
                    MarkdownMessageView(text: preview)
                }.modifier(HeaderContentEffect(bottom: bottom))
            }
            ForEach(model.outgoing) { prompt in OutgoingPromptRow(prompt: prompt).modifier(HeaderContentEffect(bottom: bottom)) }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading).background(Color.red.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                    .modifier(HeaderContentEffect(bottom: bottom))
            }
            Color.clear.frame(height: 1).id("latest")
                .background {
                    GeometryReader { anchor in
                        Color.clear.preference(key: TimelineBottomPreferenceKey.self,
                            value: anchor.frame(in: .named("chatTimeline")).maxY)
                    }
                }
        }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 18)
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
            if item.isActivity { ActivityGroupView(item: item, projectRoot: model.session.cwd, openFile: model.client.allows(.projectRead) ? { selectedFile = $0; showProject = true } : nil, images: images, openImage: { selectedImage = $0 }, openDetail: openToolDetail, isLatest: item.id == model.timelineItems.last?.id) }
            else { MessageRow(message: item.first, projectRoot: model.session.cwd, openFile: model.client.allows(.projectRead) ? { selectedFile = $0; showProject = true } : nil, images: images, openImage: { selectedImage = $0 }, openDetail: openToolDetail) }
            if let response = lastResponse[item.id], response.completed, case .prose = item.first.kind {
                ResponseFooter(response: response, text: model.responseText(response)) { text in
                    let quoted = text.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
                    model.draft = quoted + "\n\n" + model.draft
                }
            }
        }.modifier(HeaderContentEffect(bottom: bottom))
    }
    private func openToolDetail(_ messageID: String, _ field: String) {
        guard let generation = model.historyGeneration else { return }
        selectedToolDetail = ToolDetailReference(messageID: messageID, generation: generation, initialField: field)
    }
    /// Pages in earlier messages and keeps the message that was on top where it was.
    private func loadOlder(_ proxy: ScrollViewProxy) async {
        guard model.hasMore, !model.loadingOlder, let anchor = model.timelineItems.first?.id else { return }
        await model.older()
        guard model.timelineItems.first?.id != anchor else { return }
        // A scroll in the same update as the insertion is overridden by its layout; restore once the rows exist.
        try? await Task.sleep(for: .milliseconds(50))
        proxy.scrollTo(anchor, anchor: .top)
        // Still at the top after restoring: the reader wants more, and a marker that never left would not fire again.
        try? await Task.sleep(for: .milliseconds(300))
        if topNear && !atLatest { await loadOlder(proxy) }
    }
    /// A pull reads earlier messages while there are any, otherwise the latest; it redials only a link that is down.
    private func pullToRefresh(_ proxy: ScrollViewProxy) async {
        if linkState != nil && linkState != .connected { await reconnect(); return }
        if model.hasMore { await loadOlder(proxy) } else { await model.refresh() }
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
                proxy.scrollTo("latest", anchor: .bottom)
            }
        }
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
                .buttonStyle(FloatingIconStyle()).accessibilityLabel(String(localized: "chat.back")).accessibilityIdentifier("chat.back")
            VStack(alignment: .leading, spacing: 3) {
                Text(model.session.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(hostName.isEmpty ? model.session.agent.capitalized : model.session.agent.capitalized + " · " + hostName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button { showTiming = true } label: { Label(String(localized: "chat.timing"), systemImage: "clock") }.accessibilityIdentifier("chat.timing")
                if model.client.allows(.projectRead) { Button { selectedFile = ""; showProject = true } label: { Label(String(localized: "project.title"), systemImage: "doc.text.magnifyingglass") }.accessibilityIdentifier("chat.project") }
                if model.client.allows(.feedRead) { Button { showFeed = true } label: { Label(String(localized: "feed.title"), systemImage: "checkmark.bubble") }.accessibilityIdentifier("chat.feed") }
                Button { Task { await reconnect() } } label: { Label(String(localized: "chat.refresh"), systemImage: "arrow.clockwise") }
                if model.canSend {
                    Button { Task { await model.interrupt() } } label: { Label(String(localized: "chat.stop"), systemImage: "stop.circle") }
                    Button(role: .destructive) { confirmHardStop = true } label: { Label(String(localized: "chat.hard_stop"), systemImage: "stop.circle.fill") }
                }
            } label: { Image(systemName: "ellipsis").font(.system(size: 22, weight: .medium)).frame(width: 48, height: 44).background(Color.white, in: Capsule()).shadow(color: .black.opacity(0.07), radius: 10, y: 3) }
                .tint(.primary).accessibilityLabel(String(localized: "chat.more")).accessibilityIdentifier("chat.more")
        }.padding(.horizontal, MobileDesign.pageInset).padding(.vertical, 8)
    }
}
