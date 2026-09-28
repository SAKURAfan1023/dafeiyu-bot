import Foundation
import ImageIO
import UniformTypeIdentifiers

struct QQIncomingImages {
    private static let ephemeralSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    var session: URLSession = ephemeralSession
    static func allowedURL(_ value: String?) -> URL? {
        guard let value, value.utf8.count <= 8192, var url = URLComponents(string: value),
              ["http", "https"].contains(url.scheme ?? ""), url.user == nil, url.password == nil, url.port == nil,
              ["multimedia.nt.qq.com.cn", "gchat.qpic.cn", "c2cpicdw.qpic.cn", "q.qlogo.cn"].contains(url.host ?? "") else { return nil }
        url.scheme = "https"; url.fragment = nil
        return url.url
    }
    func load(_ value: String?, maxFrames: Int = 6) async throws -> [Data] {
        guard let url = Self.allowedURL(value) else { throw AppFailure.message("图片下载地址不受支持") }
        var request = URLRequest(url: url); request.timeoutInterval = 15
        let (bytes, response) = try await session.bytes(for: request, delegate: QQImageNoRedirect())
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.expectedContentLength <= 8_000_000 else { throw AppFailure.message("图片暂时无法下载") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 8_000_000 else { throw AppFailure.message("图片太大，未进行识别") }
            data.append(byte)
        }
        try Task.checkCancellation()
        return try Self.frames(data, maxFrames: maxFrames)
    }
    static func frames(_ data: Data, maxFrames: Int = 6) throws -> [Data] {
        guard data.count <= 8_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...12000).contains(width), (1...12000).contains(height), width * height <= 40_000_000 else { throw AppFailure.message("图片格式或尺寸不受支持") }
        let count = CGImageSourceGetCount(source)
        guard count > 0 && count <= 1000 else { throw AppFailure.message("动图帧数不受支持") }
        // Sample across playback time, not only frame number; GIF delays can vary greatly.
        let budget = min(count, max(1, min(6, maxFrames)))
        var elapsed = 0.0, ends: [Double] = []
        for index in 0..<count {
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            elapsed += delay.isFinite ? min(10, max(0.02, delay)) : 0.1; ends.append(elapsed)
        }
        var selected = Set([0])
        if budget > 1 {
            selected.insert(count - 1)
            for step in 1..<(budget - 1) {
                let time = elapsed * Double(step) / Double(budget - 1)
                selected.insert(ends.firstIndex(where: { $0 >= time }) ?? count - 1)
            }
            // Long holds may collapse samples; fill remaining slots with evenly spaced frames.
            for step in 0..<budget where selected.count < budget { selected.insert(step * (count - 1) / (budget - 1)) }
        }
        let indexes = selected.sorted()
        var frames: [Data] = []
        for index in indexes {
            try Task.checkCancellation()
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1280, kCGImageSourceCreateThumbnailWithTransform: true]
            guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { continue }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, frame, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            if CGImageDestinationFinalize(destination), output.length <= 2_000_000 { frames.append(output as Data) }
        }
        guard !frames.isEmpty else { throw AppFailure.message("图片解码失败") }
        return frames
    }
}
private final class QQImageNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
