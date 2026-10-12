import SwiftUI
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
    @State private var showFeed = false
    private let hostName: String
    init(session: SessionDescriptor, client: RemoteClient, hostName: String = "") {
        _model = State(initialValue: ConversationModel(session: session, client: client)); self.hostName = hostName
    }
    var body: some View {
        GeometryReader { viewport in
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.hasMore { Button(String(localized: "chat.older")) { Task { await model.older() } }.font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 12) }
                    if model.messages.isEmpty && model.error == nil {
                        ContentUnavailableView(String(localized: "chat.empty"), systemImage: "bubble.left.and.bubble.right")
                    }
                    ForEach(model.timelineItems) { item in
                        Group {
                            if item.isActivity { ActivityGroupView(item: item) }
                            else { MessageRow(message: item.first) }
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
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                if model.stopRequested {
                    Label(String(localized: "chat.stop_requested"), systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary)
                } else if model.working {
                    HStack(spacing: 7) { ProgressView().controlSize(.mini); Text(String(localized: "chat.working")).font(.footnote); Spacer(); Label(model.session.agent.capitalized, systemImage: "sparkles").font(.caption) }
                        .foregroundStyle(.secondary).padding(.horizontal, 12)
                } else if !model.canSend { Text(String(localized: "sessions.read_only")).font(.caption).foregroundStyle(.secondary) }
                ChatComposer(draft: $model.draft, canSend: model.canSend, busy: model.busy, working: model.working,
                             send: { Task { await model.send() } }, stop: { Task { await model.interrupt() } },
                             showProject: { showProject = true }, showFeed: { showFeed = true })
            }.padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
        }
        .navigationDestination(isPresented: $showProject) { ProjectView(session: model.session, client: model.client).toolbar(.visible, for: .navigationBar) }
        .navigationDestination(isPresented: $showFeed) { FeedView(client: model.client).toolbar(.visible, for: .navigationBar) }
        .task(id: phase) {
            guard phase == .active else { return }; await model.refresh()
            let ticker = RefreshTicker(); defer { ticker.stop() }
            for await _ in ticker.start() { guard !Task.isCancelled else { break }; await model.refresh() }
        }
        .environment(\.colorScheme, .light)
    }
    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44).background(Color.white, in: Circle()).shadow(color: .black.opacity(0.07), radius: 10, y: 3) }
                .buttonStyle(.plain).accessibilityLabel(String(localized: "chat.back")).accessibilityIdentifier("chat.back")
            VStack(alignment: .leading, spacing: 3) {
                Text(model.session.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(hostName.isEmpty ? model.session.agent.capitalized : model.session.agent.capitalized + " · " + hostName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button { showProject = true } label: { Label(String(localized: "project.title"), systemImage: "doc.text.magnifyingglass") }
                Button { showFeed = true } label: { Label(String(localized: "feed.title"), systemImage: "checkmark.bubble") }
                Button { Task { await model.refresh() } } label: { Label(String(localized: "chat.refresh"), systemImage: "arrow.clockwise") }
                if model.canSend { Button { Task { await model.interrupt() } } label: { Label(String(localized: "chat.stop"), systemImage: "stop.circle") } }
            } label: { Image(systemName: "ellipsis").font(.system(size: 22, weight: .medium)).frame(width: 48, height: 44).background(Color.white, in: Capsule()).shadow(color: .black.opacity(0.07), radius: 10, y: 3) }
                .tint(.primary).accessibilityLabel(String(localized: "chat.more")).accessibilityIdentifier("chat.more")
        }.padding(.horizontal, 14).padding(.vertical, 8)
    }
}
