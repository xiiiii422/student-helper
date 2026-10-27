import SwiftUI
import SHCore

/// 英语分类词汇速记：离线参考资料，放在「英语」页。
/// 与「句型语法」库互补——那个讲结构，这个讲「按主题背单词」，是小学最常见的话题词汇分类
/// （颜色 / 动物 / 食物 / 数字 / 身体 / 学校 / 天气 / 家庭成员）。
/// 每条是「一组主题词 + 中文 + 一句可用例句」，点「用这组词去写」把主题词带进「新建批改」。

// MARK: - 数据模型

struct VocabItem: Identifiable {
    let id: String   // 用英文作唯一 id
    let en: String
    let zh: String
}

struct VocabGroup: Identifiable {
    let id: Int
    let category: String
    /// 词语列表。
    let words: [VocabItem]
    /// 一句串起这组词的示范例句。
    let example: String

    var prompt: String {
        let list = words.map { "\($0.en)（\($0.zh)）" }.joined(separator: "、")
        return """
        【主题词汇练笔：\(category)】
        这组词：\(list)
        示范例句：\(example)
        试着用其中 3–5 个词写一小段话。
        """
    }
}

extension VocabGroup {
    static let all: [VocabGroup] = [
        VocabGroup(id: 6001, category: "颜色", words: [
            VocabItem(id: "red", en: "red", zh: "红色"), VocabItem(id: "orange", en: "orange", zh: "橙色"),
            VocabItem(id: "yellow", en: "yellow", zh: "黄色"), VocabItem(id: "green", en: "green", zh: "绿色"),
            VocabItem(id: "blue", en: "blue", zh: "蓝色"), VocabItem(id: "purple", en: "purple", zh: "紫色"),
            VocabItem(id: "black", en: "black", zh: "黑色"), VocabItem(id: "white", en: "white", zh: "白色"),
        ], example: "I have a red apple and a blue bag."),
        VocabGroup(id: 6002, category: "动物", words: [
            VocabItem(id: "cat", en: "cat", zh: "猫"), VocabItem(id: "dog", en: "dog", zh: "狗"),
            VocabItem(id: "bird", en: "bird", zh: "鸟"), VocabItem(id: "fish", en: "fish", zh: "鱼"),
            VocabItem(id: "rabbit", en: "rabbit", zh: "兔子"), VocabItem(id: "tiger", en: "tiger", zh: "老虎"),
            VocabItem(id: "elephant", en: "elephant", zh: "大象"), VocabItem(id: "panda", en: "panda", zh: "熊猫"),
        ], example: "The panda is black and white, and it is very cute."),
        VocabGroup(id: 6003, category: "食物", words: [
            VocabItem(id: "rice", en: "rice", zh: "米饭"), VocabItem(id: "noodles", en: "noodles", zh: "面条"),
            VocabItem(id: "egg", en: "egg", zh: "鸡蛋"), VocabItem(id: "bread", en: "bread", zh: "面包"),
            VocabItem(id: "apple", en: "apple", zh: "苹果"), VocabItem(id: "banana", en: "banana", zh: "香蕉"),
            VocabItem(id: "milk", en: "milk", zh: "牛奶"), VocabItem(id: "water", en: "water", zh: "水"),
        ], example: "I eat rice and an egg for breakfast."),
        VocabGroup(id: 6004, category: "数字", words: [
            VocabItem(id: "one", en: "one", zh: "一"), VocabItem(id: "two", en: "two", zh: "二"),
            VocabItem(id: "three", en: "three", zh: "三"), VocabItem(id: "four", en: "four", zh: "四"),
            VocabItem(id: "five", en: "five", zh: "五"), VocabItem(id: "ten", en: "ten", zh: "十"),
            VocabItem(id: "twelve", en: "twelve", zh: "十二"), VocabItem(id: "twenty", en: "twenty", zh: "二十"),
        ], example: "I have two apples and three bananas."),
        VocabGroup(id: 6005, category: "身体", words: [
            VocabItem(id: "head", en: "head", zh: "头"), VocabItem(id: "eye", en: "eye", zh: "眼睛"),
            VocabItem(id: "ear", en: "ear", zh: "耳朵"), VocabItem(id: "nose", en: "nose", zh: "鼻子"),
            VocabItem(id: "mouth", en: "mouth", zh: "嘴"), VocabItem(id: "hand", en: "hand", zh: "手"),
            VocabItem(id: "foot", en: "foot", zh: "脚"), VocabItem(id: "arm", en: "arm", zh: "手臂"),
        ], example: "I have two eyes and a small mouth."),
        VocabGroup(id: 6006, category: "学校", words: [
            VocabItem(id: "book", en: "book", zh: "书"), VocabItem(id: "pen", en: "pen", zh: "钢笔"),
            VocabItem(id: "pencil", en: "pencil", zh: "铅笔"), VocabItem(id: "ruler", en: "ruler", zh: "尺子"),
            VocabItem(id: "bag", en: "bag", zh: "书包"), VocabItem(id: "teacher", en: "teacher", zh: "老师"),
            VocabItem(id: "classroom", en: "classroom", zh: "教室"), VocabItem(id: "desk", en: "desk", zh: "书桌"),
        ], example: "The teacher is in the classroom with a book."),
        VocabGroup(id: 6007, category: "天气", words: [
            VocabItem(id: "sunny", en: "sunny", zh: "晴朗"), VocabItem(id: "rainy", en: "rainy", zh: "下雨"),
            VocabItem(id: "cloudy", en: "cloudy", zh: "多云"), VocabItem(id: "windy", en: "windy", zh: "有风"),
            VocabItem(id: "snowy", en: "snowy", zh: "下雪"), VocabItem(id: "hot", en: "hot", zh: "热"),
            VocabItem(id: "warm", en: "warm", zh: "温暖"), VocabItem(id: "cold", en: "cold", zh: "冷"),
        ], example: "It is sunny and warm today."),
        VocabGroup(id: 6008, category: "家庭成员", words: [
            VocabItem(id: "father", en: "father", zh: "父亲"), VocabItem(id: "mother", en: "mother", zh: "母亲"),
            VocabItem(id: "brother", en: "brother", zh: "兄弟"), VocabItem(id: "sister", en: "sister", zh: "姐妹"),
            VocabItem(id: "grandfather", en: "grandfather", zh: "爷爷"), VocabItem(id: "grandmother", en: "grandmother", zh: "奶奶"),
            VocabItem(id: "baby", en: "baby", zh: "婴儿"), VocabItem(id: "family", en: "family", zh: "家庭"),
        ], example: "My family has a father, a mother and a baby."),
    ]
}

// MARK: - 列表

struct EnglishVocabListView: View {
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    var body: some View {
        VStack(spacing: 0) {
            IosLargeTitle(
                title: "分类词汇",
                actions: AnyView(
                    IosTextButton(text: "去英语问问") { router.push(.essay) }
                )
            )
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(VocabGroup.all) { g in
                        VocabCard(group: g) { router.push(.vocabDetail(g.id)) }
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

private struct VocabCard: View {
    let group: VocabGroup
    let onOpen: () -> Void
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(group.category)
                        .font(HyperType.titleMedium)
                        .foregroundStyle(palette.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.textTertiary)
                }
                // 每行 4 个词
                let chunks = stride(from: 0, to: group.words.count, by: 4).map {
                    Array(group.words[$0..<min($0 + 4, group.words.count)])
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<chunks.count, id: \.self) { idx in
                        let row = chunks[idx]
                        HStack(spacing: 6) {
                            ForEach(row) { w in
                                VStack(alignment: .center, spacing: 2) {
                                    Text(w.en)
                                        .font(HyperType.bodyMedium)
                                        .foregroundStyle(palette.text)
                                    Text(w.zh)
                                        .font(HyperType.footnote)
                                        .foregroundStyle(palette.textTertiary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(HyperRadius.cardShape.fill(palette.background))
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(HyperRadius.cardShape.fill(palette.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 详情

struct EnglishVocabDetailView: View {
    let group: VocabGroup
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(group.category)
                    .font(HyperType.title2)
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)

                wordsBlock
                exampleBlock

                Button {
                    router.push(.compositionNewWithTemplate(
                        title: "主题词汇练笔：\(group.category)",
                        outline: group.prompt
                    ))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                        Text("用这组词去写")
                            .font(HyperType.titleMedium)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Hyper.miBlue))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.top, 4)
            }
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .background(palette.background)
        .navigationTitle(group.category)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var wordsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("词语")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            let chunks = stride(from: 0, to: group.words.count, by: 2).map {
                Array(group.words[$0..<min($0 + 2, group.words.count)])
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<chunks.count, id: \.self) { idx in
                    let row = chunks[idx]
                    HStack(spacing: 12) {
                        ForEach(row) { w in
                            HStack(spacing: 4) {
                                Text(w.en)
                                    .font(HyperType.bodyMedium)
                                    .foregroundStyle(palette.text)
                                Text(w.zh)
                                    .font(HyperType.footnote)
                                    .foregroundStyle(palette.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyperRadius.cardShape.fill(palette.card))
        .padding(.horizontal, 14)
    }

    private var exampleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("示范例句")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Text(group.example)
                .font(HyperType.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyperRadius.cardShape.fill(palette.card))
        .padding(.horizontal, 14)
    }
}
