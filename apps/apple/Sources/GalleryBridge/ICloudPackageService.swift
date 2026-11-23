import Foundation

/// Safe `.gallery` Document Package persistence and iCloud Drive synchronization service.
///
/// Architectural principle:
/// - A `.gallery` package contains ONLY declarative `manifest.json` + media assets (`images/`, `audio/`, etc.).
/// - Local SQLite indexes/caches are never placed inside `.gallery` to avoid iCloud Drive sync corruption.
/// - All reads and writes go through `NSFileCoordinator` for multi-device safety.
public final class ICloudPackageService: Sendable {
    public struct PackageLocation: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
        public let url: URL
        public let isICloudBacked: Bool

        public init(url: URL, isICloudBacked: Bool) {
            self.id = url.path
            self.name = url.deletingPathExtension().lastPathComponent
            self.url = url
            self.isICloudBacked = isICloudBacked
        }
    }

    public init() {}

    /// Returns the iCloud Drive Ubiquity container directory if signed/entitled,
    /// otherwise falls back to a local `~/Documents/DigitalGallery` directory.
    public func resolvePackagesRoot() -> (url: URL, isICloud: Bool) {
        let fm = FileManager.default
        if let ubiquity = fm.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("DigitalGallery", isDirectory: true)
        {
            try? fm.createDirectory(at: ubiquity, withIntermediateDirectories: true)
            return (ubiquity, true)
        }

        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let localRoot = docs.appendingPathComponent("DigitalGallery", isDirectory: true)
        try? fm.createDirectory(at: localRoot, withIntermediateDirectories: true)
        return (localRoot, false)
    }

    /// List all `.gallery` packages in the sync directory.
    public func listPackages() -> [PackageLocation] {
        let (root, isICloud) = resolvePackagesRoot()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries
            .filter { $0.pathExtension == "gallery" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { PackageLocation(url: $0, isICloudBacked: isICloud) }
    }

    /// Save a `.gallery` Document Package (`manifest.json` + media files) atomically
    /// using `NSFileCoordinator` (falling back to direct write if filecoordinationd is unavailable).
    public func savePackage(
        manifestJSON: String,
        sourceRoot: URL,
        packageURL: URL
    ) throws -> URL {
        let performWrite: (URL) throws -> Void = { targetURL in
            let fm = FileManager.default
            try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)

            if sourceRoot.standardizedFileURL != targetURL.standardizedFileURL {
                let parsed = try parseManifestJson(json: manifestJSON)
                let manifestPath = targetURL.appendingPathComponent("manifest.json")
                try saveManifestJson(manifestPath: manifestPath.path, json: parsed.rawJson)

                for sub in ["images", "audio", "videos"] {
                    let srcSub = sourceRoot.appendingPathComponent(sub, isDirectory: true)
                    if fm.fileExists(atPath: srcSub.path) {
                        let dstSub = targetURL.appendingPathComponent(sub, isDirectory: true)
                        try fm.createDirectory(at: dstSub, withIntermediateDirectories: true)
                        if let files = try? fm.contentsOfDirectory(at: srcSub, includingPropertiesForKeys: nil) {
                            for file in files {
                                let dstFile = dstSub.appendingPathComponent(file.lastPathComponent)
                                if !fm.fileExists(atPath: dstFile.path) {
                                    try fm.copyItem(at: file, to: dstFile)
                                }
                            }
                        }
                    }
                }
            } else {
                let manifestPath = targetURL.appendingPathComponent("manifest.json")
                try saveManifestJson(manifestPath: manifestPath.path, json: manifestJSON)
            }
        }

        var coordinatorError: NSError?
        var innerError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(writingItemAt: packageURL, options: [.forMerging], error: &coordinatorError) { targetURL in
            do {
                try performWrite(targetURL)
            } catch {
                innerError = error
            }
        }

        if let innerError {
            throw innerError
        }
        if coordinatorError != nil {
            // Fallback when filecoordinationd is unavailable (e.g. headless/sandboxed environments)
            try performWrite(packageURL)
        }
        return packageURL
    }

    /// Read a `.gallery` Document Package safely via `NSFileCoordinator`.
    public func loadPackage(at packageURL: URL) throws -> FfiManifestSummary {
        var coordinatorError: NSError?
        var result: Result<FfiManifestSummary, Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(readingItemAt: packageURL, options: [], error: &coordinatorError) { url in
            result = Result {
                try loadManifestFromFile(manifestPath: url.path)
            }
        }

        if let result {
            return try result.get()
        }
        if coordinatorError != nil {
            return try loadManifestFromFile(manifestPath: packageURL.path)
        }
        return try loadManifestFromFile(manifestPath: packageURL.path)
    }
}
