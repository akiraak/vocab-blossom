import Foundation
import SwiftData
import Testing

@testable import VocabBlossom

/// 通信のスタブ。テストは並列に走るので、セッションごとのトークン（ヘッダ）で返し方を引き分ける
nonisolated final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest, Data) -> (status: Int, body: Data)

    static let tokenHeader = "X-Stub-Token"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var headersByToken: [String: [String: String]] = [:]

    /// headers は応答に足すヘッダ（既定は Content-Type: application/json だけ）
    static func session(headers: [String: String] = [:], handler: @escaping Handler) -> URLSession {
        let token = UUID().uuidString
        lock.withLock {
            handlers[token] = handler
            headersByToken[token] = headers
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [tokenHeader: token]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let token = request.value(forHTTPHeaderField: Self.tokenHeader) ?? ""
        let extraHeaders = Self.lock.withLock { Self.headersByToken[token] ?? [:] }
        guard let handler = Self.lock.withLock({ Self.handlers[token] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (status, body) = handler(request, Self.body(of: request))
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"].merging(extraHeaders) { _, new in new }
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession は本文をストリームに変えて渡すので読み直す
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// 送られてきたリクエストを貯める（スタブのハンドラは別スレッドで呼ばれる）
nonisolated final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(URLRequest, SyncAPI.Request)] = []

    func append(_ request: URLRequest, _ body: Data) {
        let decoded = try? SyncAPI.decoder.decode(SyncAPI.Request.self, from: body)
        lock.withLock { items.append((request, decoded ?? SyncAPI.Request(
            cursor: -1, groups: [], customWords: [], deletions: []
        ))) }
    }

    var requests: [URLRequest] { lock.withLock { items.map(\.0) } }
    var bodies: [SyncAPI.Request] { lock.withLock { items.map(\.1) } }
}

nonisolated private func encode(_ response: SyncAPI.Response) -> Data {
    (try? SyncAPI.encoder.encode(response)) ?? Data()
}

private let config = ServerConfig(baseURL: URL(string: "https://vocab.example.com")!, apiKey: "secret")

@Suite("同期: サーバーの設定")
struct ServerConfigTests {
    @Test("BASE_URL と API_KEY が入っていれば使う")
    func validDictionary() throws {
        let config = try #require(
            ServerConfig(dictionary: ["BASE_URL": " https://vocab.chobi.me ", "API_KEY": "abc"])
        )
        #expect(config.baseURL.absoluteString == "https://vocab.chobi.me")
        #expect(config.apiKey == "abc")
        #expect(config.displayHost == "vocab.chobi.me")
        #expect(config.url(path: "api/sync").absoluteString == "https://vocab.chobi.me/api/sync")
    }

    @Test("値が空・URL でない・http(s) でなければ使わない")
    func invalidDictionary() {
        #expect(ServerConfig(dictionary: [:]) == nil)
        #expect(ServerConfig(dictionary: ["BASE_URL": "https://vocab.chobi.me", "API_KEY": ""]) == nil)
        #expect(ServerConfig(dictionary: ["BASE_URL": "", "API_KEY": "abc"]) == nil)
        #expect(ServerConfig(dictionary: ["BASE_URL": "ftp://vocab.chobi.me", "API_KEY": "abc"]) == nil)
    }

    @Test("テストの実行中・ダミーデータの起動中・ダミーデータを入れた端末では同期しない")
    func disabledInTestsAndDemo() throws {
        #expect(SyncService.appConfig(environment: ["XCTestConfigurationFilePath": "/x"]) == nil)
        #expect(SyncService.appConfig(environment: ["VOCAB_SEED_DEMO": "1"]) == nil)
        let defaults = try #require(UserDefaults(suiteName: "sync-config-\(UUID().uuidString)"))
        defaults.set(true, forKey: SyncService.Key.disabledByDebugSeed)
        #expect(SyncService.appConfig(environment: [:], defaults: defaults) == nil)
    }
}

@Suite("同期: 通信と状態")
struct SyncServiceTests {
    let context: ModelContext
    let defaults: UserDefaults
    let editor: GroupEditor

    init() throws {
        let container = try ModelContainer(
            for: AppModel.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        defaults = UserDefaults(suiteName: "sync-tests-\(UUID().uuidString)")!
        editor = GroupEditor(context: context)
    }

    @Test("接続先が無ければ通信しない")
    func disabledWithoutConfig() async {
        let log = RequestLog()
        let session = StubURLProtocol.session { request, body in
            log.append(request, body)
            return (200, Data())
        }
        let service = SyncService(config: nil, context: context, defaults: defaults, session: session)

        await service.syncNow()

        #expect(!service.isEnabled)
        #expect(log.requests.isEmpty)
        #expect(service.lastSyncedAt == nil)
    }

    @Test("Bearer つきで送り、受け取った cursor を次に使う")
    func sendsAndStoresCursor() async throws {
        let group = editor.createGroup(name: "Unit 1")
        let log = RequestLog()
        let session = StubURLProtocol.session { request, body in
            log.append(request, body)
            let sent = (try? SyncAPI.decoder.decode(SyncAPI.Request.self, from: body))
            return (200, encode(SyncAPI.Response(
                cursor: 7, reset: false, groups: sent?.groups ?? [], customWords: [], deletions: []
            )))
        }
        let service = SyncService(config: config, context: context, defaults: defaults, session: session)

        await service.syncNow()
        await service.syncNow()

        let request = try #require(log.requests.first)
        #expect(request.url?.absoluteString == "https://vocab.example.com/api/sync")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(log.bodies.map(\.cursor) == [0, 7])
        #expect(log.bodies.first?.groups.map(\.id) == [group.id.syncId])
        // 2 回目は変更が無いので何も送らない
        #expect(log.bodies.last?.groups.isEmpty == true)
        #expect(service.lastSyncedAt != nil)
        #expect(service.lastError == nil)
        #expect(!group.needsSync)
    }

    @Test("認証に失敗したらエラーを出し、手元のデータはそのまま")
    func unauthorized() async throws {
        let group = editor.createGroup(name: "Unit 1")
        let session = StubURLProtocol.session { _, _ in (401, Data(#"{"error":"unauthorized"}"#.utf8)) }
        let service = SyncService(config: config, context: context, defaults: defaults, session: session)

        await service.syncNow()

        #expect(service.lastError == SyncError.unauthorized.errorDescription)
        #expect(service.lastSyncedAt == nil)
        #expect(group.needsSync)
        #expect(try context.fetch(FetchDescriptor<WordGroup>()).count == 1)
    }

    @Test("サーバーが作り直されていたら（reset）全件を送り直す")
    func resetResendsEverything() async {
        editor.createGroup(name: "Unit 1")
        defaults.set(config.baseURL.absoluteString, forKey: SyncService.Key.server)
        defaults.set(50, forKey: SyncService.Key.cursor)
        let log = RequestLog()
        let session = StubURLProtocol.session { request, body in
            log.append(request, body)
            let sent = (try? SyncAPI.decoder.decode(SyncAPI.Request.self, from: body))
            // 1 回目: cursor 50 はサーバーより新しい → reset
            let reset = sent?.cursor == 50
            return (200, encode(SyncAPI.Response(
                cursor: 3, reset: reset, groups: sent?.groups ?? [], customWords: [], deletions: []
            )))
        }
        let service = SyncService(config: config, context: context, defaults: defaults, session: session)

        await service.syncNow()

        #expect(log.bodies.map(\.cursor) == [50, 3])
        #expect(log.bodies.map(\.groups.count) == [1, 1])
    }

    @Test("接続先が変わったら cursor を 0 に戻して全件を送り直す")
    func serverChangeResetsCursor() async {
        let group = editor.createGroup(name: "Unit 1")
        group.syncedUpdatedAt = group.updatedAt
        defaults.set("https://old.example.com", forKey: SyncService.Key.server)
        defaults.set(20, forKey: SyncService.Key.cursor)
        let log = RequestLog()
        let session = StubURLProtocol.session { request, body in
            log.append(request, body)
            return (200, encode(SyncAPI.Response(
                cursor: 1, reset: false, groups: [], customWords: [], deletions: []
            )))
        }
        let service = SyncService(config: config, context: context, defaults: defaults, session: session)

        await service.syncNow()

        #expect(log.bodies.first?.cursor == 0)
        #expect(log.bodies.first?.groups.count == 1)
        #expect(defaults.string(forKey: SyncService.Key.server) == config.baseURL.absoluteString)
    }

    @Test("グループを変えると少し待ってから 1 回にまとめて同期する")
    func changeTriggersDebouncedSync() async throws {
        let log = RequestLog()
        let session = StubURLProtocol.session { request, body in
            log.append(request, body)
            let sent = (try? SyncAPI.decoder.decode(SyncAPI.Request.self, from: body))
            return (200, encode(SyncAPI.Response(
                cursor: 1, reset: false, groups: sent?.groups ?? [], customWords: [], deletions: []
            )))
        }
        let service = SyncService(
            config: config, context: context, defaults: defaults, session: session,
            debounce: .milliseconds(50)
        )
        service.startObservingChanges()

        let group = editor.createGroup(name: "Unit 1")
        editor.rename(group, to: "Unit 2")
        for _ in 0..<100 where log.requests.isEmpty || service.isSyncing {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(log.bodies.count == 1)
        #expect(log.bodies.first?.groups.map(\.name) == ["Unit 2"])
        #expect(!group.needsSync)
    }
}
