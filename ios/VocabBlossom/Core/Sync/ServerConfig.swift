import Foundation

/// 管理画面サーバーの接続先。`Resources/ServerConfig.plist`（git 管理外）から読む。
///
/// ファイルが無い・値が空なら nil を返し、アプリはサーバーを使わずに今までどおり動く。
/// 書式は `Resources/ServerConfig.example.plist` を参照。
nonisolated struct ServerConfig: Equatable, Sendable {
    let baseURL: URL
    let apiKey: String

    static let fileName = "ServerConfig"

    init(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    /// plist の中身から作る。`BASE_URL` は http / https の URL、`API_KEY` は空でないこと
    init?(dictionary: [String: Any]) {
        let base = (dictionary["BASE_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = (dictionary["API_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty,
              let url = URL(string: base),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host() != nil
        else { return nil }
        self.init(baseURL: url, apiKey: key)
    }

    static func load(bundle: Bundle = .main) -> ServerConfig? {
        guard let url = bundle.url(forResource: fileName, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any]
        else { return nil }
        return ServerConfig(dictionary: dictionary)
    }

    /// 設定画面に出す接続先（ホスト名）
    var displayHost: String {
        baseURL.host() ?? baseURL.absoluteString
    }

    func url(path: String) -> URL {
        baseURL.appending(path: path)
    }
}
