import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

enum SocialPlatform: String, Codable, CaseIterable {
    case xiaohongshu, bilibili
    var name: String { self == .xiaohongshu ? "小红书" : "B站" }
    var contentName: String { self == .xiaohongshu ? "笔记" : "视频" }
    var canWrite: Bool { true }
    var hosts: Set<String> { self == .xiaohongshu ? ["www.xiaohongshu.com"] : ["www.bilibili.com", "search.bilibili.com"] }
    func postURL(_ id: String) -> URL {
        let base = self == .xiaohongshu ? "https://www.xiaohongshu.com/explore/" : "https://www.bilibili.com/video/"
        return URL(string: base + id.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)!
    }
}
enum SocialAccessFailure: Error, LocalizedError {
    case restricted
    var errorDescription: String? { "平台出现警告、验证或访问限制，已暂停自动访问；请在官方客户端核对" }
}
/// Shared only by engines in the same local application. Keys never enter platform executors.
@MainActor final class SocialModelAccess {
    var temporary: [String: String] = [:]
}
enum SocialMode: String, Codable, CaseIterable { case browse, review, auto }
enum SocialPersonality: String, Codable, CaseIterable {
    case natural, gentle, teasing, tsundere, energetic, calm, catgirl, witty, custom
    var name: String {
        switch self {
        case .natural: return "大肥鱼"
        case .gentle: return "温柔"
        case .teasing: return "雌小鬼"
        case .tsundere: return "傲娇"
        case .energetic: return "元气"
        case .calm: return "理性"
        case .catgirl: return "猫娘"
        case .witty: return "贴吧玩梗"
        case .custom: return "自定义"
        }
    }
    var prompt: String {
        switch self {
        case .natural: return "你是大肥鱼，一个俏皮好奇的 AI 角色。先接住具体话题，再轻轻接梗；自然短句，不堆口癖，不重复泛泛提问。"
        case .gentle: return "你是大肥鱼，温和真诚，先理解再回应，不强行安慰、不说教、不对陌生人过度亲昵。"
        case .teasing: return "你是大肥鱼，成年喜剧角色的顽皮嘴硬，小得意但心软；只在轻松互损时逗人，不主动羞辱陌生人，不连发反问或杂鱼口癖。"
        case .tsundere: return "你是大肥鱼，有点傲娇嘴硬但心软；只轻微逞强，不反复哼、笨蛋或才不是，不以贬低表达关心。"
        case .energetic: return "你是大肥鱼，开朗有活力，善于接梗；不用每句感叹号，认真求助时先给有用回应。"
        case .calm: return "你是大肥鱼，冷静直接，重视事实，能理解反串和自嘲，承认不知道，不摆专家架子。"
        case .catgirl: return "你是大肥鱼的猫娘风格，好奇俏皮；偶尔一个喵，不句句加尾缀、不写括号动作，不把陌生人叫主人。"
        case .witty: return "你是大肥鱼，用贴吧式短评接梗，偶用绷、典、乐，必须有具体语境。优先自嘲或吐槽事情，不因正常讨论主动骂人，不把反串和自嘲当真实立场，不牵扯家人。"
        case .custom: return "使用面板配置的角色与表达，不自动套用其他预设。"
        }
    }
}
struct SocialSettings: Codable, Equatable {
    var keyword = "独立游戏"
    var mode: SocialMode = .auto
    var persona = ""
    // Missing optional fields preserve older locally saved settings.
    var personality: SocialPersonality? = .natural
    var memoryEnabled: Bool? = true
    var baseURL = "https://api.deepseek.com"
    var model = "deepseek-flash"
    var durationMinutes = 15
    var maxPosts = 5
    var maxModelCalls = 5
    var dailyWriteLimit = 3
    var intervalSeconds = 300
    var readIntervalSeconds: Int? = 60
    var maxCharacters = 80
    var credentialAccount: String {
        baseURL == "https://api.deepseek.com" ? "api-key" : "social-" + socialHash(baseURL)
    }
    func validate() throws {
        guard (1...80).contains(keyword.trimmingCharacters(in: .whitespacesAndNewlines).count), persona.count <= 2000,
              personality != .custom || !persona.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (5...120).contains(durationMinutes), (1...20).contains(maxPosts), (1...100).contains(maxModelCalls),
              (0...100).contains(dailyWriteLimit), (30...3600).contains(intervalSeconds), (20...300).contains(maxCharacters),
              (5...3600).contains(readIntervalSeconds ?? 30),
              !model.isEmpty, model.count <= 100, let url = URL(string: baseURL), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.host != nil,
              url.scheme == "https" || (url.scheme == "http" && url.host == "127.0.0.1") else {
            throw AppFailure.message("请检查主题、模型地址和数量范围")
        }
    }
}
struct SocialThreadMemory: Codable {
    var accountID: String; var postID: String
    var summary: String
    var note: String = ""
    var updatedAt = Date()
}
struct SocialCandidate: Codable, Identifiable {
    var id: String; var title: String; var author: String; var kind: String
}
struct SocialComment: Codable, Identifiable, Equatable {
    var id: String; var rootID: String?; var authorID: String; var author: String; var text: String
}
struct SocialPost: Codable, Identifiable, Equatable {
    var id: String; var title: String; var text: String; var author: String; var authorID: String
    var kind: String; var imageCount: Int; var comments: [SocialComment]; var coverage: String
    var platform: SocialPlatform?
    var url: URL { (platform ?? .xiaohongshu).postURL(id) }
    func fingerprint(parentID: String?) -> String {
        socialHash(id + "\n" + title + "\n" + text + "\n" + (parentID.flatMap { id in comments.first { $0.id == id } }.map { $0.id + $0.authorID + $0.text } ?? ""))
    }
}
enum SocialState: String, Codable { case draft, skipped, sending, accepted, confirmed, uncertain, rejected, cancelled }
struct SocialRecord: Codable, Identifiable {
    var id = UUID(); var createdAt = Date(); var runID: UUID
    var accountID: String; var post: SocialPost; var parentID: String?
    var text: String; var summary: String; var reason: String
    var fingerprint: String; var hash: String; var revision: Int
    var state: SocialState = .draft
    var expiresAt: Date?
    var externalID: String?; var reservedAt: Date?; var quotaDay: String?
    var acknowledgedAt: Date?
    var blocking: Bool { (state == .sending || state == .uncertain) && acknowledgedAt == nil }
}
struct SocialStored: Codable {
    var settings = SocialSettings()
    var revision = 1
    var boundUID = ""
    var observedName = ""
    var timeZone = TimeZone.current.identifier
    var records: [SocialRecord] = []
    var modelAttempts = 0
    var modelTokens = 0
    var memories: [SocialThreadMemory]?
    var warningAt: Date?
    var nextReadAt: Date?
}
func socialHash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }

struct SocialCommand: Codable {
    var requestID: UUID
    var action: String
    var revision: Int?
    var recordID: UUID?
    var hash: String?
    var content: String?
    var settings: SocialSettings?
    var expectedUID: String?
    var key: String?
    var persistKey: Bool?
    var acknowledge: Bool?
    var platform: SocialPlatform?
}
