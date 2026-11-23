import GalleryBridge
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

enum PreviewViewport: String, CaseIterable, Identifiable {
    case mobile = "Mobile"
    case desktop = "Desktop"
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var store = GalleryStore()
    @State private var webController = WebPreviewController()
    @State private var viewport: PreviewViewport = .mobile
    @State private var showInspector = true
    @State private var showMobileEditorSheet = false
    @State private var exportedShareURL: URL?
    @State private var pickedPhotoItem: PhotosPickerItem?

    // Live-bound Inspector fields (debounced zero-reload updates)
    @State private var editTitle = ""
    @State private var editChapter = ""
    @State private var editNote = ""
    @State private var editCaption = ""
    @State private var isSyncingFields = false
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            previewStageView
                .inspector(isPresented: $showInspector) {
                    inspectorView
                        .inspectorColumnWidth(min: 290, ideal: 330, max: 390)
                }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                PhotosPicker(selection: $pickedPhotoItem, matching: .images) {
                    Label("사진 보관함", systemImage: "photo.on.rectangle")
                }
                .disabled(store.manifest == nil)
                .help("Apple 사진 보관함에서 바로 작품을 추가합니다")

                #if os(macOS)
                Button {
                    pickFolderToScan()
                } label: {
                    Label("폴더 스캔", systemImage: "folder.badge.plus")
                }
                .help("사진 폴더를 EXIF 분석해 전시관 초안을 자동 생성합니다")
                #endif

                Button {
                    openDemoPackage(named: "Our_Wedding_2027")
                } label: {
                    Label("청첩장 데모", systemImage: "sparkles")
                }

                #if os(iOS)
                Button {
                    openDemoPackage(named: "Rainy_Fukuoka")
                } label: {
                    Label("여행전 데모", systemImage: "airplane")
                }
                #endif
            }

            #if os(macOS)
            ToolbarItem(placement: .principal) {
                Picker("Viewport", selection: $viewport) {
                    ForEach(PreviewViewport.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            #endif

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.undo()
                } label: {
                    Label("실행 취소", systemImage: "arrow.uturn.backward")
                }
                .disabled(!store.canUndo)
                .keyboardShortcut("z", modifiers: [.command])

                Button {
                    store.redo()
                } label: {
                    Label("다시 실행", systemImage: "arrow.uturn.forward")
                }
                .disabled(!store.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Button {
                    store.saveToCloudPackage()
                } label: {
                    Label(
                        store.isICloudAvailable ? "iCloud 저장" : ".gallery 저장",
                        systemImage: store.isICloudAvailable ? "icloud.and.arrow.up" : "archivebox"
                    )
                }
                .disabled(store.manifest == nil)

                #if os(macOS)
                Menu {
                    Button {
                        exportHTMLPackage(singleFile: true)
                    } label: {
                        Label("단일 HTML로 공유 (AirDrop / iOS 파일)", systemImage: "doc.richtext")
                    }
                    Button {
                        exportHTMLPackage(singleFile: false)
                    } label: {
                        Label("웹 폴더로 내보내기 (index.html + assets/)", systemImage: "folder")
                    }
                } label: {
                    Label("공유 / 내보내기", systemImage: "square.and.arrow.up")
                }
                .disabled(store.manifest == nil)
                #else
                if let shareURL = exportedShareURL {
                    ShareLink(item: shareURL) {
                        Label("공유", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        prepareIOSSingleFileShare()
                    } label: {
                        Label("HTML 생성", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.manifest == nil)
                }
                #endif

                Button {
                    if horizontalSizeClass == .compact {
                        showMobileEditorSheet.toggle()
                    } else {
                        showInspector.toggle()
                    }
                } label: {
                    Label("편집", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showMobileEditorSheet) {
            NavigationStack {
                inspectorView
                    .navigationTitle("전시 편집")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("완료") { showMobileEditorSheet = false }
                        }
                    }
            }
        }
        .onAppear {
            wireLiveBridge()
            if store.manifest == nil {
                if let pkgIdx = CommandLine.arguments.firstIndex(of: "--package"),
                   pkgIdx + 1 < CommandLine.arguments.count
                {
                    let pkgURL = URL(fileURLWithPath: CommandLine.arguments[pkgIdx + 1])
                    store.loadPackage(at: pkgURL)
                } else {
                    openDemoPackage()
                }
            }
            if let themeIdx = CommandLine.arguments.firstIndex(of: "--theme"),
               themeIdx + 1 < CommandLine.arguments.count,
               let preset = ExhibitionThemePreset(rawValue: CommandLine.arguments[themeIdx + 1])
            {
                store.updateTheme(preset)
                store.refreshLivePreview()
            }
            if let sceneIdx = CommandLine.arguments.firstIndex(of: "--scene"),
               sceneIdx + 1 < CommandLine.arguments.count
            {
                let targetSceneID = CommandLine.arguments[sceneIdx + 1]
                store.selectedSceneID = targetSceneID
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                    webController.scrollToScene(targetSceneID)
                }
            }
            syncInspectorFields()
        }
        .onChange(of: store.selectedSceneID) { _, newID in
            syncInspectorFields()
            if let newID {
                webController.scrollToScene(newID)
            }
        }
        .onChange(of: pickedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    let filename = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
                    store.importPhotoDataAsSpotlight(data: data, suggestedFilename: filename)
                }
                pickedPhotoItem = nil
            }
        }
    }

    // MARK: - Left Sidebar
    private var sidebarView: some View {
        VStack(spacing: 0) {
            if let manifest = store.manifest {
                List(selection: $store.selectedSceneID) {
                    Section("\(manifest.title) · \(manifest.sceneCount) Scenes") {
                        ForEach(manifest.scenes, id: \.id) { scene in
                            SceneRowView(scene: scene)
                                .tag(scene.id)
                        }
                        .onMove { source, destination in
                            store.moveScenes(from: source, to: destination)
                        }
                    }

                    if !store.savedPackages.isEmpty {
                        Section(store.isICloudAvailable ? "iCloud Drive (.gallery)" : "저장된 .gallery 패키지") {
                            ForEach(store.savedPackages) { pkg in
                                Button {
                                    store.loadPackage(at: pkg.url)
                                } label: {
                                    Label(
                                        pkg.name,
                                        systemImage: pkg.isICloudBacked ? "icloud" : "doc.zipper"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            } else {
                ContentUnavailableView(
                    "전시관 없음",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("상단의 '폴더 스캔' 또는 '데모'를 눌러 시작하세요.")
                )
            }

            Divider()
            HStack(spacing: 6) {
                Image(systemName: store.errorMessage == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(store.errorMessage == nil ? Color.secondary : Color.red)
                    .font(.caption)
                Text(store.errorMessage ?? store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(store.errorMessage == nil ? Color.secondary : Color.red)
                    .lineLimit(2)
                Spacer()
            }
            .padding(10)
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 340)
    }

    // MARK: - Center Stage (WKWebView Live Preview)
    private var previewStageView: some View {
        ZStack {
            stageBackgroundColor.ignoresSafeArea()

            if store.previewHTMLURL != nil {
                Group {
                    #if os(macOS)
                    if viewport == .mobile {
                        ExhibitionWebView(
                            htmlURL: store.previewHTMLURL,
                            readAccessURL: store.previewDirectoryURL,
                            revision: store.previewRevision,
                            controller: webController
                        )
                        .frame(width: 393, height: 740)
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.24), radius: 28, y: 12)
                        .padding(20)
                    } else {
                        ExhibitionWebView(
                            htmlURL: store.previewHTMLURL,
                            readAccessURL: store.previewDirectoryURL,
                            revision: store.previewRevision,
                            controller: webController
                        )
                    }
                    #else
                    ExhibitionWebView(
                        htmlURL: store.previewHTMLURL,
                        readAccessURL: store.previewDirectoryURL,
                        revision: store.previewRevision,
                        controller: webController
                    )
                    .ignoresSafeArea(edges: .bottom)
                    #endif
                }
            } else {
                ContentUnavailableView(
                    "실시간 미리보기",
                    systemImage: "safari",
                    description: Text("Rust Core가 생성한 HTML 전시관이 여기에 실시간으로 표시됩니다.")
                )
            }
        }
    }

    private var stageBackgroundColor: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(.systemGroupedBackground)
        #endif
    }

    // MARK: - Right Inspector (Design Theme + Live Text + Sub-Items + Lighting + Audio)
    private var inspectorView: some View {
        Form {
            if let manifest = store.manifest {
                Section("디자인 시안 (Toss Simplicity 기반)") {
                    ForEach(ExhibitionThemePreset.allCases) { preset in
                        Button {
                            store.updateTheme(preset)
                        } label: {
                            HStack(spacing: 10) {
                                themeSwatch(for: preset)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.displayName)
                                        .font(.callout.weight(.medium))
                                    Text(preset.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if manifest.themePreset == preset.rawValue {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let scene = store.selectedScene {
                Section("실시간 텍스트 · 캡션 (자동 반영)") {
                    TextField("챕터 라벨 (예: Room 01)", text: $editChapter)
                        .onChange(of: editChapter) { _, _ in scheduleLiveTextPatch(sceneID: scene.id) }
                    TextField("제목", text: $editTitle)
                        .onChange(of: editTitle) { _, _ in scheduleLiveTextPatch(sceneID: scene.id) }
                    TextField("서브타이틀 / 노트", text: $editNote, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: editNote) { _, _ in scheduleLiveTextPatch(sceneID: scene.id) }
                    TextField("작품 캡션 / 날짜", text: $editCaption)
                        .onChange(of: editCaption) { _, _ in scheduleLiveTextPatch(sceneID: scene.id) }
                }

                if !scene.items.isEmpty {
                    Section(scene.kind == "horizontal_track" ? "가로 갤러리 개별 작품 (\(scene.items.count)장)" : "스토리 개별 비트 (\(scene.items.count)개)") {
                        ForEach(scene.items, id: \.index) { item in
                            SubItemEditorRow(
                                sceneID: scene.id,
                                item: item,
                                canDelete: scene.items.count > 1,
                                onSave: { newTitle, newCaption in
                                    store.updateItemLive(
                                        sceneID: scene.id,
                                        itemIndex: item.index,
                                        title: newTitle,
                                        caption: newCaption
                                    )
                                },
                                onDelete: {
                                    store.removeItem(sceneID: scene.id, itemIndex: item.index)
                                }
                            )
                        }
                    }
                }

                Section("조명 무드 (Atmosphere)") {
                    ForEach(LightingPreset.allCases) { preset in
                        Button {
                            store.updateMood(sceneID: scene.id, preset: preset)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(colorForMood(preset.rawValue))
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 0.5))
                                Text(preset.displayName)
                                Spacer()
                                if scene.mood == preset.rawValue {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("사운드 큐 (Ambient Audio)") {
                    if let track = scene.audioTrack {
                        LabeledContent("트랙", value: URL(fileURLWithPath: track).lastPathComponent)
                    } else {
                        Text("연결된 사운드 없음")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    #if os(macOS)
                    HStack {
                        Button("오디오 선택") {
                            pickAudioForScene(sceneID: scene.id)
                        }
                        if scene.hasAudio {
                            Button("제거", role: .destructive) {
                                store.clearAudio(from: scene.id)
                            }
                        }
                    }
                    #endif
                }

                Section("씬 관리") {
                    LabeledContent("유형", value: scene.kind)
                    LabeledContent("미디어 수", value: "\(scene.assetCount)개")
                    Button("이 씬 삭제", role: .destructive) {
                        store.removeScene(sceneID: scene.id)
                    }
                    .disabled((store.manifest?.sceneCount ?? 0) <= 1)
                }
            } else {
                Text("좌측에서 씬을 선택하면 캡션, 조명, 사운드를 실시간으로 편집할 수 있습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Live Bridge Wiring & Debounced Editing
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

    // MARK: - Actions
    private func openDemoPackage(named name: String = "Our_Wedding_2027") {
        exportedShareURL = nil
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: name, withExtension: "gallery") {
            candidates.append(bundled)
        }
        if let bundledFallback = Bundle.main.url(forResource: "Rainy_Fukuoka", withExtension: "gallery") {
            candidates.append(bundledFallback)
        }
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("demo/\(name).gallery")
        )
        candidates.append(
            URL(fileURLWithPath: "/Users/mj/.gemini/antigravity/scratch/digital-gallery/demo/\(name).gallery")
        )
        candidates.append(
            URL(fileURLWithPath: "/Users/mj/.gemini/antigravity/scratch/digital-gallery/demo/Quiet_Autumn.gallery")
        )

        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            store.loadPackage(at: found)
        } else {
            store.errorMessage = "데모 패키지를 찾지 못했습니다."
        }
    }

    #if os(iOS)
    private func prepareIOSSingleFileShare() {
        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("digital-gallery-share", isDirectory: true)
        if let result = store.exportToFolder(outDir, singleFile: true) {
            exportedShareURL = URL(fileURLWithPath: result.outputHtml)
        }
    }
    #endif

    #if os(macOS)
    private func pickFolderToScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "이 폴더 스캔"
        if panel.runModal() == .OK, let url = panel.url {
            store.scanFolder(at: url)
        }
    }

    private func pickAudioForScene(sceneID: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        panel.prompt = "오디오 연결"
        if panel.runModal() == .OK, let url = panel.url {
            store.attachAudio(to: sceneID, fileURL: url)
        }
    }

    private func exportHTMLPackage(singleFile: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = singleFile ? "단일 HTML 저장" : "여기에 내보내기"
        if panel.runModal() == .OK, let url = panel.url {
            if let result = store.exportToFolder(url, singleFile: singleFile) {
                NSWorkspace.shared.open(URL(fileURLWithPath: result.outputHtml))
            }
        }
    }
    #endif
}

private struct SubItemEditorRow: View {
    let sceneID: String
    let item: FfiSceneItem
    let canDelete: Bool
    let onSave: (String?, String?) -> Void
    let onDelete: () -> Void

    @State private var captionText: String
    @State private var titleText: String

    init(
        sceneID: String,
        item: FfiSceneItem,
        canDelete: Bool,
        onSave: @escaping (String?, String?) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.sceneID = sceneID
        self.item = item
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
        _captionText = State(initialValue: item.caption ?? "")
        _titleText = State(initialValue: item.title ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("#\(item.index + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                if let src = item.mediaSrc {
                    Text(URL(fileURLWithPath: src).lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if canDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField("캡션 / 본문", text: $captionText)
                .font(.caption)
                .onSubmit {
                    onSave(titleText, captionText)
                }
        }
        .padding(.vertical, 4)
    }
}

private struct SceneRowView: View {
    let scene: FfiSceneSummary

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(colorForMood(scene.mood))
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(.secondary.opacity(0.45), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(scene.title)
                    .font(.callout)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(scene.kind.replacingOccurrences(of: "_", with: " "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if scene.hasAudio {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

@ViewBuilder
private func themeSwatch(for preset: ExhibitionThemePreset) -> some View {
    let (bg, accent): (Color, Color) = {
        switch preset {
        case .editorialGallery:
            return (Color(red: 0.96, green: 0.95, blue: 0.92), Color(red: 0.61, green: 0.42, blue: 0.26))
        case .tossClean:
            return (Color.white, Color(red: 0.19, green: 0.51, blue: 0.96))
        case .midnightFilm:
            return (Color(red: 0.07, green: 0.07, blue: 0.06), Color(red: 0.89, green: 0.66, blue: 0.42))
        case .atelierPoster:
            return (Color(red: 0.95, green: 0.94, blue: 0.91), Color(red: 0.48, green: 0.43, blue: 0.34))
        }
    }()
    ZStack {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(bg)
            .frame(width: 26, height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.35), lineWidth: 0.75)
            )
        Circle()
            .fill(accent)
            .frame(width: 9, height: 9)
    }
}

private func colorForMood(_ mood: String) -> Color {
    switch mood {
    case "warm_paper": return Color(red: 0.96, green: 0.95, blue: 0.92)
    case "soft_dim": return Color(red: 0.90, green: 0.87, blue: 0.82)
    case "dark_room": return Color(red: 0.14, green: 0.13, blue: 0.13)
    case "obsidian": return Color(red: 0.04, green: 0.04, blue: 0.05)
    default: return .gray
    }
}
