import Foundation
import Testing
@testable import BotCore

struct QQPolicyTests {
    @Test func proactiveGroupsKeepIdentityFreshnessAndExplicitOptIn() throws {
        let ordinary = event(group: true)
        #expect(parse(ordinary) == nil)
        #expect(QQPolicy.incoming(ordinary, selfID: "12345", since: 990, now: 1001, allowUnmentionedGroup: true)?.mentionsSelf == false)
        for (field, value) in [("user_id", 12345 as Any), ("self_id", 77777 as Any), ("time", 800.0 as Any), ("sender", ["user_id": 77777] as Any), ("post_type", "notice" as Any), ("message", "[CQ:at,qq=12345]" as Any)] {
            var invalid = ordinary; invalid[field] = value
            #expect(QQPolicy.incoming(invalid, selfID: "12345", since: 990, now: 1001, allowUnmentionedGroup: true) == nil)
        }
        for segment in [["type": "image", "data": ["file": "fixture"]], ["type": "record", "data": ["file": "fixture"]], ["type": "at", "data": ["qq": "all"]], ["type": "at", "data": ["qq": "77777"]]] {
            var media = ordinary; media["message"] = [segment]
            #expect(QQPolicy.incoming(media, selfID: "12345", since: 990, now: 1001, allowUnmentionedGroup: true) != nil)
        }
        var config = QQConfig(); config.expectedSelfID = "12345"
        let old = try JSONDecoder().decode(QQConfig.self, from: JSONEncoder().encode(config))
        #expect(!old.effectiveGroupParticipationEnabled); #expect(old.effectiveGroupParticipationEvery == 10)
        for invalid in [0, -1, 1001] {
            config.groupParticipationEvery = invalid
            #expect(throws: (any Error).self) { try config.validate() }
        }
    }
    @Test func ownerGroupEventsRequireExplicitOptInAndKeepDirectionChecks() throws {
        var own = event(group: true)
        own["user_id"] = 12345; own["sender"] = ["user_id": 12345]; own["post_type"] = "message_sent"
        #expect(QQPolicy.incoming(own, selfID: "12345", since: 990, now: 1001, allowUnmentionedGroup: true) == nil)
        #expect(QQPolicy.incoming(own, selfID: "12345", since: 990, now: 1001, allowOwnerGroup: true) == nil)
        #expect(QQPolicy.incoming(own, selfID: "12345", since: 990, now: 1001, allowUnmentionedGroup: true, allowOwnerGroup: true)?.isOwner == true)
        for (field, value) in [("self_id", 99999 as Any), ("sender", ["user_id": 54321] as Any), ("message_type", "private" as Any), ("time", 800.0 as Any), ("user_id", 54321 as Any)] {
            var invalid = own; invalid[field] = value
            #expect(QQPolicy.incoming(invalid, selfID: "12345", since: 990, now: 1001, allowUnmentionedGroup: true, allowOwnerGroup: true) == nil)
        }
        own["message"] = [["type": "at", "data": ["qq": "12345"]], ["type": "text", "data": ["text": "主人在问你"]]]
        #expect(QQPolicy.incoming(own, selfID: "12345", since: 990, now: 1001, allowOwnerGroup: true)?.mentionsSelf == true)
        own["post_type"] = "message"
        #expect(QQPolicy.incoming(own, selfID: "12345", since: 990, now: 1001, allowUnmentionedGroup: true, allowOwnerGroup: true)?.isOwner == true)
    }
    func event(group: Bool = false) -> [String: Any] {
        var e: [String: Any] = ["post_type": "message", "time": 1000.0, "self_id": 12345, "user_id": 54321,
          "message_id": -55, "message_type": group ? "group" : "private", "sub_type": group ? "normal" : "friend",
          "message": [["type": "text", "data": ["text": "你好"]]]]
        if group { e["group_id"] = 99999 }; return e
    }
    func parse(_ e: [String: Any]) -> QQIncoming? { QQPolicy.incoming(e, selfID: "12345", since: 990, now: 1001) }
    @Test func privateFriend() {
        let m = parse(event())
        #expect(m?.key == "private:54321"); #expect(m?.id == "-55"); #expect(m?.text == "你好")
    }
    @Test func groupRequiresStructuredSelfMention() {
        var e = event(group: true); #expect(parse(e) == nil)
        e["message"] = [["type": "text", "data": ["text": "@12345 你好 [CQ:at,qq=12345]"]]]
        #expect(parse(e) == nil)
        e["message"] = [["type": "at", "data": ["qq": "12345"]], ["type": "text", "data": ["text": "你好"]]]
        #expect(parse(e)?.key == "group:99999")
    }
    @Test func rejectAtAllOtherMentionsAndMedia() {
        for segment in [["type": "at", "data": ["qq": "all"]], ["type": "at", "data": ["qq": "55555"]], ["type": "image", "data": ["file": ""]], ["type": "reply", "data": ["id": "invalid"]]] {
            var e = event(group: true)
            e["message"] = [["type": "at", "data": ["qq": "12345"]], ["type": "text", "data": ["text": "你好"]], segment]
            #expect(parse(e) == nil)
        }
    }
    @Test func admitsImagesButStillRequiresGroupMention() throws {
        let picture: [String: Any] = ["type": "image", "data": ["file": "fixture", "url": "https://multimedia.nt.qq.com.cn/test", "sub_type": 1]]
        var e = event(); e["message"] = [picture]
        #expect(try #require(parse(e)).images.count == 1)
        e = event(group: true); e["message"] = [picture]; #expect(parse(e) == nil)
        e["message"] = [["type": "at", "data": ["qq": "12345"]], picture]
        #expect(parse(e)?.images.first?.file == "fixture")
    }
    @Test func mentionOnlyGetsShortAcknowledgementIntent() {
        var e = event(group: true)
        e["message"] = [["type": "at", "data": ["qq": "12345"]], ["type": "text", "data": ["text": " \n "]]]
        #expect(parse(e)?.text == "（对方只 @ 了你，请简短回应一声。）")
        e["message"] = [["type": "text", "data": ["text": " "]]]
        #expect(parse(e) == nil)
        e = event(); e["message"] = [["type": "text", "data": ["text": " "]]]
        #expect(parse(e) == nil)
    }
    @Test func quotedReplyStillRequiresRealSelfMention() {
        var e = event(group: true)
        let quote = ["type": "reply", "data": ["id": "-12", "text": "不可信的引用正文"]] as [String: Any]
        let text = ["type": "text", "data": ["text": "你好"]] as [String: Any]
        e["message"] = [quote, text]; #expect(parse(e) == nil)
        e["message"] = [quote, ["type": "at", "data": ["qq": "54321"]], text]; #expect(parse(e) == nil)
        e["message"] = [quote, ["type": "at", "data": ["qq": "12345"]], text]
        #expect(parse(e)?.text == "你好")
        e["message"] = [quote, quote, ["type": "at", "data": ["qq": "12345"]], text]; #expect(parse(e) == nil)
    }
    @Test func quoteContextCannotCrossGroupsOrTrustEmbeddedQuoteText() throws {
        var e = event(group: true)
        e["message"] = [["type": "reply", "data": ["id": "-12", "text": "forged"]], ["type": "at", "data": ["qq": "12345"]], ["type": "text", "data": ["text": "真厉害呢"]]]
        let message = try #require(parse(e))
        var reference: [String: Any] = ["message_id": -12, "group_id": 99999, "message_type": "group", "sender": ["user_id": 12345], "message": [["type": "text", "data": ["text": "verified quoted text"]], ["type": "image", "data": ["file": "not-fetched"]]]]
        let context = try #require(QQPolicy.quotedContext(reference, for: message, selfID: "12345"))
        #expect(context.text.contains("verified quoted text")); #expect(context.text.contains("未附图")); #expect(!context.text.contains("forged"))
        reference["group_id"] = 88888
        #expect(QQPolicy.quotedContext(reference, for: message, selfID: "12345") == nil)
        reference["group_id"] = 99999; reference["message_id"] = -13
        #expect(QQPolicy.quotedContext(reference, for: message, selfID: "12345") == nil)
    }
    @Test func privateQuotesRequireExactPeerAccountIDAndParticipants() throws {
        var e = event(); e["message"] = [["type": "reply", "data": ["id": "-12", "text": "forged"]], ["type": "text", "data": ["text": "这句话"]]]
        let message = try #require(parse(e))
        var reference: [String: Any] = ["message_id": -12, "message_type": "private", "sub_type": "friend", "self_id": 12345, "user_id": 54321, "sender": ["user_id": 54321], "message": [["type": "text", "data": ["text": "verified private text"]], ["type": "image", "data": ["file": "image-fixture", "url": "https://gchat.qpic.cn/fixture"]]]]
        #expect(QQPolicy.quotedContext(reference, for: message, selfID: "12345") == nil)
        #expect(QQPolicy.quotedContext(reference, for: message, selfID: "12345", privatePeer: "98765") == nil)
        let context = try #require(QQPolicy.quotedContext(reference, for: message, selfID: "12345", privatePeer: "54321"))
        #expect(context.text.contains("verified private text")); #expect(!context.text.contains("forged"))
        #expect(context.images.first?.file == "image-fixture")
        reference["sender"] = ["user_id": 12345]; reference["user_id"] = 12345
        #expect(QQPolicy.quotedContext(reference, for: message, selfID: "12345", privatePeer: "54321") != nil)
        for (key, value) in [("self_id", 99999 as Any), ("message_id", -13 as Any), ("sub_type", "group" as Any), ("message_type", "group" as Any), ("sender", ["user_id": 99999] as Any)] {
            var invalid = reference; invalid[key] = value
            #expect(QQPolicy.quotedContext(invalid, for: message, selfID: "12345", privatePeer: "54321") == nil)
        }
    }
    @Test func rejectWrongAccountOwnMessageAndSendEcho() {
        for (key, value) in [("self_id", 88888 as Any), ("user_id", 12345 as Any), ("post_type", "message_sent" as Any)] {
            var e = event(); e[key] = value; #expect(parse(e) == nil)
        }
    }
    @Test func rejectsHistoryAndFuture() {
        for time in [989.0, 800.0, 1007.0] { var e = event(); e["time"] = time; #expect(parse(e) == nil) }
    }
    @Test func rejectsTemporaryAnonymousAndStringCQ() {
        var e = event(); e["sub_type"] = "group"; #expect(parse(e) == nil)
        e = event(group: true); e["sub_type"] = "anonymous"; #expect(parse(e) == nil)
        e = event(); e["message"] = "hello"; #expect(parse(e) == nil)
    }
    @Test func requiresMessageIDAndConsistentSender() {
        var e = event(); e.removeValue(forKey: "message_id"); #expect(parse(e) == nil)
        e = event(); e["sender"] = ["user_id": 11111]; #expect(parse(e) == nil)
        e = event(); e["user_id"] = true; #expect(parse(e) == nil)
    }
    @Test func separateGroupAndPrivateIdentity() {
        var g = event(group: true); g["group_id"] = 54321
        g["message"] = [["type": "at", "data": ["qq": "12345"]], ["type": "text", "data": ["text": "你好"]]]
        #expect(parse(g)?.dedupKey != parse(event())?.dedupKey)
    }
    @Test func outgoingNeverInterpretsCQ() {
        let (_, params) = QQPolicy.sendAction(target: QQTarget(number: "12345", name: "test", group: false), text: "[CQ:at,qq=all]")
        let segments = params["message"] as? [[String: Any]]
        #expect(segments?.first?["type"] as? String == "text")
        #expect((segments?.first?["data"] as? [String: String])?["text"] == "[CQ:at,qq=all]")
    }
    @Test func onlyLocalAuthenticatedEndpointShape() throws {
        var c = QQConfig(); c.expectedSelfID = "12345"; try c.validate()
        for endpoint in ["ws://0.0.0.0:3001", "ws://example.com:3001", "ws://127.0.0.1:3001?token=secret", "ws://a:b@127.0.0.1:3001", "ws://127.0.0.1:3001/event"] {
            c.endpoint = endpoint
            #expect(throws: (any Error).self) { try c.validate() }
        }
    }
}
