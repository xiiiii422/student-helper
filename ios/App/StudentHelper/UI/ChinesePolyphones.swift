import SwiftUI
import SHCore

/// 多音字库：离线参考资料，放在「语文」页。
/// 与「易错字辨析」（形近/音近混写）、成语、古诗词互补——这个专讲「同一个字多个读音、意思不同」
/// （行/得/好/长/重/乐…）。小学常考「给加点字选读音」，每条列几个读音 + 义项 + 例词。

// MARK: - 数据模型

struct Polyphone: Identifiable {
    let id: Int
    let char: String
    /// 读音（拼音） + 义项 + 例词。
    let readings: [(pinyin: String, meaning: String, words: String)]
    /// 一句好记的小结。
    let tip: String

    var prompt: String {
        let lines = readings.map { "· \($0.pinyin)：\($0.meaning)（例：\($0.words)）" }.joined(separator: "\n")
        return """
        【多音字：\(char)】
        \(lines)
        小结：\(tip)
        """
    }
}

extension Polyphone {
    static let all: [Polyphone] = [
        Polyphone(id: 10001, char: "行", readings: [
            ("xíng", "走、可以", "行走、不行"),
            ("háng", "排、职业", "银行、一行字"),
        ], tip: "走路读 xíng，排成一行 / 行业读 háng。"),
        Polyphone(id: 10002, char: "得", readings: [
            ("dé", "拿到、能够", "得到、得意"),
            ("de", "补语标记", "跑得快、写得真好"),
            ("děi", "必须", "得去、还得等"),
        ], tip: "实义「得到」读 dé；补语「跑得快」读 de；「必须」读 děi。"),
        Polyphone(id: 10003, char: "好", readings: [
            ("hǎo", "优良、便于", "好人、好学"),
            ("hào", "喜爱", "爱好、好奇"),
        ], tip: "形容词「好」读 hǎo；动词「喜爱」读 hào（好读书）。"),
        Polyphone(id: 10004, char: "长", readings: [
            ("cháng", "短的反义、久远", "长短、很长"),
            ("zhǎng", "生长、辈分高", "长大、长辈"),
        ], tip: "长度读 cháng；生长 / 长辈读 zhǎng。"),
        Polyphone(id: 10005, char: "重", readings: [
            ("zhòng", "分量、要紧", "重要、体重"),
            ("chóng", "再、层叠", "重复、重来"),
        ], tip: "分量、重要读 zhòng；再一层读 chóng（重写）。"),
        Polyphone(id: 10006, char: "乐", readings: [
            ("lè", "高兴", "快乐、乐园"),
            ("yuè", "音乐", "音乐、乐器"),
        ], tip: "高兴读 lè；音乐读 yuè。"),
        Polyphone(id: 10007, char: "地", readings: [
            ("dì", "土地、地方", "大地、地点"),
            ("de", "状语标记", "高兴地笑、慢慢地走"),
        ], tip: "名词「土地」读 dì；状语「地」读 de。"),
        Polyphone(id: 10008, char: "发", readings: [
            ("fā", "送出、产生", "发现、出发"),
            ("fà", "头发", "头发、白发"),
        ], tip: "动作「发出」读 fā；「头发」读 fà。"),
        Polyphone(id: 10009, char: "空", readings: [
            ("kōng", "没有东西", "天空、空气"),
            ("kòng", "闲、腾出", "空地、有空"),
        ], tip: "天空读 kōng；闲着的读 kòng（填空）。"),
        Polyphone(id: 10010, char: "还", readings: [
            ("hái", "仍旧、更", "还在、还好"),
            ("huán", "归还", "还书、归还"),
        ], tip: "副词「还有」读 hái；「归还」读 huán。"),
        Polyphone(id: 10011, char: "便", readings: [
            ("biàn", "方便、就", "方便、便条"),
            ("pián", "便宜", "便宜"),
        ], tip: "方便读 biàn；「便宜」读 pián。"),
        Polyphone(id: 10012, char: "背", readings: [
            ("bēi", "用脊背驮", "背书包"),
            ("bèi", "脊背、背诵", "背后、背书"),
        ], tip: "动作「背东西」读 bēi；身体部位 / 背诵读 bèi。"),
        Polyphone(id: 10013, char: "场", readings: [
            ("chǎng", "场所、量词", "操场、一场雨"),
            ("cháng", "晒粮平地、集", "打场、场院"),
        ], tip: "一般场所读 chǎng；农事「打场」读 cháng。"),
        Polyphone(id: 10014, char: "都", readings: [
            ("dōu", "全、已经", "都是、都来了"),
            ("dū", "大城市", "首都、都市"),
        ], tip: "副词「都」读 dōu；「首都」读 dū。"),
        Polyphone(id: 10015, char: "觉", readings: [
            ("jué", "感到、醒悟", "觉得、觉悟"),
            ("jiào", "睡眠", "睡觉"),
        ], tip: "感知读 jué；睡眠读 jiào（睡觉）。"),
        Polyphone(id: 10016, char: "数", readings: [
            ("shù", "数目", "数学、数字"),
            ("shǔ", "清点", "数一数、数不清"),
            ("shuò", "屡次（成语）", "频数"),
        ], tip: "名词「数目」读 shù；动词「数数」读 shǔ。"),
    ]
}

// MARK: - 列表

struct PolyphoneListView: View {
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    var body: some View {
        VStack(spacing: 0) {
            IosLargeTitle(
                title: "多音字",
                actions: AnyView(
                    IosTextButton(text: "去语文问问") { router.push(.essay) }
                )
            )
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Polyphone.all) { p in
                        PolyphoneRow(polyphone: p) { router.push(.polyphoneDetail(p.id)) }
                    }
                    .padding(.horizontal, 14)
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
        .background(palette.background)
    }
}

private struct PolyphoneRow: View {
    let polyphone: Polyphone
    let onOpen: () -> Void
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Text(polyphone.char)
                    .font(HyperType.title2)
                    .foregroundStyle(palette.text)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Hyper.chinese.opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        ForEach(polyphone.readings, id: \.pinyin) { r in
                            Text(r.pinyin)
                                .font(HyperType.bodyMedium)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    Text(polyphone.tip)
                        .font(HyperType.footnote)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(14)
            .background(HyperRadius.cardShape.fill(palette.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 详情

struct PolyphoneDetailView: View {
    let polyphone: Polyphone
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(polyphone.char)
                    .font(HyperType.title2)
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)

                readingsBlock

                Button {
                    router.push(.compositionNewWithTemplate(
                        title: "多音字练写：\(polyphone.char)",
                        outline: polyphone.prompt
                    ))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                        Text("用这个字去写")
                            .font(HyperType.titleMedium)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Hyper.miBlue))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 24)
        }
        .background(palette.background)
        .navigationTitle("多音字")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var readingsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("不同读音")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(polyphone.readings, id: \.pinyin) { r in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.pinyin)
                            .font(HyperType.titleMedium)
                            .foregroundStyle(Hyper.chinese)
                        Text(r.meaning)
                            .font(HyperType.bodyMedium)
                            .foregroundStyle(palette.text)
                        Text("例：\(r.words)")
                            .font(HyperType.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyperRadius.cardShape.fill(palette.card))
        .padding(.horizontal, 14)
    }
}
