import Foundation

/// 「単語を追加」画面の状態。検索結果の選択、AI で調べた結果（単語帳の語・新しく作る語）、確定で行う処理を持つ。
///
/// 1 画面の中で、検索 → 選ぶ（無ければ AI で調べて選ぶ）→「追加」で終わらせるため、
/// 新しく作る語も確定まではまだ自作語にせず、下書きのまま選択に並べる。画面から切り離して単体テストできるようにしている。
struct WordAddSession: Equatable {
    /// 選んだもの。単語帳の語（同梱語 + 自作語）か、新しく作る語の下書き
    enum Pick: Hashable {
        case word(String)
        case newWord(UUID)
    }

    /// AI が単語帳の語を案内した候補（打ち間違い・変化形・日本語からなど）
    struct SuggestedWord: Equatable, Identifiable {
        let id: String
        let reason: WordAssistAPI.Reason
    }

    /// 新しく作る語の下書き。AI の候補か、自分で作ったもの
    struct NewWord: Equatable, Identifiable {
        let id: UUID
        var draft: GroupEditor.WordDraft
        var reason: WordAssistAPI.Reason?

        init(id: UUID = UUID(), draft: GroupEditor.WordDraft, reason: WordAssistAPI.Reason?) {
            self.id = id
            self.draft = draft
            self.reason = reason
        }

        init(candidate: WordAssistAPI.Candidate) {
            let draft = GroupEditor.WordDraft().applying(candidate, onlyEmpty: false)
            self.init(draft: draft, reason: candidate.reason)
        }

        /// 同じ綴り・品詞の候補か
        func matches(_ candidate: WordAssistAPI.Candidate) -> Bool {
            draft.trimmed.word == candidate.word && draft.pos == candidate.pos
        }
    }

    /// AI で調べた状態。`text` は AI に送った文字列
    enum Assist: Equatable {
        case idle
        case loading(text: String)
        case done(text: String)
        case failed(text: String, message: String)

        var text: String? {
            switch self {
            case .idle: nil
            case .loading(let text), .done(let text), .failed(let text, _): text
            }
        }
    }

    /// 開いた時点でグループに入っている語。選択には含めず「追加済み」として出す
    let addedIds: Set<String>
    /// 選んだ順
    private(set) var picks: [Pick] = []
    private(set) var assist: Assist = .idle
    /// 最後に調べた AI の結果のうち、単語帳にある語
    private(set) var suggestedWords: [SuggestedWord] = []
    /// 新しく作る語。最後に調べた AI の候補と、選んだまま残っている下書き
    private(set) var newWords: [NewWord] = []

    init(addedIds: some Sequence<String>) {
        self.addedIds = Set(addedIds)
    }

    // MARK: - 選択

    var pickCount: Int { picks.count }

    func isAdded(_ wordId: String) -> Bool { addedIds.contains(wordId) }

    func isSelected(_ pick: Pick) -> Bool { picks.contains(pick) }

    /// 付け外しする。追加済みの語は選べない
    mutating func toggle(_ pick: Pick) {
        if let index = picks.firstIndex(of: pick) {
            picks.remove(at: index)
        } else {
            select(pick)
        }
    }

    /// 選択に加える（すでに選んでいる・追加済みなら何もしない）
    mutating func select(_ pick: Pick) {
        if case .word(let wordId) = pick, isAdded(wordId) { return }
        if case .newWord(let id) = pick, !newWords.contains(where: { $0.id == id }) { return }
        guard !picks.contains(pick) else { return }
        picks.append(pick)
    }

    // MARK: - AI で調べる

    mutating func startAssist(text: String) {
        assist = .loading(text: text)
    }

    /// AI の結果を受け取る。調べている最中の文字列と違う（あとから別の語で調べ直した）なら捨てる。
    ///
    /// 前の結果のうち選んでいない下書きは消し、選んだ下書きは残す。入力どおりの綴りで単語帳に無い語が返れば、
    /// 最初の 1 つを選んでおく（そのまま「追加」を押せば済むように）
    mutating func finishAssist(text: String, candidates: [WordAssistAPI.Candidate]) {
        guard assist == .loading(text: text) else { return }
        assist = .done(text: text)
        suggestedWords = candidates.compactMap { candidate in
            candidate.bundled.map { SuggestedWord(id: $0.id, reason: candidate.reason) }
        }
        let kept = newWords.filter { isSelected(.newWord($0.id)) }
        let fresh = candidates
            .filter { $0.bundled == nil }
            // 同じ候補を選んだまま調べ直したときに 2 つ並ばないように
            .filter { candidate in !kept.contains { $0.matches(candidate) } }
            .map(NewWord.init(candidate:))
        newWords = kept + fresh
        if let first = candidates.first, first.reason == .exact, first.bundled == nil,
           let created = fresh.first(where: { $0.matches(first) }) {
            select(.newWord(created.id))
        }
    }

    mutating func failAssist(text: String, message: String) {
        guard assist == .loading(text: text) else { return }
        assist = .failed(text: text, message: message)
    }

    // MARK: - 新しく作る語

    /// 自分で作った下書きを足して選ぶ
    mutating func addNewWord(_ draft: GroupEditor.WordDraft) {
        let newWord = NewWord(draft: draft, reason: nil)
        newWords.append(newWord)
        select(.newWord(newWord.id))
    }

    /// 下書きを直す。直したら選んだことにする
    mutating func updateNewWord(_ id: UUID, with draft: GroupEditor.WordDraft) {
        guard let index = newWords.firstIndex(where: { $0.id == id }) else { return }
        newWords[index].draft = draft
        select(.newWord(id))
    }

    /// 下書きの代わりに単語帳の語を選ぶ（エディタで同じ綴りの同梱語を案内されたとき）
    mutating func replaceNewWord(_ id: UUID, withWord wordId: String) {
        let pick = Pick.newWord(id)
        if let index = picks.firstIndex(of: pick) {
            picks.remove(at: index)
        }
        newWords.removeAll { $0.id == id }
        select(.word(wordId))
    }

    // MARK: - 確定

    /// 選んだ順に、新しく作る語は `createCustomWord` で自作語にして、グループの末尾に足す語の ID を返す
    func commit(createCustomWord: (GroupEditor.WordDraft) -> String) -> [String] {
        picks.compactMap { pick in
            switch pick {
            case .word(let wordId):
                return wordId
            case .newWord(let id):
                guard let newWord = newWords.first(where: { $0.id == id }), newWord.draft.isValid else {
                    return nil
                }
                return createCustomWord(newWord.draft)
            }
        }
    }
}
