import Foundation
import Observation

/// Lighting mood presets mirrored from `gallery-core`.
public enum LightingPreset: String, CaseIterable, Identifiable, Sendable {
    case warmPaper = "warm_paper"
    case softDim = "soft_dim"
    case darkRoom = "dark_room"
    case obsidian = "obsidian"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .warmPaper: return "Warm Paper"
        case .softDim: return "Soft Dim"
        case .darkRoom: return "Dark Room"
        case .obsidian: return "Obsidian"
        }
    }
}

/// Exhibition design theme presets.
public enum ExhibitionThemePreset: String, CaseIterable, Identifiable, Sendable {
    case memoriaPastel = "memoria_pastel"
    case tossClean = "toss_clean"
    case editorialGallery = "editorial_gallery"
    case atelierPoster = "atelier_poster"
    case midnightFilm = "midnight_film"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .memoriaPastel: return "메모리아 파스텔"
        case .tossClean: return "토스 미니멀"
        case .editorialGallery: return "에디토리얼 매거진"
        case .atelierPoster: return "아틀리에 포스터"
        case .midnightFilm: return "미드나잇 필름"
        }
    }

    public var subtitle: String {
        switch self {
        case .memoriaPastel: return "구름 마스코트 · 파스텔 웨딩/추억"
        case .tossClean: return "심플 카드 · 스카이 블루"
        case .editorialGallery: return "화보 매거진 · 세리프"
        case .atelierPoster: return "전시 포스터 · 클래식"
        case .midnightFilm: return "다크룸 필름 · 앰버"
        }
    }
}

/// Callback hooks for zero-reload live DOM patching in `WKWebView`.
public struct LivePatchCallbacks {
    public var onScrollToScene: ((String) -> Void)?
    public var onPatchAtmosphere: ((String, FfiPalette) -> Void)?
    public var onPatchText: ((String, String, String, String, String) -> Void)?
    public var onPatchItem: ((String, UInt32, String?, String?) -> Void)?
    public var onPatchTheme: ((String) -> Void)?

    public init() {}
}

/// Observable SwiftUI state store backed directly by the Rust Core via UniFFI,
/// with full Undo/Redo history and zero-reload WKWebView live patching.
@MainActor
@Observable
public final class GalleryStore {
    public var manifest: FfiManifestSummary?
    public var sourceRootURL: URL?
    public var selectedSceneID: String?
    public var previewHTMLURL: URL?
    public var previewDirectoryURL: URL?
    public var previewRevision: Int = 0
    public var savedPackages: [ICloudPackageService.PackageLocation] = []
    public var isICloudAvailable: Bool = false
    public var statusMessage: String = "사진 보관함이나 폴더에서 전시관을 시작하세요."
    public var errorMessage: String?

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public var liveCallbacks = LivePatchCallbacks()

    private var undoStack: [String] = []
    private var redoStack: [String] = []
    private let cloudService = ICloudPackageService()

    public init() {
        refreshCloudPackages()
    }

    public var selectedScene: FfiSceneSummary? {
        guard let id = selectedSceneID else { return manifest?.scenes.first }
        return manifest?.scenes.first(where: { $0.id == id })
    }

    public func refreshCloudPackages() {
        let (_, isICloud) = cloudService.resolvePackagesRoot()
        self.isICloudAvailable = isICloud
        self.savedPackages = cloudService.listPackages()
    }

    public func selectScene(_ sceneID: String?) {
        self.selectedSceneID = sceneID
        if let sceneID {
            liveCallbacks.onScrollToScene?(sceneID)
        }
    }

    // MARK: - Undo / Redo
    private func pushUndoSnapshot() {
        guard let raw = manifest?.rawJson else { return }
        if undoStack.last != raw {
            undoStack.append(raw)
            if undoStack.count > 40 {
                undoStack.removeFirst()
            }
        }
        redoStack.removeAll()
    }

    public func undo() {
        guard let previousJSON = undoStack.popLast(), let current = manifest else { return }
        redoStack.append(current.rawJson)
        do {
            let restored = try parseManifestJson(json: previousJSON)
            self.manifest = restored
            if !restored.scenes.contains(where: { $0.id == selectedSceneID }) {
                self.selectedSceneID = restored.scenes.first?.id
            }
            self.statusMessage = "실행 취소됨"
            refreshLivePreview()
        } catch {
            self.errorMessage = "실행 취소 실패: \(error.localizedDescription)"
        }
    }

    public func redo() {
        guard let nextJSON = redoStack.popLast(), let current = manifest else { return }
        undoStack.append(current.rawJson)
        do {
            let restored = try parseManifestJson(json: nextJSON)
            self.manifest = restored
            if !restored.scenes.contains(where: { $0.id == selectedSceneID }) {
                self.selectedSceneID = restored.scenes.first?.id
            }
            self.statusMessage = "다시 실행됨"
            refreshLivePreview()
        } catch {
            self.errorMessage = "다시 실행 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Loading & Scanning
    public func scanFolder(at folderURL: URL, title: String? = nil, gapHours: Int64 = 4) {
        clearError()
        let derivedTitle = title ?? folderURL.lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        do {
            let summary = try scanFolderToManifest(
                inputDir: folderURL.path,
                title: derivedTitle,
                subtitle: "Curated with Digital Gallery",
                gapHours: gapHours
            )
            undoStack.removeAll()
            redoStack.removeAll()
            self.manifest = summary
            self.sourceRootURL = folderURL
            self.selectedSceneID = summary.scenes.first?.id
            self.statusMessage = "\(summary.sceneCount)개 전시 씬 자동 구성 완료"
            refreshLivePreview()
        } catch {
            self.errorMessage = "폴더 스캔 실패: \(error.localizedDescription)"
        }
    }

    public func loadPackage(at url: URL) {
        clearError()
        do {
            let summary = try cloudService.loadPackage(at: url)
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            undoStack.removeAll()
            redoStack.removeAll()
            self.manifest = summary
            self.sourceRootURL = isDir ? url : url.deletingLastPathComponent()
            self.selectedSceneID = summary.scenes.first?.id
            self.statusMessage = "'\(summary.title)' 불러오기 완료 (\(summary.sceneCount) scenes)"
            refreshLivePreview()
        } catch {
            self.errorMessage = "패키지 로드 실패: \(error.localizedDescription)"
        }
    }

    public func saveToCloudPackage() {
        guard let current = manifest, let sourceRoot = sourceRootURL else {
            self.errorMessage = "저장할 전시관이 없습니다."
            return
        }
        clearError()
        do {
            let (root, isICloud) = cloudService.resolvePackagesRoot()
            let sanitized = current.title
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let packageName = (sanitized.isEmpty ? "Untitled" : sanitized) + ".gallery"
            let packageURL = root.appendingPathComponent(packageName, isDirectory: true)
            let savedURL = try cloudService.savePackage(
                manifestJSON: current.rawJson,
                sourceRoot: sourceRoot,
                packageURL: packageURL
            )
            self.sourceRootURL = savedURL
            refreshCloudPackages()
            let destLabel = isICloud ? "iCloud Drive" : "로컬 DigitalGallery 폴더"
            self.statusMessage = "\(packageName) 저장 완료 (\(destLabel))"
        } catch {
            self.errorMessage = ".gallery 저장 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Live Zero-Reload Editing
    public func updateTheme(_ preset: ExhibitionThemePreset) {
        guard let current = manifest else { return }
        clearError()
        pushUndoSnapshot()
        do {
            let updated = try updateThemePreset(json: current.rawJson, themePreset: preset.rawValue)
            self.manifest = updated
            self.statusMessage = "디자인 시안 변경: \(preset.displayName)"
            liveCallbacks.onPatchTheme?(preset.rawValue)
        } catch {
            self.errorMessage = "테마 변경 실패: \(error.localizedDescription)"
        }
    }

    public func updateMood(sceneID: String, preset: LightingPreset) {
        guard let current = manifest else { return }
        clearError()
        pushUndoSnapshot()
        do {
            let updated = try updateSceneMood(
                json: current.rawJson,
                sceneId: sceneID,
                moodPreset: preset.rawValue
            )
            self.manifest = updated
            self.statusMessage = "조명 변경: \(preset.displayName)"

            // Zero-reload live CSS variable patch in WKWebView
            if let palette = try? resolveMoodPalette(moodPreset: preset.rawValue) {
                liveCallbacks.onPatchAtmosphere?(sceneID, palette)
            }
        } catch {
            self.errorMessage = "조명 변경 실패: \(error.localizedDescription)"
        }
    }

    public func updateTextLive(
        sceneID: String,
        title: String,
        subtitleOrNote: String,
        caption: String,
        chapterLabel: String,
        recordUndo: Bool = false
    ) {
        guard let current = manifest else { return }
        clearError()
        if recordUndo {
            pushUndoSnapshot()
        }
        do {
            let updated = try updateSceneText(
                json: current.rawJson,
                sceneId: sceneID,
                title: title,
                subtitleOrNote: subtitleOrNote,
                caption: caption,
                chapterLabel: chapterLabel
            )
            self.manifest = updated
            self.statusMessage = "실시간 반영됨"
            liveCallbacks.onPatchText?(sceneID, title, chapterLabel, subtitleOrNote, caption)
        } catch {
            self.errorMessage = "텍스트 수정 실패: \(error.localizedDescription)"
        }
    }

    public func updateItemLive(
        sceneID: String,
        itemIndex: UInt32,
        title: String?,
        caption: String?
    ) {
        guard let current = manifest else { return }
        clearError()
        pushUndoSnapshot()
        do {
            let updated = try updateSceneItem(
                json: current.rawJson,
                sceneId: sceneID,
                itemIndex: itemIndex,
                title: title,
                caption: caption
            )
            self.manifest = updated
            self.statusMessage = "아이템 #\(itemIndex + 1) 수정 반영됨"
            liveCallbacks.onPatchItem?(sceneID, itemIndex, title, caption)
        } catch {
            self.errorMessage = "아이템 수정 실패: \(error.localizedDescription)"
        }
    }

    public func removeItem(sceneID: String, itemIndex: UInt32) {
        guard let current = manifest else { return }
        clearError()
        pushUndoSnapshot()
        do {
            let updated = try removeSceneItem(
                json: current.rawJson,
                sceneId: sceneID,
                itemIndex: itemIndex
            )
            self.manifest = updated
            self.statusMessage = "아이템 #\(itemIndex + 1) 삭제됨"
            refreshLivePreview()
        } catch {
            self.errorMessage = "아이템 삭제 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Media Import (Files & PhotosPicker)
    public func importPhotoDataAsSpotlight(data: Data, suggestedFilename: String) {
        guard let sourceRoot = sourceRootURL else {
            self.errorMessage = "먼저 전시관을 열거나 생성해 주세요."
            return
        }
        let fm = FileManager.default
        let imagesDir = sourceRoot.appendingPathComponent("images", isDirectory: true)
        do {
            try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            let destURL = imagesDir.appendingPathComponent(suggestedFilename)
            try data.write(to: destURL)
            importPhotoAsSpotlight(fileURL: destURL)
        } catch {
            self.errorMessage = "사진 보관함 가져오기 실패: \(error.localizedDescription)"
        }
    }

    public func importPhotoAsSpotlight(fileURL: URL) {
        guard let current = manifest, let sourceRoot = sourceRootURL else { return }
        clearError()
        pushUndoSnapshot()
        do {
            let relPath = try copyMediaIntoProject(fileURL: fileURL, subdir: "images", sourceRoot: sourceRoot)
            let title = fileURL.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            let updated = try addSpotlightScene(
                json: current.rawJson,
                imageRelPath: relPath,
                title: title,
                caption: nil,
                moodPreset: "dark_room"
            )
            self.manifest = updated
            if updated.scenes.count >= 2 {
                self.selectedSceneID = updated.scenes[updated.scenes.count - 2].id
            }
            self.statusMessage = "사진 씬 추가: \(fileURL.lastPathComponent)"
            refreshLivePreview()
        } catch {
            self.errorMessage = "사진 추가 실패: \(error.localizedDescription)"
        }
    }

    public func attachAudio(to sceneID: String, fileURL: URL) {
        guard let current = manifest, let sourceRoot = sourceRootURL else { return }
        clearError()
        pushUndoSnapshot()
        do {
            let relPath = try copyMediaIntoProject(fileURL: fileURL, subdir: "audio", sourceRoot: sourceRoot)
            let updated = try setSceneAudio(
                json: current.rawJson,
                sceneId: sceneID,
                audioTrack: relPath,
                volume: 0.5
            )
            self.manifest = updated
            self.statusMessage = "오디오 연결: \(fileURL.lastPathComponent)"
            refreshLivePreview()
        } catch {
            self.errorMessage = "오디오 추가 실패: \(error.localizedDescription)"
        }
    }

    public func clearAudio(from sceneID: String) {
        guard let current = manifest else { return }
        clearError()
        pushUndoSnapshot()
        do {
            let updated = try setSceneAudio(
                json: current.rawJson,
                sceneId: sceneID,
                audioTrack: nil,
                volume: 0.5
            )
            self.manifest = updated
            self.statusMessage = "오디오 큐 제거됨"
            refreshLivePreview()
        } catch {
            self.errorMessage = "오디오 제거 실패: \(error.localizedDescription)"
        }
    }

    public func removeScene(sceneID: String) {
        guard let current = manifest else { return }
        clearError()
        pushUndoSnapshot()
        do {
            let updated = try deleteScene(json: current.rawJson, sceneId: sceneID)
            self.manifest = updated
            self.selectedSceneID = updated.scenes.first?.id
            self.statusMessage = "씬 삭제 완료"
            refreshLivePreview()
        } catch {
            self.errorMessage = "씬 삭제 실패: \(error.localizedDescription)"
        }
    }

    public func moveScenes(from source: IndexSet, to destination: Int) {
        guard let current = manifest, let fromIndex = source.first else { return }
        let targetIndex = destination > fromIndex ? destination - 1 : destination
        guard fromIndex != targetIndex else { return }
        clearError()
        pushUndoSnapshot()
        do {
            let updated = try reorderScenes(
                json: current.rawJson,
                fromIndex: UInt32(fromIndex),
                toIndex: UInt32(targetIndex)
            )
            self.manifest = updated
            self.statusMessage = "씬 순서 변경 완료"
            refreshLivePreview()
        } catch {
            self.errorMessage = "순서 변경 실패: \(error.localizedDescription)"
        }
    }

    // MARK: - Export (Folder or Single-File HTML)
    public func exportToFolder(_ destinationURL: URL, singleFile: Bool = false) -> FfiExportResult? {
        guard let current = manifest, let sourceRoot = sourceRootURL else {
            self.errorMessage = "내보낼 전시관이 없습니다."
            return nil
        }
        clearError()
        do {
            let result = singleFile
                ? try exportManifestSingleFile(
                    json: current.rawJson,
                    sourceRoot: sourceRoot.path,
                    outputDir: destinationURL.path
                )
                : try exportManifestToFolder(
                    json: current.rawJson,
                    sourceRoot: sourceRoot.path,
                    outputDir: destinationURL.path
                )
            let kindLabel = singleFile ? "단일 HTML" : "웹 폴더"
            self.statusMessage = "\(kindLabel) 내보내기 완료 (\(result.copiedAssets.count)개 에셋, \(result.optimizedImages)장 최적화)"
            return result
        } catch {
            self.errorMessage = "내보내기 실패: \(error.localizedDescription)"
            return nil
        }
    }

    public func refreshLivePreview() {
        guard let current = manifest, let sourceRoot = sourceRootURL else { return }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("digital-gallery-preview", isDirectory: true)
            .appendingPathComponent(current.id, isDirectory: true)
        do {
            let result = try exportManifestToFolder(
                json: current.rawJson,
                sourceRoot: sourceRoot.path,
                outputDir: tempDir.path
            )
            self.previewDirectoryURL = tempDir
            self.previewHTMLURL = URL(fileURLWithPath: result.outputHtml)
            self.previewRevision += 1
        } catch {
            self.errorMessage = "미리보기 생성 실패: \(error.localizedDescription)"
        }
    }

    private func copyMediaIntoProject(fileURL: URL, subdir: String, sourceRoot: URL) throws -> String {
        let fm = FileManager.default
        let destDir = sourceRoot.appendingPathComponent(subdir, isDirectory: true)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destURL = destDir.appendingPathComponent(fileURL.lastPathComponent)
        if fileURL.standardizedFileURL != destURL.standardizedFileURL {
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: fileURL, to: destURL)
        }
        return "\(subdir)/\(fileURL.lastPathComponent)"
    }

    private func clearError() {
        self.errorMessage = nil
    }
}
