import Foundation
import GalleryBridge
import XCTest

final class GalleryBridgeTests: XCTestCase {
    func testRustFFIRoundtripWithDemoPackageAndSingleFileExport() throws {
        let demoPackage = "/Users/mj/.gemini/antigravity/scratch/digital-gallery/demo/Quiet_Autumn.gallery"
        let loaded = try loadManifestFromFile(manifestPath: demoPackage)
        XCTAssertEqual(loaded.title, "Quiet Autumn")
        XCTAssertEqual(loaded.sceneCount, 5)

        // 1. Live palette resolution
        let palette = try resolveMoodPalette(moodPreset: "dark_room")
        XCTAssertEqual(palette.background, "#171615")

        // 2. Edit individual item inside HorizontalTrack (scene index 2)
        let trackScene = loaded.scenes[2]
        XCTAssertEqual(trackScene.kind, "horizontal_track")
        XCTAssertEqual(trackScene.items.count, 4)

        let itemEdited = try updateSceneItem(
            json: loaded.rawJson,
            sceneId: trackScene.id,
            itemIndex: 1,
            title: nil,
            caption: "강물 위로 번지는 저녁빛"
        )
        XCTAssertEqual(itemEdited.scenes[2].items[1].caption, "강물 위로 번지는 저녁빛")

        // 3. Remove one item from HorizontalTrack
        let trimmed = try removeSceneItem(
            json: itemEdited.rawJson,
            sceneId: trackScene.id,
            itemIndex: 3
        )
        XCTAssertEqual(trimmed.scenes[2].items.count, 3)

        // 4. Single-file self-contained HTML export (AirDrop / iOS Files ready)
        let singleOutDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gallery-single-test-\(UUID().uuidString)", isDirectory: true)
        let singleExport = try exportManifestSingleFile(
            json: trimmed.rawJson,
            sourceRoot: demoPackage,
            outputDir: singleOutDir.path
        )
        let singleHTML = try String(contentsOfFile: singleExport.outputHtml, encoding: .utf8)
        XCTAssertTrue(singleHTML.contains("data:image/svg+xml;base64,"))
        XCTAssertTrue(singleHTML.contains("data:audio/wav;base64,"))
        XCTAssertTrue(singleHTML.contains("window.__galleryBridge"))
        XCTAssertTrue(singleHTML.contains("강물 위로 번지는 저녁빛"))
    }
}
