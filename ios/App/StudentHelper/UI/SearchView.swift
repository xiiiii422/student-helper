import SwiftUI
import SHCore

/// 历史搜索页：以前找一道旧题只能按学科一条条翻，问过的题多了根本找不到。
/// 搜索逻辑（大小写不敏感、按时间倒序、空查询返回空）全在 SHCore.AppStore，
/// 这里只负责展示。
struct SearchView: View {
    @StateObject private var vm: SearchViewModel
    /// 点一条结果时回调（切到对应学科）。VM 由 @StateObject 持有，
    /// 不能从外部每次 body 重算时新建——那样每帧都在造对象。
    var openSubject: (String) -> Void = { _ in }

    init(store: AppStore, openSubject: @escaping (String) -> Void = { _ in }) {
        _vm = StateObject(wrappedValue: SearchViewModel(store: store))
        self.openSubject = openSubject
    }

    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router
    @State private var filter: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                searchField

                if !vm.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    HStack(spacing: 8) {
                        chip("全部", selected: filter == nil) { filter = nil }
                        ForEach(["chinese", "math", "english"], id: \.self) { subject in
                            let count = vm.count(subject: subject)
                            chip(
                                count > 0 ? "\(SubjectLabel.of(subject)) \(count)" : SubjectLabel.of(subject),
                                selected: filter == subject
                            ) { filter = subject }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                }

                if vm.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    hintState
                } else if vm.results(filter: filter).isEmpty {
                    emptyState
                } else {
                    ForEach(vm.results(filter: filter)) { row in
                        resultCard(row)
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .background(palette.background)
        .navigationTitle("搜题历史")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.textTertiary)
            TextField("搜索问过的题目", text: $vm.query)
                .font(HyperType.body)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !vm.query.isEmpty {
                Button { vm.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(HyperRadius.cardShape.fill(palette.card))
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var hintState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(palette.textTertiary)
            Text("输入关键词，比如「分数」「圆的面积」")
                .font(HyperType.bodyMedium)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(palette.textTertiary)
            Text("没搜到「\(vm.query)」相关的题目")
                .font(HyperType.bodyMedium)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func resultCard(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(SubjectColor.forSubject(message.subject))
                    .frame(width: 6, height: 6)
                Text(SubjectLabel.of(message.subject))
                    .font(HyperType.footnote)
                    .foregroundStyle(palette.textSecondary)
                Text(Timestamp.format(message.createdAt))
                    .font(HyperType.footnote)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }
            Text(message.textContent)
                .font(HyperType.bodyMedium)
                .foregroundStyle(palette.text)
                .lineLimit(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyperRadius.cardShape.fill(palette.card))
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            // 点一条跳回对应学科，学生能接着往下看完整问答
            router.popToRoot()
            openSubject(message.subject)
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(HyperType.bodyMedium)
                .foregroundStyle(selected ? Hyper.miBlue : palette.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? Hyper.miBlue.opacity(0.12) : palette.card))
        }
        .buttonStyle(.plain)
    }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = "" { didSet { if query != oldValue { reload() } } }
    @Published private(set) var hits: [Message] = []

    private let store: AppStore

    init(store: AppStore) {
        self.store = store
        reload()
    }
    private func reload() {
        hits = store.searchMessages(query: query)
    }

    func results(filter: String?) -> [Message] {
        guard let filter else { return hits }
        return hits.filter { $0.subject == filter }
    }

    func count(subject: String) -> Int {
        store.searchSubjectCounts(query: query)[subject] ?? 0
    }
}
