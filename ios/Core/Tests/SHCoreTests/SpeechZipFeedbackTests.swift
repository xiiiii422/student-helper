import XCTest
@testable import SHCore

/// 朗读归一化测试。这些断言的每条都对应「念出来像不像人」，
/// 错了不会崩溃，只会被学生听出来，所以必须靠测试而不是靠耳朵守。
final class SpeechTextTests: XCTestCase {

    func test分数按中文语序念() {
        // 中文说「八分之七」：先分母后分子，和书写顺序相反
        XCTAssertEqual(SpeechText.speakMath("\\frac{7}{8}"), "八分之七")
        // 嵌套分数从最内层剥：1/(2/3) → 一分之二分之三
        XCTAssertEqual(SpeechText.speakMath("\\frac{1}{\\frac{2}{3}}"), "一分之二分之三")
    }

    func test行内公式整体翻成口语() {
        let spoken = SpeechText.normalize("答：\\( \\frac{7}{8} \\)。")
        XCTAssertTrue(spoken.contains("八分之七"), spoken)
        XCTAssertFalse(spoken.contains("\\"), "不该把反斜杠念出来：\(spoken)")
        XCTAssertFalse(spoken.contains("frac"), "不该念出命令名：\(spoken)")
    }

    func test常见运算符与符号() {
        XCTAssertEqual(SpeechText.speakMath("3 \\times 4 = 12"), "3 乘 4 等于 12")
        XCTAssertEqual(SpeechText.speakMath("a^2"), "a 的平方")
        XCTAssertEqual(SpeechText.speakMath("r^3"), "r 的立方")
        XCTAssertTrue(SpeechText.speakMath("S = \\pi r^2").contains("π"))
        XCTAssertEqual(SpeechText.speakMath("25\\%"), "百分之25")
        XCTAssertEqual(SpeechText.speakMath("1 \\div 2"), "1 除以 2")
    }

    func test小标题念成停顿而不是括号() {
        let spoken = SpeechText.normalize("【答案】\n答：11/12")
        XCTAssertFalse(spoken.contains("【"), "括号不该被念出来：\(spoken)")
        XCTAssertTrue(spoken.contains("答案，"), spoken)
    }

    func test未知命令被丢弃而不是念出名字() {
        let spoken = SpeechText.speakMath("\\text{甲} + 1")
        XCTAssertFalse(spoken.contains("\\"), spoken)
        XCTAssertTrue(spoken.contains("加"), spoken)
    }

    func test分句按标点断且长度可控() {
        let long = String(repeating: "这是一个很长的句子用来验证换气切分，", count: 12) + "结束。"
        let sentences = SpeechText.splitSentences(long, maxChunkChars: 42)
        XCTAssertGreaterThan(sentences.count, 2)
        for sentence in sentences {
            XCTAssertLessThanOrEqual(sentence.count, 60, "单句过长 TTS 会越念越快：\(sentence)")
        }
    }

    func test中英混排切成不同语种() {
        let chunks = SpeechText.chunks("apple 的中文是苹果。")
        XCTAssertTrue(chunks.contains { $0.language == .english })
        XCTAssertTrue(chunks.contains { $0.language == .chinese })
    }

    func test空输入不炸() {
        XCTAssertTrue(SpeechText.chunks("").isEmpty)
        XCTAssertTrue(SpeechText.normalize("   \n  ").isEmpty)
    }
}

/// ZIP 读写测试：备份是「导出去还能导回来」的契约，格式写错等于数据丢了。
final class ZipTests: XCTestCase {

    func test写入再读回内容一致() throws {
        let entries = [
            Zip.Entry(name: "data.json", data: Data("{\"a\":1}".utf8)),
            Zip.Entry(name: "images/a.jpg", data: Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])),
        ]
        let archive = Zip.write(entries)
        let back = try Zip.read(archive)
        XCTAssertEqual(Set(back.map(\.name)), Set(entries.map(\.name)))
        for entry in entries {
            XCTAssertEqual(back.first { $0.name == entry.name }?.data, entry.data)
        }
    }

    func test文件头与结束标记符合规范() {
        let archive = Zip.write([Zip.Entry(name: "x.txt", data: Data("hi".utf8))])
        let head = [UInt8](archive.prefix(4))
        XCTAssertEqual(head, [0x50, 0x4B, 0x03, 0x04], "本地头必须以 PK\\x03\\x04 开头")
        XCTAssertTrue(archive.range(of: Data([0x50, 0x4B, 0x05, 0x06])) != nil, "必须写 EOCD")
    }

    func testCRC32与已知值对齐() {
        // RFC 3285 附录里的标准测试值
        XCTAssertEqual(Crc32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(Crc32.checksum(Data()), 0x0000_0000)
    }

    func test空包也能往返() throws {
        let archive = Zip.write([])
        XCTAssertNoThrow(try Zip.read(archive))
        XCTAssertEqual(try Zip.read(archive).count, 0)
    }

    func test非zip数据报错而不是崩溃() {
        XCTAssertThrowsError(try Zip.read(Data("这不是 zip".utf8)))
    }
}

/// 批改 JSON 解析测试，逐条对齐安卓 FeedbackParserTest。
final class FeedbackParserTests: XCTestCase {

    private let valid = """
    {"总分":88,"分项":{"内容":23,"结构":22,"语言":22,"书写":21},
     "总评":"写得不错","优点":[{"位置":"第2段","内容":"妈妈笑了","为什么好":"有细节"}],
     "问题":[{"位置":"第1段","类型":"病句","原句":"他大约估计","问题说明":"语义重复","修改建议":"删掉大约"}],
     "改进建议":["加外貌描写","加动作","结尾呼应"],
     "好句升级":[{"原句":"妈妈笑了","改写":"妈妈的眼角弯了弯","为什么更好":"更具体"}],
     "同类范文片段":"示例片段"}
    """

    func test正常解析() throws {
        let fb = try XCTUnwrap(FeedbackParser.parse(valid))
        XCTAssertEqual(fb.totalScore, 88)
        XCTAssertEqual(fb.breakdownTotal, 88)
        XCTAssertEqual(fb.suggestions.count, 3)
        XCTAssertEqual(fb.strengths.first?.content, "妈妈笑了")
        XCTAssertEqual(fb.rewrites.first?.original, "妈妈笑了")
    }

    func test剥离三反引号json围栏() throws {
        let fb = try XCTUnwrap(FeedbackParser.parse("```json\n\(valid)\n```"))
        XCTAssertEqual(fb.totalScore, 88)
    }

    func test容忍前后夹杂说明文字() throws {
        let fb = try XCTUnwrap(FeedbackParser.parse("好的，以下是批改结果：\n\(valid)\n希望对你有帮助！"))
        XCTAssertEqual(fb.totalScore, 88)
    }

    func test缺字段用默认值不崩溃() throws {
        let fb = try XCTUnwrap(FeedbackParser.parse("{\"总分\": 70}"))
        XCTAssertEqual(fb.totalScore, 70)
        XCTAssertEqual(fb.breakdown.content, 0)
        XCTAssertTrue(fb.strengths.isEmpty)
    }

    func test分数写成字符串也能读出来() throws {
        let fb = try XCTUnwrap(FeedbackParser.parse("{\"总分\": \"92\", \"总评\": 好}"))
        XCTAssertEqual(fb.totalScore, 92)
    }

    func test彻底不是json时返回nil让调用方降级() {
        XCTAssertNil(FeedbackParser.parse(""))
        XCTAssertNil(FeedbackParser.parse("老师今天没空批改"))
    }
}

/// 存储层测试：历史窗口、僵尸占位清理、级联删除，都是安卓踩过的位置。
final class AppStoreTests: XCTestCase {

    private func makeStore() throws -> (AppStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-test-\(UUID().uuidString).json")
        return (AppStore(fileURL: url), url)
    }

    func test插入与按学科读取() throws {
        let (store, _) = try makeStore()
        store.insert(Message(subject: "math", role: "user", textContent: "题1"))
        store.insert(Message(subject: "chinese", role: "user", textContent: "题2"))
        XCTAssertEqual(store.messages(subject: "math").count, 1)
        XCTAssertEqual(store.messages(subject: "math").first?.textContent, "题1")
    }

    func test历史窗口只取最近十六条() throws {
        let (store, _) = try makeStore()
        for i in 0..<30 {
            store.insert(Message(
                subject: "math", role: i % 2 == 0 ? "user" : "assistant",
                textContent: "m\(i)", createdAt: 1_000 + i
            ))
        }
        XCTAssertEqual(store.recentMessages(subject: "math").count, 16)
        XCTAssertEqual(store.recentMessages(subject: "math").last?.textContent, "m29")
    }

    func test流式空占位在启动清理时被删掉() throws {
        let (store, _) = try makeStore()
        store.insert(Message(subject: "math", role: "assistant", textContent: "", isStreaming: true))
        store.insert(Message(subject: "math", role: "assistant", textContent: "半截答案", isStreaming: true))
        store.cleanupStale(subject: "math")
        let rows = store.messages(subject: "math")
        XCTAssertEqual(rows.count, 1, "空占位该被删掉")
        XCTAssertFalse(rows[0].isStreaming, "有内容的残留该定稿而不是继续转圈")
    }

    func test删消息级联删收藏() throws {
        let (store, _) = try makeStore()
        let msg = store.insert(Message(subject: "math", role: "assistant", textContent: "答案"))
        store.insert(Message(subject: "math", role: "user", textContent: "题"))
        XCTAssertNotNil(store.toggleFavorite(messageId: msg.id))
        XCTAssertEqual(store.favorites(subject: nil).count, 1)
        store.deleteMessage(id: msg.id)
        XCTAssertTrue(store.favorites(subject: nil).isEmpty, "原消息没了，收藏行不该留下")
    }

    func test收藏开关幂等() throws {
        let (store, _) = try makeStore()
        let msg = store.insert(Message(subject: "math", role: "assistant", textContent: "答案"))
        XCTAssertEqual(store.toggleFavorite(messageId: msg.id), true)
        XCTAssertEqual(store.toggleFavorite(messageId: msg.id), false)
        XCTAssertNil(store.toggleFavorite(messageId: 99_999), "不存在的不该凭空造一条")
    }

    func test落盘后可重新加载() throws {
        let (store, url) = try makeStore()
        store.insert(Message(subject: "math", role: "user", textContent: "题目"))
        let reopened = AppStore(fileURL: url)
        XCTAssertEqual(reopened.messages(subject: "math").count, 1)
        XCTAssertEqual(reopened.messages(subject: "math").first?.textContent, "题目")
    }

    func test时间分隔阈值与安卓一致() {
        let base = 1_700_000_000_000
        let rows = [
            Message(subject: "math", role: "user", textContent: "a", createdAt: base),
            Message(subject: "math", role: "user", textContent: "b", createdAt: base + 4 * 60 * 1000),
            Message(subject: "math", role: "user", textContent: "c", createdAt: base + 20 * 60 * 1000),
        ]
        XCTAssertTrue(AppStore.shouldShowTimestamp(rows, index: 0), "首条要显示时间")
        XCTAssertFalse(AppStore.shouldShowTimestamp(rows, index: 1), "间隔 4 分钟不显示")
        XCTAssertTrue(AppStore.shouldShowTimestamp(rows, index: 2), "间隔 16 分钟要显示")
    }
}
