import Foundation
import Observation
import SwiftData

/// 管理画面サーバーとの同期を回す。同時に走るのは 1 本だけで、走っている間に頼まれたら終わってからもう 1 回だけ回す。
///
/// 同期するタイミング（呼ぶのは画面側）
/// - 起動時・アプリに戻ったとき（`VocabBlossomApp` の `scenePhase`）
/// - グループ・自作語を変えた少しあと（`GroupEditor` の保存の通知 → `scheduleSoon`）
/// - グループ一覧の引っ張って更新・設定画面の「今すぐ同期」
///
/// 接続先が無ければ（`ServerConfig.plist` が無い・テスト中など）何もしない。
@Observable
final class SyncService {
    enum Key {
        static let cursor = "sync.cursor"
        /// cursor をもらったサーバー。変わったら cursor を捨てて全件を送り直す
        static let server = "sync.server"
        static let lastSyncedAt = "sync.lastSyncedAt"
        /// DEBUG のダミーデータ（`DebugSeed`）を入れたことがある。アプリを入れ直すまで同期しない
        static let disabledByDebugSeed = "sync.disabledByDebugSeed"
    }

    /// 変更から同期までの待ち時間。続けて編集したときに 1 回にまとめる
    static let debounce: Duration = .seconds(2)
    /// reset や通信中の依頼で続けて回す上限
    static let maxRounds = 3

    let config: ServerConfig?
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    private(set) var lastError: String?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let client: SyncClient?
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var rerunRequested = false
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    var isEnabled: Bool { config != nil }

    init(
        config: ServerConfig?,
        context: ModelContext,
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        debounce: Duration = SyncService.debounce
    ) {
        self.config = config
        self.context = context
        self.defaults = defaults
        self.debounce = debounce
        client = config.map { SyncClient(config: $0, session: session) }
        lastSyncedAt = defaults.object(forKey: Key.lastSyncedAt) as? Date
    }

    /// アプリで使う接続先。テストの実行中・ダミーデータを入れた端末では、本番に送らないよう nil にする
    static func appConfig(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> ServerConfig? {
        if environment["XCTestConfigurationFilePath"] != nil { return nil }
        #if DEBUG
        if environment["VOCAB_SEED_DEMO"] == "1" { return nil }
        if defaults.bool(forKey: Key.disabledByDebugSeed) { return nil }
        #endif
        return ServerConfig.load(bundle: bundle)
    }

    // MARK: - 呼び出し

    /// `GroupEditor` の保存を見張り、少し待ってから同期する
    func startObservingChanges() {
        guard isEnabled, observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .syncableDataDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleSoon()
            }
        }
    }

    func scheduleSoon() {
        guard isEnabled else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// すぐに同期する。走っている最中なら、終わってからもう 1 回回すよう頼んで戻る
    func syncNow() async {
        guard let client, let config else { return }
        if isSyncing {
            rerunRequested = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        var rounds = 0
        repeat {
            rerunRequested = false
            rounds += 1
            do {
                let engine = SyncEngine(context: context)
                try prepareCursor(for: config, engine: engine)
                let request = try engine.makeRequest(cursor: cursor)
                let response = try await client.sync(request)
                try engine.apply(response, sent: request)
                cursor = response.cursor
                if response.reset { rerunRequested = true }
                lastSyncedAt = .now
                defaults.set(lastSyncedAt, forKey: Key.lastSyncedAt)
                lastError = nil
            } catch {
                lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return
            }
        } while rerunRequested && rounds < Self.maxRounds
    }

    /// バックアップから復元したあと。復元した内容を全件送り直し、サーバーの全件も受け取り直す
    func resendAll() {
        cursor = 0
        try? SyncEngine(context: context).markAllForResend()
        try? context.save()
        guard isEnabled else { return }
        Task { await syncNow() }
    }

    // MARK: - cursor

    private var cursor: Int {
        get { defaults.integer(forKey: Key.cursor) }
        set { defaults.set(newValue, forKey: Key.cursor) }
    }

    /// 接続先が前回と違えば、前の cursor は意味が無いので 0 に戻して全件を送り直す
    private func prepareCursor(for config: ServerConfig, engine: SyncEngine) throws {
        let server = config.baseURL.absoluteString
        guard defaults.string(forKey: Key.server) != server else { return }
        if defaults.string(forKey: Key.server) != nil {
            try engine.markAllForResend()
        }
        cursor = 0
        defaults.set(server, forKey: Key.server)
    }
}
