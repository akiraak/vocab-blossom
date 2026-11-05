import Foundation

/// グループの読み上げの声（`POST /api/speech`）の型。設計は docs/plans/read-aloud-gemini-voice.md
nonisolated enum SpeechAPI {
    /// 読む人。Chobi（先生役・Leda）と Naruko（仲間の生徒役・Aoede）
    enum Speaker: String, Codable, CaseIterable, Sendable {
        case chobi
        case naruko
    }

    /// 文の種類。サーバーが種類ごとに話し方（スタイル）を変える
    enum Kind: String, Codable, Sendable {
        case word
        case example
        case japanese
    }

    /// 端末に残す音声の鍵にもなる（モデル・人・種類・文が同じなら同じ音声）
    struct Request: Encodable, Hashable, Sendable {
        var text: String
        var speaker: Speaker
        var kind: Kind
        var model: TTSModel
    }

    /// サーバーが返す 1 文分の音声
    struct Audio: Sendable {
        /// WAV（24kHz mono 16bit）
        var wav: Data
        /// モデル・声・スタイルの版。サーバーで話し方を直すと変わる（端末に残した音声の鍵に使う）
        var version: String
    }
}

/// 1 文の音声を取ってくる。本番は `SpeechClient`、テストと画面確認は偽物
protocol SpeechFetching: Sendable {
    func fetch(_ request: SpeechAPI.Request) async throws -> SpeechAPI.Audio
}

/// `POST /api/speech` を呼ぶ。エラーは AI チェックと同じ `WordAssistError` で返す
nonisolated struct SpeechClient: SpeechFetching {
    static let path = "api/speech"
    static let versionHeader = "x-speech-version"
    /// 1 文の生成は 2〜3.5 秒（実測）。待ちすぎると読み上げが止まって見えるので、早めにあきらめて内蔵の声で読む
    static let timeout: TimeInterval = 20

    let config: ServerConfig
    let session: URLSession

    init(config: ServerConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func fetch(_ request: SpeechAPI.Request) async throws -> SpeechAPI.Audio {
        var urlRequest = URLRequest(url: config.url(path: Self.path), timeoutInterval: Self.timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("audio/wav", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw WordAssistError.offline
            default:
                throw WordAssistError.network(error.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else { throw WordAssistError.invalidResponse }
        if let error = WordAssistClient.error(forStatus: http.statusCode) { throw error }
        guard let version = http.value(forHTTPHeaderField: Self.versionHeader), !version.isEmpty,
              data.count > 44
        else { throw WordAssistError.invalidResponse }
        return SpeechAPI.Audio(wav: data, version: version)
    }
}
