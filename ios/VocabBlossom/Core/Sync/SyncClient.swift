import Foundation

/// 同期の通信で起きたこと。設定画面にそのまま出せる文にする
enum SyncError: LocalizedError, Equatable {
    /// API キーが違う（サーバーの `API_SHARED_SECRET` と `ServerConfig.plist` の `API_KEY`）
    case unauthorized
    case server(status: Int)
    case invalidResponse
    case offline
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "サーバーに認証されませんでした（API キーを確認してください）"
        case .server(let status):
            "サーバーでエラーが起きました（\(status)）"
        case .invalidResponse:
            "サーバーの返事を読み取れませんでした"
        case .offline:
            "インターネットにつながっていません"
        case .network(let detail):
            "サーバーにつながりませんでした（\(detail)）"
        }
    }
}

/// `POST /api/sync` を呼ぶ。テストでは `URLProtocol` のスタブを入れた `URLSession` を渡す
struct SyncClient {
    static let path = "api/sync"
    static let timeout: TimeInterval = 20

    let config: ServerConfig
    let session: URLSession

    func sync(_ body: SyncAPI.Request) async throws -> SyncAPI.Response {
        var request = URLRequest(url: config.url(path: Self.path), timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try SyncAPI.encoder.encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw SyncError.offline
            default:
                throw SyncError.network(error.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else { throw SyncError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw SyncError.unauthorized
        default:
            throw SyncError.server(status: http.statusCode)
        }
        do {
            return try SyncAPI.decoder.decode(SyncAPI.Response.self, from: data)
        } catch {
            throw SyncError.invalidResponse
        }
    }
}
