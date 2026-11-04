import Foundation
import Observation

/// 穴埋めを始める前に、端末に文章の無い語の分をサーバーで作ってもらう。作る画面（`PassagePreparationView`）の中身。
///
/// 3 語ずつ、3 本まで並べて送る（サーバーは 1 回 5 語まで。1 回の AI の呼び出しが短く済み、進み具合もこまめに出せる）。
/// 一部の語が作れなくても続ける（その語は例文で出す）。すべて失敗したときだけ `failed` にする
@MainActor
@Observable
final class PassagePreparation {
    static let wordsPerRequest = 3
    static let parallelRequests = 3

    enum Phase: Equatable {
        case working
        /// 作り終えた。`failedCount` は文章が作れなかった語（例文で出す）
        case finished(failedCount: Int)
        /// 1 語も作れなかった（通信できない・サーバーのエラーなど）
        case failed(message: String)
    }

    struct Item: Identifiable, Equatable {
        enum State: Equatable { case waiting, done, failed }

        let id: String
        let word: String
        /// 意味が複数ある語は意味を添えて見分ける
        let detail: String?
        var state: State = .waiting
    }

    let requests: [PassageAPI.Word]
    private(set) var items: [Item]
    private(set) var phase: Phase = .working

    init(requests: [PassageAPI.Word]) {
        self.requests = requests
        let multiSense = Dictionary(grouping: requests) { Self.wordId(of: $0) }.filter { $0.value.count > 1 }
        items = requests.map { request in
            let detail = multiSense[Self.wordId(of: request)] != nil ? request.meaning : nil
            return Item(id: request.id, word: request.word, detail: detail)
        }
    }

    /// 「単語 ID#意味の番号」の単語 ID
    private static func wordId(of request: PassageAPI.Word) -> String {
        request.id.split(separator: "#").first.map(String.init) ?? request.id
    }

    var total: Int { items.count }
    var doneCount: Int { items.count { $0.state != .waiting } }
    var progress: Double { total > 0 ? Double(doneCount) / Double(total) : 1 }

    /// 文章の無い語・意味の一覧（意味ごとに 1 件。id は「単語 ID#意味の番号」）
    nonisolated static func missingWords(_ words: [WordEntry], cache: PassageCache) -> [PassageAPI.Word] {
        words.flatMap { word in
            word.senses.enumerated().compactMap { index, sense -> PassageAPI.Word? in
                guard !cache.contains(word: word.word, sense: sense) else { return nil }
                return PassageAPI.Word(
                    id: "\(word.id)#\(index)", word: word.word, pos: sense.pos,
                    meaning: sense.meaning, example: sense.example
                )
            }
        }
    }

    func run(fetcher: any PassageFetching, cache: PassageCache) async {
        phase = .working
        for index in items.indices { items[index].state = .waiting }

        let chunks = stride(from: 0, to: requests.count, by: Self.wordsPerRequest).map {
            Array(requests[$0..<min($0 + Self.wordsPerRequest, requests.count)])
        }
        var firstError: (any Error)?

        typealias ChunkResult = (chunk: [PassageAPI.Word], result: Result<[PassageAPI.Result], any Error>)
        await withTaskGroup(of: ChunkResult.self) { group in
            var next = 0
            func addNext() {
                guard next < chunks.count else { return }
                let chunk = chunks[next]
                next += 1
                group.addTask {
                    do {
                        return (chunk, .success(try await fetcher.fetch(chunk)))
                    } catch {
                        return (chunk, .failure(error))
                    }
                }
            }
            for _ in 0..<Self.parallelRequests { addNext() }

            for await (chunk, result) in group {
                switch result {
                case .success(let results):
                    var toStore: [String: [Passage]] = [:]
                    for request in chunk {
                        let passages = results.first { $0.id == request.id }?.passages ?? []
                        if !passages.isEmpty {
                            let sense = WordSense(pos: request.pos, meaning: request.meaning)
                            toStore[Passages.key(word: request.word, sense: sense)] = passages
                        }
                        mark(request.id, passages.isEmpty ? .failed : .done)
                    }
                    cache.store(toStore)
                case .failure(let error):
                    firstError = firstError ?? error
                    for request in chunk { mark(request.id, .failed) }
                }
                addNext()
            }
        }

        let failedCount = items.count { $0.state == .failed }
        if failedCount == items.count, let firstError {
            phase = .failed(message: firstError.localizedDescription)
        } else {
            phase = .finished(failedCount: failedCount)
        }
    }

    private func mark(_ id: String, _ state: Item.State) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = state
    }
}
