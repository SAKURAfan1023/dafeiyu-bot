import Foundation
#if canImport(ImageIO)
import ImageIO
import UniformTypeIdentifiers
#endif
import Testing
@testable import WeChatAIBot

struct QQIncomingImagesTests {
    static func animatedFixture() throws -> Data {
        #if os(Linux)
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("synthetic-images.json")
        let images = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        let encoded = try #require(images["animated"])
        return try #require(Data(base64Encoded: encoded))
        #else
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes, UTType.gif.identifier as CFString, 12, nil))
        for index in 0..<12 {
            let context = try #require(CGContext(data: nil, width: 240, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 240, height: 120))
            context.setFillColor(CGColor(red: 0, green: 0.3, blue: 1, alpha: 1))
            context.fillEllipse(in: CGRect(x: 10 + index * 17, y: 40, width: 32, height: 32))
            let frame = try #require(context.makeImage())
            CGImageDestinationAddImage(destination, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: index == 4 ? 0.8 : 0.1]] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        return bytes as Data
        #endif
    }
    @Test func animatedFramesCoverMotionAndRespectSharedBudget() throws {
        let gif = try Self.animatedFixture()
        let frames = try QQIncomingImages.frames(gif)
        #expect((4...6).contains(frames.count))
        #expect(frames.first != frames.last)
        #expect(try QQIncomingImages.frames(gif, maxFrames: 2).count == 2)
        #expect(try QQIncomingImages.frames(gif, maxFrames: 1).count == 1)
        let still = try #require(frames.first)
        #expect(try QQIncomingImages.frames(still).count == 1)
    }
    @Test func restrictsSourceAndDecodesToBoundedJPEG() throws {
        for url in ["file:///secret", "https://127.0.0.1/x", "https://multimedia.nt.qq.com.cn.evil.org/a", "https://x:y@gchat.qpic.cn/a", "https://gchat.qpic.cn:123/a"] { #expect(QQIncomingImages.allowedURL(url) == nil) }
        #expect(QQIncomingImages.allowedURL("http://gchat.qpic.cn/a")?.scheme == "https")
        #expect(throws: (any Error).self) { try QQIncomingImages.frames(Data("invalid".utf8)) }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/QQStickers")
        let library = QQStickerLibrary(directory: root)
        let frames = try QQIncomingImages.frames(try #require(library.data(for: library.items[0])))
        #expect((1...3).contains(frames.count))
        for frame in frames {
            #expect(frame.starts(with: [255,216])); #expect(frame.count <= 2_000_000)
            #if canImport(ImageIO)
            let source = try #require(CGImageSourceCreateWithData(frame as CFData, nil))
            let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            #expect((props[kCGImagePropertyPixelWidth] as! Int) <= 1280)
            #expect((props[kCGImagePropertyPixelHeight] as! Int) <= 1280)
            #endif
        }
    }
}
