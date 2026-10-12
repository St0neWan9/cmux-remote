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
    private let hostName: String
    init(model: ConversationModel, hostName: String = "") {
        _model = State(initialValue: model); self.hostName = hostName
    }
    var body: some View {
        GeometryReader { viewport in
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.hasMore { Button(String(localized: "chat.older")) { Task { await model.older() } }.disabled(model.loadingOlder).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 12) }
                    if model.messages.isEmpty && model.error == nil {
                        ContentUnavailableView(String(localized: "chat.empty"), systemImage: "bubble.left.and.bubble.right")
                    }
                    ForEach(model.timelineItems) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            if let response = model.responses.first(where: { $0.firstMessageID == item.id }), let seconds = response.durationSeconds {
                                ResponseRunLabel(seconds: seconds, recorded: response.recordedDuration)
                            }
                            if item.isActivity { ActivityGroupView(item: item, projectRoot: model.session.cwd, openFile: model.client.allows(.projectRead) ? { selectedFile = $0; showProject = true } : nil, images: model.images.filter { reference in item.messages.contains { $0.id == reference.messageID } }, openImage: { selectedImage = $0 }, openDetail: openToolDetail) }
                            else { MessageRow(message: item.first, projectRoot: model.session.cwd, openFile: model.client.allows(.projectRead) ? { selectedFile = $0; showProject = true } : nil, images: model.images.filter { reference in item.messages.contains { $0.id == reference.messageID } }, openImage: { selectedImage = $0 }, openDetail: openToolDetail) }
                            if let response = model.responses.first(where: { $0.lastMessageID == item.id }), response.completed, case .prose = item.first.kind {
                                ResponseFooter(response: response, text: model.responseText(response)) { text in
                                    let quoted = text.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
                                    model.draft = quoted + "\n\n" + model.draft
                                }
                            }
                        }.modifier(HeaderContentEffect())
                    }
                    if let preview = model.preview {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(String(localized: "chat.preview"), systemImage: "ellipsis.bubble").font(.caption).foregroundStyle(.secondary)
                            MarkdownMessageView(text: preview)
                        }.modifier(HeaderContentEffect())
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red).padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading).background(Color.red.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                            .modifier(HeaderContentEffect())
                    }
                    Color.clear.frame(height: 1).id("latest")
                        .background {
                            GeometryReader { anchor in
                                Color.clear.preference(key: TimelineBottomPreferenceKey.self,
                                    value: anchor.frame(in: .named("chatTimeline")).maxY)
                            }
                        }
                }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 18)
            }
            .scrollClipDisabled()
            .coordinateSpace(name: "chatTimeline")
            .onPreferenceChange(TimelineBottomPreferenceKey.self) { bottom in
                latestVisible = bottom > 0 && bottom <= viewport.size.height + 32
                if userScrolling || !atLatest { atLatest = latestVisible }
                else if bottom.isFinite && !latestVisible { proxy.scrollTo("latest", anchor: .bottom) }
            }
            .modifier(TimelineScrollInteraction(userScrolling: $userScrolling, atLatest: $atLatest, latestVisible: latestVisible))
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.refresh() }
            .overlay(alignment: .bottom) {
                if !atLatest {
                    Button { atLatest = true; withAnimation { proxy.scrollTo("latest", anchor: .bottom) } } label: {
                        Image(systemName: "arrow.down").font(.system(size: 20, weight: .medium)).frame(width: 42, height: 42)
                            .background(Color.white, in: Circle()).shadow(color: .black.opacity(0.1), radius: 10, y: 4)
                    }.buttonStyle(.plain).accessibilityLabel(String(localized: "chat.latest")).accessibilityIdentifier("chat.latest").padding(.bottom, 10)
                }
            }
            .onChange(of: model.timelineItems.last?.id) { _, _ in
                if !initiallyScrolled && !model.messages.isEmpty { proxy.scrollTo("latest", anchor: .bottom); initiallyScrolled = true }
                else if atLatest { proxy.scrollTo("latest", anchor: .bottom) }
            }
            .onChange(of: model.latestMessageText) { _, _ in if atLatest { proxy.scrollTo("latest", anchor: .bottom) } }
            .onChange(of: model.preview) { _, _ in if atLatest { proxy.scrollTo("latest", anchor: .bottom) } }
            .onChange(of: model.jumpToLatest) { _, _ in atLatest = true; withAnimation { proxy.scrollTo("latest", anchor: .bottom) } }
        }
        }
        .background(Color.white.ignoresSafeArea())
        .background(InteractivePopInstaller())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                SpeechDraftStrip(model: model.speech, useText: model.useSpeechDraft)
                if !model.imageDraft.images.isEmpty {
                    ImageDraftStrip(images: model.imageDraft.images, remove: model.imageDraft.remove).equatable()
                }
                if model.imageDraft.loading { ProgressView(String(localized: "image.preparing")) }
                if let error = model.imageDraft.error { Text(error).font(.footnote).foregroundStyle(.red) }
                if (model.pendingSend != nil || model.recoveryFailed) && !model.busy {
                    HStack {
                        if model.pendingSend != nil { Button(String(localized: "operation.check")) { Task { await model.checkPendingSend() } }.disabled(model.busy) }
                        Button(String(localized: "operation.inspected")) { confirmPendingReset = true }.disabled(model.busy)
                    }.font(.footnote).buttonStyle(FloatingButtonStyle())
                }
                if model.stopRequested {
                    Label(String(localized: "chat.stop_requested"), systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary)
                } else if model.hasActiveResponse {
                    HStack(spacing: 7) { ProgressView().controlSize(.mini); if let start = model.runningSince {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let elapsed = Duration.seconds(max(0, context.date.timeIntervalSince(start))).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2))
                            Text(String.localizedStringWithFormat(String(localized: "chat.elapsed_duration"), elapsed)).font(.footnote).monospacedDigit()
                        }
                    } else { Text(String(localized: "chat.working")).font(.footnote) }; Spacer(); Label(model.session.agent.capitalized, systemImage: "sparkles").font(.caption) }
                        .foregroundStyle(.secondary).padding(.horizontal, 12)
                } else if !model.canSend { Text(String(localized: "sessions.read_only")).font(.caption).foregroundStyle(.secondary) }
                ChatComposer(draft: $model.draft, canSend: model.canSend, busy: model.busy, working: model.hasActiveResponse,
                             send: { Task { await model.send() } }, stop: { Task { await model.interrupt() } },
                             canReadProject: model.client.allows(.projectRead), canReadFeed: model.client.allows(.feedRead), showProject: { selectedFile = ""; showProject = true }, showFeed: { showFeed = true },
                             hasImages: !model.imageDraft.images.isEmpty, sendBlocked: model.recoveryBlocked || model.imageDraft.loading || model.speech.active, showPhotos: {
                                 guard model.imageDraft.images.count < 4 else { model.imageDraft.error = String(localized: "error.image"); return }
                                 photoItems = []; showingPhotos = true
                             }, dictating: model.speech.state == .recording, startVoice: { Task { await model.speech.start() } }, finishVoice: { model.speech.finish() }, showImageFiles: { showingImageFiles = true })
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
            guard phase == .active else { model.suspendReads(); return }; model.resumeReads(); await model.refresh()
            let ticker = RefreshTicker(); defer { ticker.stop() }
            for await _ in ticker.start() { guard !Task.isCancelled else { break }; await model.refresh() }
        }
        .environment(\.colorScheme, .light)
        .accessibilityAction(.escape) { dismiss() }
    }
    private func openToolDetail(_ messageID: String, _ field: String) {
        guard let generation = model.historyGeneration else { return }
        selectedToolDetail = ToolDetailReference(messageID: messageID, generation: generation, initialField: field)
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
                Button { Task { await model.refresh() } } label: { Label(String(localized: "chat.refresh"), systemImage: "arrow.clockwise") }
                if model.canSend {
                    Button { Task { await model.interrupt() } } label: { Label(String(localized: "chat.stop"), systemImage: "stop.circle") }
                    Button(role: .destructive) { confirmHardStop = true } label: { Label(String(localized: "chat.hard_stop"), systemImage: "stop.circle.fill") }
                }
            } label: { Image(systemName: "ellipsis").font(.system(size: 22, weight: .medium)).frame(width: 48, height: 44).background(Color.white, in: Capsule()).shadow(color: .black.opacity(0.07), radius: 10, y: 3) }
                .tint(.primary).accessibilityLabel(String(localized: "chat.more")).accessibilityIdentifier("chat.more")
        }.padding(.horizontal, MobileDesign.pageInset).padding(.vertical, 8)
    }
}
