import GalleryBridge
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

// MARK: - Exhibition Library Entry
struct ExhibitionEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let url: URL
    let coverImageURL: URL?
    let photoCount: Int
    let isSample: Bool
}

enum ViewerMode: String, CaseIterable, Identifiable {
    case exhibition = "전시"
    case photos = "사진"
    var id: String { rawValue }
}

// MARK: - Root View: Apple Photos–Style Exhibition Library
struct ContentView: View {
    @State private var store = GalleryStore()
    @State private var libraryEntries: [ExhibitionEntry] = []
    @State private var navigationPath: [ExhibitionEntry] = []
    @State private var showNewExhibitionSheet = false
    @State private var isCreatingExhibition = false

    // New Exhibition sheet state
    @State private var newTitle = ""
    @State private var newSubtitle = ""
    @State private var newPickedItems: [PhotosPickerItem] = []
    @State private var newLoadedPhotos: [(Data, String)] = []
    @State private var isAnalyzingNewPhotos = false
    @State private var newRecommendedBGM: MoodBGMRecommendation?
    @State private var selectedNewBGM: ExhibitionBGMTrack? = .morningLight
    @State private var bgmPreviewPlayer = BGMPreviewPlayer()

    // Toast feedback
    @State private var toastMessage: String?
    @State private var isToastError = false
    @State private var toastTask: Task<Void, Never>?

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 320, maximum: 520), spacing: 20)]
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                systemGroupedBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("사진으로 만드는 나만의 디지털 전시")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: gridColumns, spacing: 20) {
                            ForEach(libraryEntries) { entry in
                                NavigationLink(value: entry) {
                                    ExhibitionCoverCard(entry: entry)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if !entry.isSample {
                                        Button(role: .destructive) {
                                            store.deleteSavedPackage(at: entry.url)
                                            reloadLibrary()
                                            showToast("'\(entry.title)' 전시를 삭제했어요")
                                        } label: {
                                            Label("전시 삭제", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }

                        if libraryEntries.allSatisfy(\.isSample) {
                            Text("우상단 + 버튼으로 내 사진 전시를 만들어 보세요")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }

                if isCreatingExhibition {
                    loadingOverlay("사진을 분석해 전시를 구성하는 중…")
                }

                toastOverlay
            }
            .navigationTitle("전시관")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    #if os(macOS)
                    Button {
                        pickFolderToCreateExhibition()
                    } label: {
                        Label("폴더로 만들기", systemImage: "folder.badge.plus")
                    }
                    #endif

                    Button {
                        showNewExhibitionSheet = true
                    } label: {
                        Label("새 전시", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: ExhibitionEntry.self) { entry in
                ExhibitionViewerScreen(
                    entry: entry,
                    store: store,
                    onLibraryUpdated: { reloadLibrary() }
                )
            }
            .sheet(isPresented: $showNewExhibitionSheet) {
                newExhibitionSheet
            }
            .onAppear {
                reloadLibrary()
                handleLaunchArgumentsIfNeeded()
            }
        }
    }

    // MARK: - New Exhibition Sheet (Native Apple Form)
    private var newExhibitionSheet: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(
                        selection: $newPickedItems,
                        maxSelectionCount: 30,
                        matching: .images
                    ) {
                        HStack(spacing: 12) {
                            Image(systemName: newPickedItems.isEmpty ? "photo.on.rectangle.angled" : "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(newPickedItems.isEmpty ? Color.accentColor : Color.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(newPickedItems.isEmpty ? "사진 보관함에서 고르기" : "\(newPickedItems.count)장 선택됨")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text("최대 30장 · 촬영 순서에 맞춰 자동 구성됩니다")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }

                    #if os(macOS)
                    Button {
                        showNewExhibitionSheet = false
                        pickFolderToCreateExhibition()
                    } label: {
                        Label("Mac 사진 폴더에서 바로 만들기…", systemImage: "folder")
                    }
                    #endif
                } header: {
                    Text("사진")
                }

                Section {
                    TextField("전시 제목 (예: 후쿠오카의 여름)", text: $newTitle)
                    TextField("한 줄 소개 (선택)", text: $newSubtitle)
                } header: {
                    Text("전시 정보")
                } footer: {
                    Text("비워두면 기본 제목으로 생성되며, 전시 안에서 언제든 바꿀 수 있습니다.")
                }

                Section {
                    if isAnalyzingNewPhotos {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("사진 분위기를 분석해 배경음악을 추천하는 중…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(ExhibitionBGMTrack.allCases) { track in
                            BGMSelectionRow(
                                track: track,
                                isSelected: selectedNewBGM == track,
                                isRecommended: newRecommendedBGM?.track == track,
                                isPlaying: bgmPreviewPlayer.playingTrack == track,
                                onSelect: { selectedNewBGM = track },
                                onTogglePreview: { bgmPreviewPlayer.togglePreview(track) }
                            )
                        }

                        Button {
                            selectedNewBGM = nil
                            bgmPreviewPlayer.stop()
                        } label: {
                            HStack {
                                Image(systemName: "speaker.slash")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                Text("배경음악 없음")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedNewBGM == nil {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("배경음악")
                } footer: {
                    if let rec = newRecommendedBGM {
                        Text("추천: \(rec.track.displayName) — \(rec.reason)")
                    } else {
                        Text("사진을 고르면 색감과 밝기를 분석해 어울리는 배경음악을 자동 추천합니다.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("새 전시 만들기")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onChange(of: newPickedItems) { _, items in
                Task {
                    await analyzeNewPickedPhotos(items)
                }
            }
            .onDisappear {
                bgmPreviewPlayer.stop()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        bgmPreviewPlayer.stop()
                        showNewExhibitionSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("만들기") {
                        bgmPreviewPlayer.stop()
                        let preloaded = newLoadedPhotos
                        let items = newPickedItems
                        let title = newTitle
                        let subtitle = newSubtitle
                        let chosenBGM = selectedNewBGM?.fileURL
                        showNewExhibitionSheet = false
                        newPickedItems = []
                        newLoadedPhotos = []
                        newTitle = ""
                        newSubtitle = ""
                        newRecommendedBGM = nil
                        Task {
                            await createAndOpenExhibition(
                                title: title,
                                subtitle: subtitle,
                                preloaded: preloaded,
                                items: items,
                                bgmFileURL: chosenBGM
                            )
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(newPickedItems.isEmpty || isAnalyzingNewPhotos)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    // MARK: - Library Loading & Creation
    private func reloadLibrary() {
        store.refreshCloudPackages()
        var entries: [ExhibitionEntry] = []

        // 1. User's own exhibitions first
        for pkg in store.savedPackages {
            if let entry = buildEntry(from: pkg.url, isSample: false) {
                entries.append(entry)
            }
        }

        // 2. Single curated editorial sample: Rainy Fukuoka
        if let fukuokaURL = locateFukuokaSampleURL(),
           let sampleEntry = buildEntry(from: fukuokaURL, isSample: true) {
            entries.append(sampleEntry)
        }

        self.libraryEntries = entries
    }

    private func buildEntry(from url: URL, isSample: Bool) -> ExhibitionEntry? {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let title = (json["title"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let subtitle = (json["subtitle"] as? String) ?? ""
        let imgDir = url.appendingPathComponent("images", isDirectory: true)
        let imageFiles = (try? FileManager.default.contentsOfDirectory(
            at: imgDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        // Prefer cover hero_image if present
        var coverURL: URL? = imageFiles.first
        if let scenes = json["scenes"] as? [[String: Any]],
           let firstCover = scenes.first(where: { ($0["type"] as? String) == "cover" }),
           let hero = firstCover["hero_image"] as? [String: Any],
           let src = hero["src"] as? String {
            let candidate = url.appendingPathComponent(src)
            if FileManager.default.fileExists(atPath: candidate.path) {
                coverURL = candidate
            }
        }

        return ExhibitionEntry(
            id: url.path,
            title: title,
            subtitle: subtitle,
            url: url,
            coverImageURL: coverURL,
            photoCount: imageFiles.count,
            isSample: isSample
        )
    }

    private func locateFukuokaSampleURL() -> URL? {
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: "Rainy_Fukuoka", withExtension: "gallery") {
            candidates.append(bundled)
        }
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("demo/Rainy_Fukuoka.gallery")
        )
        candidates.append(
            URL(fileURLWithPath: "/Users/mj/.gemini/antigravity/scratch/digital-gallery/demo/Rainy_Fukuoka.gallery")
        )
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func analyzeNewPickedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            newLoadedPhotos = []
            newRecommendedBGM = nil
            return
        }
        isAnalyzingNewPhotos = true
        var loaded: [(Data, String)] = []
        let stamp = Int(Date().timeIntervalSince1970)
        for (idx, item) in items.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append((data, "photo_\(stamp)_\(idx + 1).jpg"))
            }
        }
        newLoadedPhotos = loaded
        let rec = MoodAudioAdvisor.recommend(from: loaded.map(\.0))
        newRecommendedBGM = rec
        selectedNewBGM = rec.track
        isAnalyzingNewPhotos = false
    }

    private func createAndOpenExhibition(
        title: String,
        subtitle: String,
        preloaded: [(Data, String)],
        items: [PhotosPickerItem],
        bgmFileURL: URL?
    ) async {
        isCreatingExhibition = true
        var loaded = preloaded
        if loaded.isEmpty {
            let stamp = Int(Date().timeIntervalSince1970)
            for (idx, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    loaded.append((data, "photo_\(stamp)_\(idx + 1).jpg"))
                }
            }
        }

        let created = store.createNewExhibition(
            title: title,
            subtitle: subtitle,
            photos: loaded,
            bgmFileURL: bgmFileURL
        )
        isCreatingExhibition = false
        if created, let pkgURL = store.sourceRootURL {
            reloadLibrary()
            if let entry = libraryEntries.first(where: { $0.url.standardizedFileURL == pkgURL.standardizedFileURL }) {
                navigationPath = [entry]
            }
        } else {
            showToast(store.errorMessage ?? "새 전시를 만들지 못했어요", isError: true)
        }
    }

    #if os(macOS)
    private func pickFolderToCreateExhibition() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "이 폴더로 전시 만들기"
        if panel.runModal() == .OK, let url = panel.url {
            store.scanFolder(at: url)
            if store.manifest != nil {
                store.saveToCloudPackage()
                reloadLibrary()
                if let savedURL = store.sourceRootURL,
                   let entry = libraryEntries.first(where: { $0.url.standardizedFileURL == savedURL.standardizedFileURL }) {
                    navigationPath = [entry]
                }
            } else {
                showToast(store.errorMessage ?? "폴더를 스캔하지 못했어요", isError: true)
            }
        }
    }
    #endif

    private func handleLaunchArgumentsIfNeeded() {
        guard navigationPath.isEmpty else { return }
        if CommandLine.arguments.contains("--open-sample"), let first = libraryEntries.first {
            navigationPath = [first]
        }
    }

    private func showToast(_ message: String, isError: Bool = false) {
        toastTask?.cancel()
        isToastError = isError
        toastMessage = message
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            toastMessage = nil
        }
    }

    private var toastOverlay: some View {
        VStack {
            if let toast = toastMessage {
                HStack(spacing: 8) {
                    Image(systemName: isToastError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isToastError ? .red : .accentColor)
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .allowsHitTesting(false)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: toastMessage)
    }

    private func loadingOverlay(_ text: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
    }

    private var systemGroupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
}

// MARK: - Exhibition Cover Card (Apple Photos Collection Card)
private struct ExhibitionCoverCard: View {
    let entry: ExhibitionEntry

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                if let coverURL = entry.coverImageURL {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        default:
                            Color.secondary.opacity(0.14)
                        }
                    }
                } else {
                    Color.secondary.opacity(0.14)
                }

                // Subtle editorial bottom scrim
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.72),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Top-left subtle badge
                VStack {
                    HStack {
                        Text(entry.isSample ? "샘플 전시" : "내 전시")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                    }
                    Spacer()
                }
                .padding(16)

                // Bottom title & full subtitle (no cramped button truncating text)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(entry.subtitle.isEmpty ? "사진 \(entry.photoCount)장" : "\(entry.subtitle) · \(entry.photoCount)장")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                }
                .padding(18)
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }
}

// MARK: - Reusable BGM Track Selection Row (with Recommendation Badge & Live Preview)
private struct BGMSelectionRow: View {
    let track: ExhibitionBGMTrack
    let isSelected: Bool
    let isRecommended: Bool
    let isPlaying: Bool
    let onSelect: () -> Void
    let onTogglePreview: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTogglePreview) {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isPlaying ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Button(action: onSelect) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(track.displayName)
                                .font(.body.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(.primary)
                            if isRecommended {
                                Text("추천")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                        }
                        Text(track.moodTag)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Screen 2: Full-Screen Immersive Exhibition Viewer + Photos Grid + Clean Editor
private struct ExhibitionViewerScreen: View {
    let entry: ExhibitionEntry
    @Bindable var store: GalleryStore
    let onLibraryUpdated: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var webController = WebPreviewController()
    @State private var viewerMode: ViewerMode = .exhibition
    @State private var showInspector = false
    @State private var showMobileEditorSheet = false
    @State private var showShareSheet = false
    @State private var exportedShareURL: URL?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pickedPhotoItems: [PhotosPickerItem] = []

    // Live editor fields
    @State private var editTitle = ""
    @State private var editChapter = ""
    @State private var editNote = ""
    @State private var editCaption = ""
    @State private var isSyncingFields = false
    @State private var debounceTask: Task<Void, Never>?

    // Toast, BGM & Haptics
    @State private var bgmPreviewPlayer = BGMPreviewPlayer()
    @State private var moodRecommendation: MoodBGMRecommendation?
    @State private var activeBGMTrack: ExhibitionBGMTrack?
    @State private var toastMessage: String?
    @State private var isToastError = false
    @State private var toastTask: Task<Void, Never>?
    @State private var hapticTick = 0

    var body: some View {
        ZStack {
            if viewerMode == .exhibition {
                if store.previewHTMLURL != nil {
                    ExhibitionWebView(
                        htmlURL: store.previewHTMLURL,
                        readAccessURL: store.previewDirectoryURL,
                        revision: store.previewRevision,
                        controller: webController
                    )
                    .ignoresSafeArea()
                } else {
                    ProgressView("전시를 준비하는 중…")
                }
            } else {
                applePhotosGridView
            }

            // Floating Toast / Loading Pill
            VStack {
                if isImporting || isExporting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(isImporting ? "사진 추가하는 중…" : "초대장 파일 준비 중…")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 10)
                } else if let toast = toastMessage {
                    HStack(spacing: 8) {
                        Image(systemName: isToastError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(isToastError ? .red : .accentColor)
                        Text(toast)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .allowsHitTesting(false)
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: toastMessage)
        }
        .navigationTitle(store.manifest?.title ?? entry.title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(viewerMode == .exhibition ? .hidden : .automatic, for: .navigationBar)
        #endif
        .sensoryFeedback(.selection, trigger: hapticTick)
        .inspector(isPresented: $showInspector) {
            editorFormView
                .inspectorColumnWidth(min: 300, ideal: 340, max: 400)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("보기 모드", selection: $viewerMode) {
                    ForEach(ViewerMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 144)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button("편집") {
                    hapticTick += 1
                    if horizontalSizeClass == .compact {
                        showMobileEditorSheet.toggle()
                    } else {
                        showInspector.toggle()
                    }
                }
                .fontWeight(.medium)

                Button {
                    openShareSheet()
                } label: {
                    Label("공유", systemImage: "square.and.arrow.up")
                }
                .disabled(store.manifest == nil)
            }
        }
        .sheet(isPresented: $showMobileEditorSheet) {
            NavigationStack {
                editorFormView
                    .navigationTitle("전시 편집")
                    #if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            HStack(spacing: 14) {
                                Button {
                                    store.undo()
                                    syncInspectorFields()
                                    showToast("실행 취소")
                                } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                }
                                .disabled(!store.canUndo)

                                Button {
                                    store.redo()
                                    syncInspectorFields()
                                    showToast("다시 실행")
                                } label: {
                                    Image(systemName: "arrow.uturn.forward")
                                }
                                .disabled(!store.canRedo)
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("완료") { showMobileEditorSheet = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: $showShareSheet) {
            nativeShareModalSheet
        }
        .onAppear {
            wireLiveBridge()
            if store.sourceRootURL?.standardizedFileURL != entry.url.standardizedFileURL || store.manifest == nil {
                store.loadPackage(at: entry.url)
            }
            syncInspectorFields()
            refreshMoodBGMRecommendation()
            if CommandLine.arguments.contains("--open-editor") {
                if horizontalSizeClass == .compact {
                    showMobileEditorSheet = true
                } else {
                    showInspector = true
                }
            }
        }
        .onDisappear {
            bgmPreviewPlayer.stop()
        }
        .onChange(of: store.selectedSceneID) { _, newID in
            syncInspectorFields()
            if let newID {
                webController.scrollToScene(newID)
            }
        }
        .onChange(of: pickedPhotoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            let toLoad = newItems
            pickedPhotoItems = []
            Task {
                await importPickedPhotos(toLoad)
            }
        }
    }

    // MARK: - Apple Photos–Style 3-Column Photo Grid
    private var applePhotosGridView: some View {
        let images = collectProjectImages()
        let columns = [
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2),
        ]

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("사진 \(images.count)장")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    PhotosPicker(
                        selection: $pickedPhotoItems,
                        maxSelectionCount: 30,
                        matching: .images
                    ) {
                        Label("사진 추가", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(images, id: \.path) { url in
                        GeometryReader { geo in
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: geo.size.width, height: geo.size.width)
                                        .clipped()
                                default:
                                    Color.secondary.opacity(0.12)
                                }
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Native Apple Form Editor (Clean, Serious, Zero Clutter)
    private var editorFormView: some View {
        Form {
            if let manifest = store.manifest {
                // 1. Theme Selection
                Section("전시 스타일") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ExhibitionThemePreset.allCases) { preset in
                                let isCurrent = (manifest.themePreset == preset.rawValue)
                                Button {
                                    store.updateTheme(preset)
                                    hapticTick += 1
                                    showToast("'\(preset.displayName)' 스타일 적용됨")
                                } label: {
                                    VStack(spacing: 6) {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(themeSwatchColor(for: preset))
                                            .frame(width: 48, height: 32)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(isCurrent ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isCurrent ? 2.5 : 1)
                                            )
                                        Text(shortThemeName(preset))
                                            .font(.caption2.weight(isCurrent ? .bold : .regular))
                                            .foregroundStyle(isCurrent ? .primary : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // 2. Scene Picker + Add Photos
                Section("장면 선택 (\(manifest.sceneCount)개)") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(manifest.scenes.enumerated()), id: \.element.id) { idx, scene in
                                let isSelected = (store.selectedScene?.id == scene.id)
                                Button {
                                    store.selectScene(scene.id)
                                    hapticTick += 1
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(String(format: "%02d", idx + 1))
                                            .font(.caption2.monospacedDigit().bold())
                                            .foregroundStyle(isSelected ? .white : .secondary)
                                        Text(friendlySceneTitle(scene))
                                            .font(.caption.weight(.medium))
                                            .lineLimit(1)
                                            .foregroundStyle(isSelected ? .white : .primary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.14))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    PhotosPicker(
                        selection: $pickedPhotoItems,
                        maxSelectionCount: 30,
                        matching: .images
                    ) {
                        Label("사진 여러 장 추가 (최대 30장)", systemImage: "photo.badge.plus")
                    }
                }
            }

            // 3. Selected Scene Text & Mood
            if let scene = store.selectedScene {
                Section("선택한 장면 편집") {
                    TextField("제목", text: $editTitle)
                        .onChange(of: editTitle) { _, _ in scheduleLiveTextPatch(sceneID: scene.id) }
                    TextField("소제목 / 챕터", text: $editChapter)
                        .onChange(of: editChapter) { _, _ in scheduleLiveTextPatch(sceneID: scene.id) }
                    TextField("설명 문구", text: $editNote, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: editNote) { _, _ in scheduleLiveTextPatch(sceneID: scene.id) }
                    TextField("캡션 / 날짜", text: $editCaption)
                        .onChange(of: editCaption) { _, _ in scheduleLiveTextPatch(sceneID: scene.id) }

                    Picker("조명 분위기", selection: Binding(
                        get: { LightingPreset(rawValue: scene.mood) ?? .warmPaper },
                        set: { newMood in
                            store.updateMood(sceneID: scene.id, preset: newMood)
                            hapticTick += 1
                        }
                    )) {
                        Text("밝음").tag(LightingPreset.warmPaper)
                        Text("은은함").tag(LightingPreset.softDim)
                        Text("어두움").tag(LightingPreset.darkRoom)
                        Text("깊은 밤").tag(LightingPreset.obsidian)
                    }

                    if let manifest = store.manifest,
                       manifest.scenes.count > 2,
                       scene.kind != "cover",
                       scene.kind != "ending" {
                        Button(role: .destructive) {
                            store.removeScene(sceneID: scene.id)
                            syncInspectorFields()
                            showToast("장면을 삭제했어요")
                        } label: {
                            Label("이 장면 삭제", systemImage: "trash")
                        }
                    }
                }
            }

            // 4. Mood-Based BGM Recommendation & Picker
            Section {
                ForEach(ExhibitionBGMTrack.allCases) { track in
                    BGMSelectionRow(
                        track: track,
                        isSelected: activeBGMTrack == track,
                        isRecommended: moodRecommendation?.track == track,
                        isPlaying: bgmPreviewPlayer.playingTrack == track,
                        onSelect: {
                            activeBGMTrack = track
                            store.applyExhibitionBGM(fileURL: track.fileURL)
                            hapticTick += 1
                            showToast("'\(track.displayName)' 배경음악 적용됨")
                        },
                        onTogglePreview: {
                            bgmPreviewPlayer.togglePreview(track)
                        }
                    )
                }

                Button {
                    activeBGMTrack = nil
                    bgmPreviewPlayer.stop()
                    store.applyExhibitionBGM(fileURL: nil)
                    hapticTick += 1
                    showToast("배경음악을 껐어요")
                } label: {
                    HStack {
                        Image(systemName: "speaker.slash")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text("배경음악 없음")
                            .foregroundStyle(.primary)
                        Spacer()
                        if activeBGMTrack == nil {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("배경음악")
            } footer: {
                if let rec = moodRecommendation {
                    Text("사진 분위기 추천: \(rec.track.displayName) — \(rec.reason)")
                } else {
                    Text("재생 버튼을 눌러 미리 듣고 전시에 어울리는 배경음악을 선택하세요.")
                }
            }

            // 5. Save
            Section {
                Button {
                    store.saveToCloudPackage()
                    onLibraryUpdated()
                    hapticTick += 1
                    showToast(store.errorMessage ?? "전시 프로젝트를 저장했어요", isError: store.errorMessage != nil)
                } label: {
                    Label(store.isICloudAvailable ? "iCloud에 사본 저장" : "전시 프로젝트 저장", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("내 전시의 모든 변경 사항은 자동으로 저장됩니다.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Native Share Sheet Modal
    private var nativeShareModalSheet: some View {
        NavigationStack {
            Form {
                Section {
                    #if os(macOS)
                    Button {
                        showShareSheet = false
                        exportHTMLOnMac(singleFile: true)
                    } label: {
                        Label("오프라인 전시 파일 저장 (.html)", systemImage: "doc.richtext")
                    }
                    Button {
                        showShareSheet = false
                        exportHTMLOnMac(singleFile: false)
                    } label: {
                        Label("웹 게시용 폴더로 저장", systemImage: "folder")
                    }
                    #else
                    if isExporting {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("공유할 전시 파일을 만드는 중…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let url = exportedShareURL {
                        ShareLink(
                            item: url,
                            subject: Text(store.manifest?.title ?? "Memoria 전시"),
                            message: Text("Memoria로 만든 디지털 전시를 열어보세요.")
                        ) {
                            Label("전시 파일 바로 공유하기 (AirDrop · 메시지 · 카카오톡)", systemImage: "square.and.arrow.up")
                                .fontWeight(.semibold)
                        }
                    } else {
                        Button {
                            prepareShareFileForIOS()
                        } label: {
                            Label("전시 파일 다시 준비하기", systemImage: "arrow.clockwise")
                        }
                    }
                    #endif
                } header: {
                    Text("전시 공유")
                } footer: {
                    Text("단일 HTML 파일로 내보내져 별도 서버 없이 Safari에서 바로 감상할 수 있습니다.")
                }

                Section {
                    Button {
                        store.saveToCloudPackage()
                        onLibraryUpdated()
                        showShareSheet = false
                        showToast(store.errorMessage ?? "전시 프로젝트를 저장했어요", isError: store.errorMessage != nil)
                    } label: {
                        Label("내 기기에 프로젝트 저장 (.gallery)", systemImage: "icloud.and.arrow.up")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("공유 및 저장")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { showShareSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 260)
        #endif
    }

    // MARK: - Helpers
    private func openShareSheet() {
        hapticTick += 1
        showShareSheet = true
        #if !os(macOS)
        prepareShareFileForIOS()
        #endif
    }

    #if !os(macOS)
    private func prepareShareFileForIOS() {
        exportedShareURL = nil
        isExporting = true
        Task {
            let outDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("memoria-share", isDirectory: true)
            let result = store.exportToFolder(outDir, singleFile: true)
            isExporting = false
            if let result {
                exportedShareURL = URL(fileURLWithPath: result.outputHtml)
            } else {
                showToast(store.errorMessage ?? "전시 파일 준비에 실패했어요", isError: true)
            }
        }
    }
    #endif

    #if os(macOS)
    private func exportHTMLOnMac(singleFile: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = singleFile ? "HTML 저장" : "폴더 저장"
        if panel.runModal() == .OK, let url = panel.url {
            isExporting = true
            let result = store.exportToFolder(url, singleFile: singleFile)
            isExporting = false
            if let result {
                showToast(singleFile ? "오프라인 전시 파일(.html) 저장 완료" : "웹 게시용 폴더 저장 완료")
                NSWorkspace.shared.open(URL(fileURLWithPath: result.outputHtml))
            } else {
                showToast(store.errorMessage ?? "저장에 실패했어요", isError: true)
            }
        }
    }
    #endif

    private func importPickedPhotos(_ items: [PhotosPickerItem]) async {
        isImporting = true
        var loaded: [(Data, String)] = []
        let stamp = Int(Date().timeIntervalSince1970)
        for (idx, item) in items.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append((data, "photo_\(stamp)_\(idx + 1).jpg"))
            }
        }
        let added = store.importMultiplePhotoData(loaded)
        isImporting = false
        hapticTick += 1
        if added > 0 {
            showToast("사진 \(added)장을 추가했어요")
        } else {
            showToast(store.errorMessage ?? "사진을 추가하지 못했어요", isError: true)
        }
    }

    private func refreshMoodBGMRecommendation() {
        let urls = collectProjectImages()
        moodRecommendation = MoodAudioAdvisor.recommend(from: urls)
        // Detect if an existing scene already uses one of our curated tracks
        if let firstAudio = store.manifest?.scenes.compactMap(\.audioTrack).first {
            let base = URL(fileURLWithPath: firstAudio).deletingPathExtension().lastPathComponent
            activeBGMTrack = ExhibitionBGMTrack(rawValue: base)
        } else {
            activeBGMTrack = nil
        }
    }

    private func collectProjectImages() -> [URL] {
        guard let root = store.sourceRootURL else { return [] }
        let imgDir = root.appendingPathComponent("images", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: imgDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return items.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func friendlySceneTitle(_ scene: FfiSceneSummary) -> String {
        if scene.title.hasPrefix("Horizontal Walk") {
            return "사진 컬렉션 (\(scene.items.count)장)"
        }
        return scene.title
    }

    private func shortThemeName(_ preset: ExhibitionThemePreset) -> String {
        switch preset {
        case .editorialGallery: return "에디토리얼"
        case .tossClean: return "미니멀"
        case .atelierPoster: return "포스터"
        case .midnightFilm: return "다크 필름"
        case .memoriaPastel: return "파스텔"
        }
    }

    private func themeSwatchColor(for preset: ExhibitionThemePreset) -> Color {
        switch preset {
        case .editorialGallery: return Color(red: 0.96, green: 0.95, blue: 0.92)
        case .tossClean: return Color(red: 0.95, green: 0.97, blue: 1.00)
        case .atelierPoster: return Color(red: 0.90, green: 0.90, blue: 0.88)
        case .midnightFilm: return Color(red: 0.11, green: 0.12, blue: 0.14)
        case .memoriaPastel: return Color(red: 0.82, green: 0.91, blue: 1.00)
        }
    }

    private func wireLiveBridge() {
        store.liveCallbacks.onScrollToScene = { sceneID in
            webController.scrollToScene(sceneID)
        }
        store.liveCallbacks.onPatchAtmosphere = { sceneID, palette in
            webController.patchAtmosphere(sceneID: sceneID, palette: palette)
        }
        store.liveCallbacks.onPatchText = { sceneID, title, chapter, note, caption in
            webController.patchText(sceneID: sceneID, title: title, chapter: chapter, note: note, caption: caption)
        }
        store.liveCallbacks.onPatchItem = { sceneID, index, title, caption in
            webController.patchItem(sceneID: sceneID, index: index, title: title, caption: caption)
        }
        store.liveCallbacks.onPatchTheme = { preset in
            webController.patchTheme(preset)
        }
    }

    private func syncInspectorFields() {
        guard let scene = store.selectedScene else { return }
        isSyncingFields = true
        editTitle = scene.title
        editChapter = scene.chapterLabel ?? ""
        editNote = scene.subtitleOrNote ?? ""
        editCaption = scene.caption ?? ""
        DispatchQueue.main.async {
            isSyncingFields = false
        }
    }

    private func scheduleLiveTextPatch(sceneID: String) {
        guard !isSyncingFields else { return }
        debounceTask?.cancel()
        let t = editTitle
        let ch = editChapter
        let n = editNote
        let cap = editCaption
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            store.updateTextLive(
                sceneID: sceneID,
                title: t,
                subtitleOrNote: n,
                caption: cap,
                chapterLabel: ch,
                recordUndo: true
            )
        }
    }

    private func showToast(_ message: String, isError: Bool = false) {
        toastTask?.cancel()
        isToastError = isError
        toastMessage = message
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            toastMessage = nil
        }
    }
}
