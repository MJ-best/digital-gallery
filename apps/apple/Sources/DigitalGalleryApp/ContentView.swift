import GalleryBridge
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

enum CenterStageTab: String, CaseIterable, Identifiable {
    case preview = "모바일 전시"
    case galleryGrid = "우리의 갤러리"
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var store = GalleryStore()
    @State private var webController = WebPreviewController()
    @State private var stageTab: CenterStageTab = .preview
    @State private var showInspector = true
    @State private var showMobileEditorSheet = false
    @State private var showMemoriaShareModal = false
    @State private var exportedShareURL: URL?
    @State private var pickedPhotoItem: PhotosPickerItem?

    // Live-bound Inspector fields
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
            ZStack {
                centerStageView
                    .inspector(isPresented: $showInspector) {
                        inspectorView
                            .inspectorColumnWidth(min: 300, ideal: 340, max: 400)
                    }

                if showMemoriaShareModal {
                    Color.black.opacity(0.26)
                        .ignoresSafeArea()
                        .onTapGesture { showMemoriaShareModal = false }
                    memoriaShareCardModal
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.84), value: showMemoriaShareModal)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    openDemoPackage(named: "Our_Wedding_2027")
                } label: {
                    Label("청첩장", systemImage: "heart.fill")
                }

                Button {
                    openDemoPackage(named: "Rainy_Fukuoka")
                } label: {
                    Label("여행전", systemImage: "airplane")
                }

                #if os(macOS)
                Button {
                    pickFolderToScan()
                } label: {
                    Label("폴더 스캔", systemImage: "folder.badge.plus")
                }
                #endif
            }

            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    ForEach(CenterStageTab.allCases) { tab in
                        Button {
                            stageTab = tab
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(stageTab == tab ? Color.white : Color.clear)
                                        .shadow(color: .black.opacity(stageTab == tab ? 0.08 : 0), radius: 6, y: 2)
                                )
                                .foregroundStyle(stageTab == tab ? MemoriaPalette.ink : MemoriaPalette.subInk)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Capsule().fill(MemoriaPalette.softSky))
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button { store.undo() } label: {
                    Label("실행 취소", systemImage: "arrow.uturn.backward")
                }
                .disabled(!store.canUndo)
                .keyboardShortcut("z", modifiers: [.command])

                Button { store.redo() } label: {
                    Label("다시 실행", systemImage: "arrow.uturn.forward")
                }
                .disabled(!store.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Button {
                    showMemoriaShareModal = true
                } label: {
                    Label("공유하기", systemImage: "square.and.arrow.up")
                }
                .disabled(store.manifest == nil)

                Button {
                    if horizontalSizeClass == .compact {
                        showMobileEditorSheet.toggle()
                    } else {
                        showInspector.toggle()
                    }
                } label: {
                    Label("꾸미기", systemImage: "sparkles")
                }
            }
        }
        .sheet(isPresented: $showMobileEditorSheet) {
            NavigationStack {
                inspectorView
                    .navigationTitle("Memoria 꾸미기")
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
                    store.loadPackage(at: URL(fileURLWithPath: CommandLine.arguments[pkgIdx + 1]))
                } else {
                    openDemoPackage(named: "Our_Wedding_2027")
                }
            }
            if let themeIdx = CommandLine.arguments.firstIndex(of: "--theme"),
               themeIdx + 1 < CommandLine.arguments.count,
               let preset = ExhibitionThemePreset(rawValue: CommandLine.arguments[themeIdx + 1])
            {
                store.updateTheme(preset)
                store.refreshLivePreview()
            }
            if CommandLine.arguments.contains("--grid") {
                stageTab = .galleryGrid
            }
            if CommandLine.arguments.contains("--share-sheet") {
                showMemoriaShareModal = true
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

    // MARK: - Left Sidebar (Memoria Brand Header + Album Card + Scene Cards + Photo Add CTA)
    private var sidebarView: some View {
        VStack(spacing: 14) {
            // 1. Memoria Brand Header
            HStack(spacing: 12) {
                MemoriaLogoMark(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memoria")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(MemoriaPalette.ink)
                    Text("소중한 순간을, 더 특별하게.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MemoriaPalette.subInk)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            if let manifest = store.manifest {
                // 2. Active Album Summary Card
                HStack(spacing: 12) {
                    coverThumbnail(size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(manifest.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MemoriaPalette.ink)
                            .lineLimit(1)
                        Text("\(manifest.sceneCount)개 장면 · \(ExhibitionThemePreset(rawValue: manifest.themePreset)?.displayName ?? "메모리아")")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MemoriaPalette.subInk)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(MemoriaPalette.subInk.opacity(0.6))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color(red: 0.35, green: 0.42, blue: 0.62).opacity(0.08), radius: 14, y: 4)
                )
                .padding(.horizontal, 14)

                // 3. Scene Cards List
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(manifest.scenes.enumerated()), id: \.element.id) { idx, scene in
                            let isSelected = (store.selectedScene?.id == scene.id)
                            Button {
                                store.selectScene(scene.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(String(format: "%02d", idx + 1))
                                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                                        .foregroundStyle(isSelected ? Color.white : MemoriaPalette.purple)
                                        .frame(width: 26, height: 26)
                                        .background(
                                            Circle().fill(
                                                isSelected
                                                    ? AnyShapeStyle(MemoriaPalette.skyLavenderPill)
                                                    : AnyShapeStyle(MemoriaPalette.softLavender)
                                            )
                                        )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(scene.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(MemoriaPalette.ink)
                                            .lineLimit(1)
                                        HStack(spacing: 5) {
                                            Text(koreanKindLabel(scene.kind))
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(MemoriaPalette.subInk)
                                            if scene.hasAudio {
                                                Image(systemName: "music.note")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(MemoriaPalette.coralPink)
                                            }
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(isSelected ? Color.white : Color.white.opacity(0.55))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .strokeBorder(
                                                    isSelected ? MemoriaPalette.purple.opacity(0.45) : Color.clear,
                                                    lineWidth: 1.5
                                                )
                                        )
                                        .shadow(color: .black.opacity(isSelected ? 0.06 : 0), radius: 8, y: 3)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }

                // 4. Clean Photo Add Pill CTA (Typography-first, no mascot)
                PhotosPicker(selection: $pickedPhotoItem, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("사진 추가하기")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(MemoriaPalette.skyLavenderPill))
                    .shadow(color: MemoriaPalette.purple.opacity(0.24), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
            }

            // Status footer
            HStack(spacing: 6) {
                Circle()
                    .fill(store.errorMessage == nil ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(store.errorMessage ?? store.statusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(store.errorMessage == nil ? MemoriaPalette.subInk : .red)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(MemoriaPalette.canvas)
        .navigationSplitViewColumnWidth(min: 256, ideal: 280, max: 320)
    }

    // MARK: - Center Stage (Mobile Exhibition Phone Preview OR "우리의 갤러리" 2-Column Grid)
    private var centerStageView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.96, blue: 1.00),
                    Color(red: 0.97, green: 0.96, blue: 1.00),
                    Color.white,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if stageTab == .galleryGrid {
                ourGalleryGridStage
            } else if store.previewHTMLURL != nil {
                #if os(macOS)
                ExhibitionWebView(
                    htmlURL: store.previewHTMLURL,
                    readAccessURL: store.previewDirectoryURL,
                    revision: store.previewRevision,
                    controller: webController
                )
                .frame(width: 393, height: 748)
                .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 48, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color(red: 0.32, green: 0.38, blue: 0.58).opacity(0.18), radius: 34, y: 16)
                )
                .padding(18)
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
        }
    }

    // Screen 4 of reference: "우리의 갤러리" (전체 / 사진 / 영상 pills + 2-column rounded photo grid + camera FAB)
    private var ourGalleryGridStage: some View {
        let images = collectProjectImages()
        return ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 16) {
                HStack {
                    Text("우리의 갤러리")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(MemoriaPalette.ink)
                    Spacer()
                    Text("공유된 사진 \(images.count)장")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MemoriaPalette.purple)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(MemoriaPalette.softLavender))
                }

                HStack(spacing: 8) {
                    ForEach(["전체", "사진", "하이라이트"], id: \.self) { chip in
                        Text(chip)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(chip == "전체" ? MemoriaPalette.ink : MemoriaPalette.subInk)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(chip == "전체" ? Color.white : MemoriaPalette.softSky.opacity(0.7))
                                    .shadow(color: .black.opacity(chip == "전체" ? 0.06 : 0), radius: 6, y: 2)
                            )
                    }
                    Spacer()
                }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(images, id: \.path) { url in
                            GeometryReader { geo in
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: geo.size.width, height: 184)
                                            .clipped()
                                    default:
                                        MemoriaPalette.softSky
                                    }
                                }
                            }
                            .frame(height: 184)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
            .background(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color(red: 0.32, green: 0.38, blue: 0.58).opacity(0.14), radius: 28, y: 12)
            )
            .padding(24)

            PhotosPicker(selection: $pickedPhotoItem, matching: .images) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(MemoriaPalette.skyLavenderPill))
                    .shadow(color: MemoriaPalette.purple.opacity(0.38), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
            .padding(44)
        }
    }

    // MARK: - Right Inspector (Memoria Rounded Pastel Settings Cards)
    private var inspectorView: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let manifest = store.manifest {
                    // 1. Pastel Dot Theme Switcher ("배경 테마 변경 🟡🟠🩷🟣🔵")
                    MemoriaCard(title: "배경 테마 변경", icon: "paintpalette.fill") {
                        HStack(spacing: 10) {
                            ForEach(ExhibitionThemePreset.allCases) { preset in
                                let isCurrent = (manifest.themePreset == preset.rawValue)
                                Button {
                                    store.updateTheme(preset)
                                } label: {
                                    Circle()
                                        .fill(pastelDotColor(for: preset))
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white, lineWidth: isCurrent ? 3 : 0)
                                        )
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    isCurrent ? MemoriaPalette.purple : Color.black.opacity(0.08),
                                                    lineWidth: isCurrent ? 2 : 1
                                                )
                                        )
                                        .scaleEffect(isCurrent ? 1.12 : 1.0)
                                }
                                .buttonStyle(.plain)
                                .help(preset.displayName)
                            }
                            Spacer()
                        }

                        if let activePreset = ExhibitionThemePreset(rawValue: manifest.themePreset) {
                            HStack {
                                Text(activePreset.displayName)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(MemoriaPalette.purple)
                                Text("· \(activePreset.subtitle)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(MemoriaPalette.subInk)
                            }
                        }
                    }
                }

                if let scene = store.selectedScene {
                    // 2. Live Text & Caption Card
                    MemoriaCard(title: "문구 · 캡션 꾸미기", icon: "pencil.and.scribble") {
                        MemoriaTextField(label: "상단 뱃지 / 챕터", text: $editChapter)
                            .onChange(of: editChapter) { _, _ in scheduleLiveTextPatch(sceneID: scene.id) }
                        MemoriaTextField(label: "메인 타이틀", text: $editTitle)
                            .onChange(of: editTitle) { _, _ in scheduleLiveTextPatch(sceneID: scene.id) }
                        MemoriaTextField(label: "초대 문구 / 설명", text: $editNote, multiline: true)
                            .onChange(of: editNote) { _, _ in scheduleLiveTextPatch(sceneID: scene.id) }
                        MemoriaTextField(label: "날짜 / 포인트 캡션", text: $editCaption)
                            .onChange(of: editCaption) { _, _ in scheduleLiveTextPatch(sceneID: scene.id) }
                    }

                    // 3. Individual Gallery Items (when HorizontalTrack / PinnedStory selected)
                    if !scene.items.isEmpty {
                        MemoriaCard(title: "개별 사진 캡션 (\(scene.items.count)장)", icon: "photo.stack.fill") {
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

                    // 4. Lighting & Sound Card
                    MemoriaCard(title: "장면 분위기 · 배경음악", icon: "sparkles") {
                        HStack(spacing: 6) {
                            ForEach(LightingPreset.allCases) { preset in
                                let active = (scene.mood == preset.rawValue)
                                Button {
                                    store.updateMood(sceneID: scene.id, preset: preset)
                                } label: {
                                    Text(shortMoodName(preset))
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule().fill(
                                                active ? MemoriaPalette.softLavender : MemoriaPalette.canvas
                                            )
                                        )
                                        .foregroundStyle(active ? MemoriaPalette.purple : MemoriaPalette.subInk)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Divider()

                        HStack {
                            Image(systemName: "music.quarternote.3")
                                .foregroundStyle(MemoriaPalette.coralPink)
                            Text(scene.audioTrack.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "배경음악 없음")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(MemoriaPalette.ink)
                                .lineLimit(1)
                            Spacer()
                            #if os(macOS)
                            Button("변경") {
                                pickAudioForScene(sceneID: scene.id)
                            }
                            .font(.system(size: 11, weight: .bold))
                            #endif
                        }
                    }

                    // 5. Sunset Gradient Primary Share CTA ("갤러리 공유하기 ›")
                    Button {
                        showMemoriaShareModal = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("우리의 갤러리 공유하기")
                                .font(.system(size: 14, weight: .bold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(MemoriaPalette.sunsetPill))
                        .shadow(color: MemoriaPalette.coralPink.opacity(0.32), radius: 14, y: 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(MemoriaPalette.canvas)
    }

    // MARK: - Memoria Custom Share Modal (Screen 8 of Reference)
    private var memoriaShareCardModal: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    coverThumbnail(size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.manifest?.title ?? "우리의 앨범")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(MemoriaPalette.ink)
                        Text("Memoria · 소중한 순간")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MemoriaPalette.subInk)
                    }
                    Spacer()
                    Button {
                        showMemoriaShareModal = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(MemoriaPalette.subInk)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(MemoriaPalette.canvas))
                    }
                    .buttonStyle(.plain)
                }

                // 4 Circular Share Icons (AirDrop / 메시지 / 카카오톡 / iCloud 저장)
                HStack(spacing: 22) {
                    shareIconButton(
                        title: "AirDrop",
                        icon: "wifi",
                        bg: Color(red: 0.92, green: 0.96, blue: 1.0),
                        fg: Color(red: 0.12, green: 0.53, blue: 1.0)
                    ) {
                        triggerPrimaryExport(singleFile: true)
                    }
                    shareIconButton(
                        title: "메시지",
                        icon: "message.fill",
                        bg: Color(red: 0.22, green: 0.84, blue: 0.38),
                        fg: .white
                    ) {
                        triggerPrimaryExport(singleFile: true)
                    }
                    shareIconButton(
                        title: "카카오톡",
                        icon: "bubble.left.fill",
                        bg: Color(red: 0.99, green: 0.89, blue: 0.0),
                        fg: Color(red: 0.22, green: 0.14, blue: 0.14)
                    ) {
                        triggerPrimaryExport(singleFile: true)
                    }
                    shareIconButton(
                        title: "iCloud",
                        icon: "icloud.and.arrow.up.fill",
                        bg: Color(red: 0.93, green: 0.91, blue: 1.0),
                        fg: MemoriaPalette.purple
                    ) {
                        store.saveToCloudPackage()
                        showMemoriaShareModal = false
                    }
                }
                .padding(.vertical, 4)

                VStack(spacing: 8) {
                    Button {
                        triggerPrimaryExport(singleFile: true)
                    } label: {
                        HStack {
                            Image(systemName: "link")
                            Text("단일 HTML 초대장 내보내기 (추천)")
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                        }
                        .foregroundStyle(MemoriaPalette.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MemoriaPalette.canvas))
                    }
                    .buttonStyle(.plain)

                    #if os(macOS)
                    Button {
                        triggerPrimaryExport(singleFile: false)
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text("웹 호스팅용 폴더 내보내기")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(MemoriaPalette.subInk)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MemoriaPalette.canvas))
                    }
                    .buttonStyle(.plain)
                    #else
                    if let shareURL = exportedShareURL {
                        ShareLink(item: shareURL) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("생성된 초대장 바로 보내기")
                                    .font(.system(size: 13, weight: .bold))
                                Spacer()
                            }
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MemoriaPalette.skyLavenderPill))
                        }
                    }
                    #endif
                }
            }
            .padding(22)
        }
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.22), radius: 32, y: 14)
        )
    }

    // MARK: - Helpers
    private func shareIconButton(title: String, icon: String, bg: Color, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(fg)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(bg))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MemoriaPalette.subInk)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func coverThumbnail(size: CGFloat) -> some View {
        if let firstURL = collectProjectImages().first {
            AsyncImage(url: firstURL) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    MemoriaLogoMark(size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            MemoriaLogoMark(size: size)
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

    private func pastelDotColor(for preset: ExhibitionThemePreset) -> Color {
        switch preset {
        case .memoriaPastel: return Color(red: 0.36, green: 0.70, blue: 1.00)
        case .tossClean: return Color(red: 0.22, green: 0.52, blue: 0.96)
        case .editorialGallery: return Color(red: 0.72, green: 0.84, blue: 0.98)
        case .atelierPoster: return Color(red: 0.54, green: 0.66, blue: 0.82)
        case .midnightFilm: return Color(red: 0.16, green: 0.22, blue: 0.32)
        }
    }

    private func shortMoodName(_ preset: LightingPreset) -> String {
        switch preset {
        case .warmPaper: return "밝은 낮"
        case .softDim: return "오후 노을"
        case .darkRoom: return "저녁 무드"
        case .obsidian: return "깊은 밤"
        }
    }

    private func koreanKindLabel(_ kind: String) -> String {
        switch kind {
        case "cover": return "표지 커버"
        case "spotlight": return "단독 포커스"
        case "horizontal_track": return "가로 스냅 갤러리"
        case "pinned_story": return "스토리 카드"
        case "video_moment": return "영상 장면"
        case "ending": return "마무리 인사"
        default: return kind
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

    private func triggerPrimaryExport(singleFile: Bool) {
        #if os(macOS)
        showMemoriaShareModal = false
        exportHTMLPackage(singleFile: singleFile)
        #else
        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("memoria-share", isDirectory: true)
        if let result = store.exportToFolder(outDir, singleFile: true) {
            exportedShareURL = URL(fileURLWithPath: result.outputHtml)
        }
        #endif
    }

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
                    .foregroundStyle(MemoriaPalette.purple)
                if let src = item.mediaSrc {
                    Text(URL(fileURLWithPath: src).lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(MemoriaPalette.subInk)
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
            TextField("사진 캡션", text: $captionText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MemoriaPalette.canvas))
                .onSubmit {
                    onSave(titleText, captionText)
                }
        }
        .padding(.vertical, 2)
    }
}
