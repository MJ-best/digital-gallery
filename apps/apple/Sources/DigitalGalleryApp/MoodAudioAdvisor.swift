import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Observation

/// Curated bundled ambient BGM tracks for exhibitions.
enum ExhibitionBGMTrack: String, CaseIterable, Identifiable, Hashable {
    case morningLight = "morning_light"
    case rainyAfternoon = "rainy_afternoon"
    case sunsetWarmth = "sunset_warmth"
    case midnightNocturne = "midnight_nocturne"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .morningLight: return "맑은 아침 패드"
        case .rainyAfternoon: return "비 오는 오후 앰비언트"
        case .sunsetWarmth: return "노을 어쿠스틱"
        case .midnightNocturne: return "깊은 밤 녹턴"
        }
    }

    var moodTag: String {
        switch self {
        case .morningLight: return "밝고 청량한 자연광"
        case .rainyAfternoon: return "차분하고 서정적인 흐린 날"
        case .sunsetWarmth: return "따뜻한 온기와 골든아워"
        case .midnightNocturne: return "고요한 야경과 깊은 밤"
        }
    }

    var systemImage: String {
        switch self {
        case .morningLight: return "sun.max"
        case .rainyAfternoon: return "cloud.rain"
        case .sunsetWarmth: return "sunset"
        case .midnightNocturne: return "moon.stars"
        }
    }

    var filename: String { "\(rawValue).wav" }

    var fileURL: URL? {
        if let url = Bundle.main.url(forResource: rawValue, withExtension: "wav", subdirectory: "Audio") {
            return url
        }
        if let url = Bundle.main.url(forResource: rawValue, withExtension: "wav") {
            return url
        }
        let devFallback = URL(fileURLWithPath: "/Users/mj/.gemini/antigravity/scratch/digital-gallery/apps/xcode/Resources/Audio/\(filename)")
        if FileManager.default.fileExists(atPath: devFallback.path) {
            return devFallback
        }
        return nil
    }
}

struct MoodBGMRecommendation: Equatable {
    let track: ExhibitionBGMTrack
    let reason: String
}

/// Analyzes photo luminance & color warmth on-device (via tiny 16x16 CGContext thumbnails)
/// to recommend the most fitting ambient BGM track for an exhibition.
enum MoodAudioAdvisor {
    static func recommend(from photoDataList: [Data]) -> MoodBGMRecommendation {
        let samples = photoDataList.prefix(8).compactMap { analyzeImageData($0) }
        return decide(from: samples)
    }

    static func recommend(from imageURLs: [URL]) -> MoodBGMRecommendation {
        let samples = imageURLs.prefix(8).compactMap { url -> (luminance: Double, warmth: Double)? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return analyzeImageData(data)
        }
        return decide(from: samples)
    }

    private static func decide(from samples: [(luminance: Double, warmth: Double)]) -> MoodBGMRecommendation {
        guard !samples.isEmpty else {
            return MoodBGMRecommendation(
                track: .morningLight,
                reason: "어떤 사진에도 자연스럽게 어울리는 기본 앰비언트예요"
            )
        }
        let avgLum = samples.map(\.luminance).reduce(0, +) / Double(samples.count)
        let avgWarmth = samples.map(\.warmth).reduce(0, +) / Double(samples.count)

        if avgLum < 0.34 {
            return MoodBGMRecommendation(
                track: .midnightNocturne,
                reason: "어두운 야경과 깊은 무드의 사진이 많아 추천해요"
            )
        } else if avgWarmth < -0.015 {
            return MoodBGMRecommendation(
                track: .rainyAfternoon,
                reason: "차분하고 서정적인 색감의 사진과 잘 어울려요"
            )
        } else if avgWarmth > 0.055 && avgLum < 0.72 {
            return MoodBGMRecommendation(
                track: .sunsetWarmth,
                reason: "따뜻한 빛과 온기가 느껴지는 사진들이에요"
            )
        } else {
            return MoodBGMRecommendation(
                track: .morningLight,
                reason: "밝고 투명한 자연광 사진과 잘 어울려요"
            )
        }
    }

    private static func analyzeImageData(_ data: Data) -> (luminance: Double, warmth: Double)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 32,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            return nil
        }

        let size = 16
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: size, height: size))

        var rSum = 0.0
        var gSum = 0.0
        var bSum = 0.0
        let count = Double(size * size)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            rSum += Double(pixels[i]) / 255.0
            gSum += Double(pixels[i + 1]) / 255.0
            bSum += Double(pixels[i + 2]) / 255.0
        }
        let r = rSum / count
        let g = gSum / count
        let b = bSum / count
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let warmth = r - b
        return (luminance, warmth)
    }
}

/// Lightweight on-device audio player for previewing BGM tracks inside New Exhibition / Editor sheets.
@MainActor
@Observable
final class BGMPreviewPlayer {
    var playingTrack: ExhibitionBGMTrack?
    private var player: AVAudioPlayer?

    func togglePreview(_ track: ExhibitionBGMTrack) {
        if playingTrack == track {
            stop()
            return
        }
        stop()
        guard let url = track.fileURL else { return }
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.55
            p.play()
            self.player = p
            self.playingTrack = track
        } catch {
            self.playingTrack = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingTrack = nil
    }
}
