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

enum GalleryGridFilter: String, CaseIterable, Identifiable {
    case all = "전체"
    case featured = "대표 장면"
    case album = "앨범 사진"
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var store = GalleryStore()
    @State private var webController = WebPreviewController()
    @State private var stageTab: CenterStageTab = .preview
    @State private var galleryFilter: GalleryGridFilter = .all
    @State private var showInspector = true
    @State private var showMobileEditorSheet = false
    @State private var showMemoriaShareModal = false
    @State private var showNewExhibitionSheet = false
    @State private var exportedShareURL: URL?
    @State private var isExporting = false
    @State private var isImportingPhotos = false
    @State private var pickedPhotoItems: [PhotosPickerItem] = []

    // New Exhibition modal state
    @State private var newExhibitionTitle = ""
    @State private var newExhibitionSubtitle = ""
    @State private var newExhibitionPhotoItems: [PhotosPickerItem] = []

    // Toast & Haptic feedback state
    @State private var toastMessage: String?
    @State private var isToastError = false
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var hapticTick = 0

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

                // Floating Toast & Loading Banner
                VStack {
                    if isImportingPhotos || isExporting {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(isImportingPhotos ? "사진을 전시에 담는 중…" : "초대장 파일을 준비하는 중…")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MemoriaPalette.ink)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                        )
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else if let toast = toastMessage {
                        HStack(spacing: 8) {
                            Image(systemName: isToastError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(isToastError ? Color.red : MemoriaPalette.purple)
                            Text(toast)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MemoriaPalette.ink)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.white)
                                .overlay(
                                    Capsule().strokeBorder(
                                        (isToastError ? Color.red : MemoriaPalette.purple).opacity(0.2),
                                        lineWidth: 1
                                    )
                                )
                                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                        )
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.84), value: showMemoriaShareModal)
            .animation(.spring(response: 0.30, dampingFraction: 0.86), value: toastMessage)
            .animation(.easeInOut(duration: 0.2), value: isImportingPhotos)
            .animation(.easeInOut(duration: 0.2), value: isExporting)
        }
        .sensoryFeedback(.selection, trigger: hapticTick)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    showNewExhibitionSheet = true
                } label: {
                    Label("새 전시", systemImage: "plus.rectangle.on.folder")
                }

                Menu {
                    Section("샘플 전시 둘러보기") {
                        Button {
                            openDemoPackage(named: "Our_Wedding_2027")
                            showToast("청첩장 샘플을 열었어요")
                        } label: {
                            Label("청첩장 샘플", systemImage: "heart.fill")
                        }
                        Button {
                            openDemoPackage(named: "Rainy_Fukuoka")
                            showToast("여행전 샘플을 열었어요")
                        } label: {
                            Label("여행전 샘플", systemImage: "airplane")
                        }
                    }
                    if !store.savedPackages.isEmpty {
                        Section("내 저장된 전시") {
                            ForEach(store.savedPackages) { pkg in
                                Button {
                                    store.loadPackage(at: pkg.url)
                                    showToast("'\(pkg.name)' 전시를 열었어요")
                                } label: {
                                    Label(pkg.name, systemImage: "photo.on.rectangle.angled")
                                }
                            }
                        }
                    }
                    #if os(macOS)
                    Divider()
                    Button {
                        pickFolderToScan()
                    } label: {
                        Label("Mac 폴더에서 바로 만들기…", systemImage: "folder.badge.plus")
                    }
                    #endif
                } label: {
                    Label("전시 전환", systemImage: "rectangle.stack")
                }
            }

            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    ForEach(CenterStageTab.allCases) { tab in
                        Button {
                            stageTab = tab
                            hapticTick += 1
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
                if horizontalSizeClass != .compact {
                    Button {
                        store.undo()
                        showToast("실행 취소했어요")
                    } label: {
                        Label("실행 취소", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!store.canUndo)
                    .keyboardShortcut("z", modifiers: [.command])

                    Button {
                        store.redo()
                        showToast("다시 실행했어요")
                    } label: {
                        Label("다시 실행", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(!store.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                }

                Button {
                    openShareModal()
                } label: {
                    Label("공유하기", systemImage: "square.and.arrow.up")
                }
                .disabled(store.manifest == nil)

                Button {
                    hapticTick += 1
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
                        ToolbarItem(placement: .cancellationAction) {
                            HStack(spacing: 12) {
                                Button {
                                    store.undo()
                                    showToast("실행 취소했어요")
                                } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                }
                                .disabled(!store.canUndo)

                                Button {
                                    store.redo()
                                    showToast("다시 실행했어요")
                                } label: {
                                    Image(systemName: "arrow.uturn.forward")
                                }
                                .disabled(!store.canRedo)
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("완료") { showMobileEditorSheet = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: $showNewExhibitionSheet) {
            newExhibitionModalSheet
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
                openShareModal()
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
        .onChange(of: pickedPhotoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            let itemsToLoad = newItems
            pickedPhotoItems = []
            Task {
                await loadAndImportPhotos(itemsToLoad)
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
                // 2. Active Album Summary Card (Interactive Switcher Menu)
                Menu {
                    Button {
                        showNewExhibitionSheet = true
                    } label: {
                        Label("새 전시 만들기", systemImage: "plus.circle.fill")
                    }
                    Divider()
                    Section("샘플 전시") {
                        Button("청첩장 샘플") {
                            openDemoPackage(named: "Our_Wedding_2027")
                            showToast("청첩장 샘플을 열었어요")
                        }
                        Button("여행전 샘플") {
                            openDemoPackage(named: "Rainy_Fukuoka")
                            showToast("여행전 샘플을 열었어요")
                        }
                    }
                    if !store.savedPackages.isEmpty {
                        Section("저장된 내 전시") {
                            ForEach(store.savedPackages) { pkg in
                                Button(pkg.name) {
                                    store.loadPackage(at: pkg.url)
                                    showToast("'\(pkg.name)' 전시를 열었어요")
                                }
                            }
                        }
                    }
                } label: {
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
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(MemoriaPalette.subInk.opacity(0.6))
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: Color(red: 0.35, green: 0.42, blue: 0.62).opacity(0.08), radius: 14, y: 4)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)

                // 3. Scene Cards List
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(manifest.scenes.enumerated()), id: \.element.id) { idx, scene in
                            let isSelected = (store.selectedScene?.id == scene.id)
                            Button {
                                store.selectScene(scene.id)
                                hapticTick += 1
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
                            .contextMenu {
                                if manifest.scenes.count > 2 && scene.kind != "cover" && scene.kind != "ending" {
                                    Button(role: .destructive) {
                                        store.removeScene(sceneID: scene.id)
                                        showToast("장면을 삭제했어요")
                                    } label: {
                                        Label("이 장면 삭제", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }

                // 4. Multi-Photo Add CTA + New Exhibition Button
                VStack(spacing: 8) {
                    PhotosPicker(
                        selection: $pickedPhotoItems,
                        maxSelectionCount: 30,
                        matching: .images
                    ) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 13, weight: .bold))
                            Text("사진 여러 장 추가")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(MemoriaPalette.skyLavenderPill))
                        .shadow(color: MemoriaPalette.purple.opacity(0.24), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showNewExhibitionSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("새 전시 만들기")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(MemoriaPalette.purple)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(Color.white)
                                .overlay(Capsule().strokeBorder(MemoriaPalette.purple.opacity(0.25), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }
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

    // Screen 4 of reference: "우리의 갤러리" (interactive filter chips + 2-column rounded photo grid + multi-photo FAB)
    private var ourGalleryGridStage: some View {
        let images = filteredProjectImages()
        return ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 16) {
                HStack {
                    Text("우리의 갤러리")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(MemoriaPalette.ink)
                    Spacer()
                    Text("사진 \(images.count)장")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MemoriaPalette.purple)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(MemoriaPalette.softLavender))
                }

                HStack(spacing: 8) {
                    ForEach(GalleryGridFilter.allCases) { chip in
                        let isActive = (galleryFilter == chip)
                        Button {
                            galleryFilter = chip
                            hapticTick += 1
                        } label: {
                            Text(chip.rawValue)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(isActive ? MemoriaPalette.ink : MemoriaPalette.subInk)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(isActive ? Color.white : MemoriaPalette.softSky.opacity(0.7))
                                        .shadow(color: .black.opacity(isActive ? 0.06 : 0), radius: 6, y: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }

                if images.isEmpty {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 32))
                            .foregroundStyle(MemoriaPalette.purple.opacity(0.5))
                        Text("해당 카테고리에 사진이 없어요")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MemoriaPalette.subInk)
                        Spacer()
                    }
                } else {
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
            }
            .padding(24)
            .frame(maxWidth: 560)
            .background(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color(red: 0.32, green: 0.38, blue: 0.58).opacity(0.14), radius: 28, y: 12)
            )
            .padding(24)

            PhotosPicker(
                selection: $pickedPhotoItems,
                maxSelectionCount: 30,
                matching: .images
            ) {
                Image(systemName: "photo.badge.plus")
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
                                    hapticTick += 1
                                    showToast("'\(preset.displayName)' 테마 적용됨")
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
                                    hapticTick += 1
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

                    // 5. Primary Share CTA ("갤러리 공유하기 ›")
                    Button {
                        showMobileEditorSheet = false
                        openShareModal()
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

    // MARK: - Memoria Native Share & Export Modal (Honest 1-Tap ShareLink on iOS, Direct Save on macOS)
    private var memoriaShareCardModal: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                coverThumbnail(size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.manifest?.title ?? "우리의 앨범")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(MemoriaPalette.ink)
                        .lineLimit(1)
                    Text("Memoria · 오프라인 초대장 공유")
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

            VStack(spacing: 10) {
                #if os(macOS)
                Button {
                    triggerPrimaryExport(singleFile: true)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("오프라인 초대장 파일 저장 (.html)")
                                .font(.system(size: 13, weight: .bold))
                            Text("인터넷 없이 Safari에서 바로 열리는 단일 파일")
                                .font(.system(size: 11))
                                .opacity(0.88)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MemoriaPalette.skyLavenderPill))
                }
                .buttonStyle(.plain)

                Button {
                    triggerPrimaryExport(singleFile: false)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(MemoriaPalette.purple)
                        Text("웹 게시용 폴더로 저장")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(MemoriaPalette.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MemoriaPalette.canvas))
                }
                .buttonStyle(.plain)
                #else
                if isExporting {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("초대장 파일 준비 중…")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MemoriaPalette.skyLavenderPill.opacity(0.75)))
                } else if let shareURL = exportedShareURL {
                    ShareLink(
                        item: shareURL,
                        subject: Text(store.manifest?.title ?? "Memoria 전시 초대장"),
                        message: Text("Memoria로 만든 디지털 전시관을 열어보세요.")
                    ) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .bold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("초대장 바로 공유하기")
                                    .font(.system(size: 14, weight: .bold))
                                Text("AirDrop · 메시지 · 카카오톡 · 파일")
                                    .font(.system(size: 11))
                                    .opacity(0.9)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MemoriaPalette.skyLavenderPill))
                    }
                } else {
                    Button {
                        prepareShareFileForIOS()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("초대장 파일 다시 준비하기")
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MemoriaPalette.skyLavenderPill))
                    }
                    .buttonStyle(.plain)
                }
                #endif

                Button {
                    store.saveToCloudPackage()
                    showMemoriaShareModal = false
                    hapticTick += 1
                    showToast(store.errorMessage ?? "전시 프로젝트를 저장했어요", isError: store.errorMessage != nil)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "icloud.and.arrow.up.fill")
                            .foregroundStyle(MemoriaPalette.purple)
                        Text(store.isICloudAvailable ? "iCloud Drive에 프로젝트 저장" : "내 기기에 프로젝트 저장 (.gallery)")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(MemoriaPalette.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MemoriaPalette.canvas))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(width: 344)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.22), radius: 32, y: 14)
        )
    }

    // MARK: - New Exhibition Creation Sheet (Onboarding for Own Photos)
    private var newExhibitionModalSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("나만의 전시 만들기")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(MemoriaPalette.ink)
                        Text("사진을 여러 장 고르면 촬영 순서와 비율에 맞춰 전시를 자동으로 구성해 드려요.")
                            .font(.system(size: 13))
                            .foregroundStyle(MemoriaPalette.subInk)
                    }

                    MemoriaCard(title: "전시 정보", icon: "text.alignleft") {
                        MemoriaTextField(label: "전시 제목 (예: 제주도 여름 기록, 우리의 결혼식)", text: $newExhibitionTitle)
                        MemoriaTextField(label: "한 줄 부제 (선택)", text: $newExhibitionSubtitle)
                    }

                    MemoriaCard(title: "전시에 담을 사진 (최대 30장)", icon: "photo.on.rectangle.angled") {
                        PhotosPicker(
                            selection: $newExhibitionPhotoItems,
                            maxSelectionCount: 30,
                            matching: .images
                        ) {
                            HStack(spacing: 10) {
                                Image(systemName: newExhibitionPhotoItems.isEmpty ? "photo.badge.plus" : "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                Text(
                                    newExhibitionPhotoItems.isEmpty
                                        ? "사진 보관함에서 여러 장 고르기"
                                        : "\(newExhibitionPhotoItems.count)장 선택됨 · 다시 고르기"
                                )
                                .font(.system(size: 13, weight: .bold))
                                Spacer()
                            }
                            .foregroundStyle(MemoriaPalette.purple)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(MemoriaPalette.softLavender)
                            )
                        }
                        .buttonStyle(.plain)

                        #if os(macOS)
                        Button {
                            showNewExhibitionSheet = false
                            pickFolderToScan()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.badge.plus")
                                Text("또는 Mac 사진 폴더에서 바로 만들기…")
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                            }
                            .foregroundStyle(MemoriaPalette.subInk)
                            .padding(.top, 4)
                        }
                        .buttonStyle(.plain)
                        #endif
                    }

                    Button {
                        let items = newExhibitionPhotoItems
                        let title = newExhibitionTitle
                        let subtitle = newExhibitionSubtitle
                        showNewExhibitionSheet = false
                        newExhibitionPhotoItems = []
                        newExhibitionTitle = ""
                        newExhibitionSubtitle = ""
                        Task {
                            await createExhibitionFromPickedPhotos(title: title, subtitle: subtitle, items: items)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text(newExhibitionPhotoItems.isEmpty ? "사진을 1장 이상 선택해 주세요" : "\(newExhibitionPhotoItems.count)장으로 전시 시작하기")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().fill(
                                newExhibitionPhotoItems.isEmpty
                                    ? AnyShapeStyle(Color.gray.opacity(0.35))
                                    : AnyShapeStyle(MemoriaPalette.skyLavenderPill)
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(newExhibitionPhotoItems.isEmpty)
                }
                .padding(20)
            }
            .background(MemoriaPalette.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { showNewExhibitionSheet = false }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 460)
        #endif
    }

    // MARK: - Helpers
    private func showToast(_ message: String, isError: Bool = false) {
        toastDismissTask?.cancel()
        isToastError = isError
        toastMessage = message
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            toastMessage = nil
        }
    }

    private func openShareModal() {
        hapticTick += 1
        showMemoriaShareModal = true
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
                showToast(store.errorMessage ?? "초대장 파일 준비에 실패했어요", isError: true)
            }
        }
    }
    #endif

    private func loadAndImportPhotos(_ items: [PhotosPickerItem]) async {
        isImportingPhotos = true
        var loaded: [(Data, String)] = []
        let stamp = Int(Date().timeIntervalSince1970)
        for (idx, item) in items.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append((data, "photo_\(stamp)_\(idx + 1).jpg"))
            }
        }
        let added = store.importMultiplePhotoData(loaded)
        isImportingPhotos = false
        hapticTick += 1
        if added > 0 {
            showToast("사진 \(added)장을 전시에 추가했어요")
        } else {
            showToast(store.errorMessage ?? "사진을 불러오지 못했어요", isError: true)
        }
    }

    private func createExhibitionFromPickedPhotos(
        title: String,
        subtitle: String,
        items: [PhotosPickerItem]
    ) async {
        isImportingPhotos = true
        var loaded: [(Data, String)] = []
        let stamp = Int(Date().timeIntervalSince1970)
        for (idx, item) in items.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append((data, "photo_\(stamp)_\(idx + 1).jpg"))
            }
        }
        let ok = store.createNewExhibition(title: title, subtitle: subtitle, photos: loaded)
        isImportingPhotos = false
        hapticTick += 1
        if ok {
            stageTab = .preview
            showToast("새 전시를 만들었어요 (\(loaded.count)장)")
        } else {
            showToast(store.errorMessage ?? "새 전시 생성에 실패했어요", isError: true)
        }
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

    private func filteredProjectImages() -> [URL] {
        let all = collectProjectImages()
        guard let manifest = store.manifest, galleryFilter != .all else { return all }
        switch galleryFilter {
        case .all:
            return all
        case .featured:
            let featuredNames = Set(
                manifest.scenes
                    .filter { $0.kind == "cover" || $0.kind == "spotlight" }
                    .flatMap { scene in
                        scene.items.compactMap { $0.mediaSrc.map { URL(fileURLWithPath: $0).lastPathComponent } }
                    }
            )
            let matched = all.filter { featuredNames.contains($0.lastPathComponent) }
            return matched.isEmpty ? Array(all.prefix(2)) : matched
        case .album:
            let albumNames = Set(
                manifest.scenes
                    .filter { $0.kind == "horizontal_track" || $0.kind == "pinned_story" }
                    .flatMap { scene in
                        scene.items.compactMap { $0.mediaSrc.map { URL(fileURLWithPath: $0).lastPathComponent } }
                    }
            )
            return all.filter { albumNames.contains($0.lastPathComponent) }
        }
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
        case "cover": return "표지"
        case "spotlight": return "큰 사진 한 장"
        case "horizontal_track": return "옆으로 넘기는 앨범"
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
            showToast(store.errorMessage ?? "폴더에서 전시를 구성했어요", isError: store.errorMessage != nil)
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
            isExporting = true
            let result = store.exportToFolder(url, singleFile: singleFile)
            isExporting = false
            if let result {
                showToast(singleFile ? "오프라인 초대장(.html) 저장 완료" : "웹 게시용 폴더 저장 완료")
                NSWorkspace.shared.open(URL(fileURLWithPath: result.outputHtml))
            } else {
                showToast(store.errorMessage ?? "저장에 실패했어요", isError: true)
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
