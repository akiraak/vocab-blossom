import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// 設定。初学者が迷わないよう、項目は音声・データ（+ サーバーとの同期・AI のモデル）に絞る。
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SyncService.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.wordStore) private var store
    @Query private var progresses: [WordProgress]
    @Query private var groups: [WordGroup]

    @State private var exportDocument: BackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingImport: Data?
    @State private var message: Message?
    @State private var showsMyWords = false
    @State private var isConfirmingCleanup = false

    private struct Message: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Toggle("自動で読み上げる", isOn: $settings.soundEnabled)
                    Toggle("正解・不正解の音", isOn: $settings.effectSoundEnabled)
                } header: {
                    Text("音声")
                } footer: {
                    Text("読み上げをオフにしても、スピーカーのボタンからいつでも聞けます。")
                }

                Section {
                    NavigationLink {
                        MyWordsView()
                    } label: {
                        LabeledContent {
                            Text("\(store.customWords.count) 語")
                        } label: {
                            Label("マイ単語", systemImage: "character.book.closed")
                        }
                    }
                    Button {
                        prepareExport()
                    } label: {
                        Label("進捗を書き出す", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        isImporting = true
                    } label: {
                        Label("進捗を読み込む", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("データ")
                } footer: {
                    if sync.isEnabled {
                        Text(
                            """
                            読み込むと、いまの進捗はファイルの内容に置き換わります。\
                            グループ・自作の単語はサーバーの内容と合わせ、新しい方が残ります。
                            """
                        )
                    } else {
                        Text("読み込むと、いまの進捗・グループ・自作の単語はファイルの内容に置き換わります。")
                    }
                }

                cleanupSection

                SyncSection()

                if sync.config != nil {
                    AIModelSection()
                }

                Section("このアプリ") {
                    LabeledContent("バージョン", value: appVersion)
                    LabeledContent("収録語数") {
                        Text("\(WordStore.shared.allWords.count) 語")
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showsMyWords) {
                MyWordsView()
            }
        }
        #if DEBUG
        .onAppear {
            if DebugSeed.variant == .myWords { showsMyWords = true }
        }
        #endif
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: BackupService.fileName()
        ) { result in
            if case .failure(let error) = result {
                message = Message(title: "書き出せませんでした", detail: error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json]
        ) { result in
            handlePickedFile(result)
        }
        .alert("進捗を置き換えますか？", isPresented: .constant(pendingImport != nil)) {
            Button("置き換える", role: .destructive) { applyImport() }
            Button("キャンセル", role: .cancel) { pendingImport = nil }
        } message: {
            Text("いまの学習記録は消えて、ファイルの内容になります。")
        }
        .alert(item: $message) { message in
            Alert(title: Text(message.title), message: Text(message.detail))
        }
    }

    /// どのグループにも入っていない語の学習記録（前の版のおまかせ学習・既知語の一括登録・外した語など）
    private var wordIdsOutsideGroups: Set<String> {
        LearningEngine.wordIdsOutsideGroups(
            progressWordIds: progresses.map(\.wordId),
            groupWordIds: Set(groups.flatMap(\.wordIds))
        )
    }

    /// グループに無い語の学習記録を消す。今日の復習にはもともと出ないが、統計の数などから外したいとき用
    private var cleanupSection: some View {
        let count = wordIdsOutsideGroups.count
        return Section {
            Button(role: .destructive) {
                isConfirmingCleanup = true
            } label: {
                LabeledContent {
                    Text("\(count) 語")
                        .monospacedDigit()
                } label: {
                    Label("グループに無い単語の学習記録を消す", systemImage: "leaf.arrow.triangle.circlepath")
                }
            }
            .disabled(count == 0)
            .confirmationDialog(
                "グループに無い \(count) 語の学習記録を消しますか？",
                isPresented: $isConfirmingCleanup,
                titleVisibility: .visible
            ) {
                Button("\(count) 語の学習記録を消す", role: .destructive) { deleteProgressOutsideGroups() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text(
                    """
                    消した単語は種（未学習）に戻ります。グループの単語・回答の記録・連続日数・マイ単語は消えません。\
                    元に戻せないので、先に「進捗を書き出す」で控えを取っておくと安心です。
                    """
                )
            }
        } header: {
            Text("学習記録の整理")
        } footer: {
            Text(
                """
                今日の復習には、グループに入っている単語だけが出ます。\
                前の版で学習した単語や、グループから外した単語の学習記録は残っているので、使わなければここで消せます。
                """
            )
        }
    }

    private func deleteProgressOutsideGroups() {
        let deleted = LearningEngine(context: context).deleteProgress(wordIds: wordIdsOutsideGroups)
        message = Message(title: "消しました", detail: "\(deleted) 語の学習記録を消しました。")
    }

    private func prepareExport() {
        do {
            let data = try BackupService.export(context: context, settings: settings)
            exportDocument = BackupDocument(data: data)
            isExporting = true
        } catch {
            message = Message(title: "書き出せませんでした", detail: error.localizedDescription)
        }
    }

    private func handlePickedFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            do {
                pendingImport = try Data(contentsOf: url)
            } catch {
                message = Message(title: "読み込めませんでした", detail: error.localizedDescription)
            }
        case .failure(let error):
            message = Message(title: "読み込めませんでした", detail: error.localizedDescription)
        }
    }

    private func applyImport() {
        guard let data = pendingImport else { return }
        pendingImport = nil
        do {
            let archive = try BackupService.restore(
                from: data, context: context, settings: settings
            )
            sync.resendAll()
            message = Message(
                title: "読み込みました",
                detail: "\(archive.progress.count) 語の進捗と \(archive.logs.count) 件の記録、"
                    + "\(archive.groups?.count ?? 0) 個のグループを復元しました。"
            )
        } catch {
            message = Message(title: "読み込めませんでした", detail: error.localizedDescription)
        }
    }
}

/// サーバー（管理画面）との同期の状態。グループと自作の単語だけを同期する
private struct SyncSection: View {
    @Environment(SyncService.self) private var sync

    var body: some View {
        Section {
            if let config = sync.config {
                LabeledContent("サーバー", value: config.displayHost)
                LabeledContent("最後に同期") {
                    if let date = sync.lastSyncedAt {
                        Text(date, format: .relative(presentation: .named))
                    } else {
                        Text("まだ同期していません")
                    }
                }
                if let error = sync.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Button {
                    Task { await sync.syncNow() }
                } label: {
                    HStack {
                        Label("今すぐ同期", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if sync.isSyncing {
                            ProgressView()
                        }
                    }
                }
                .disabled(sync.isSyncing)
            } else {
                Text("サーバーの設定が無いため、この端末の中だけに保存しています。")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("同期")
        } footer: {
            if sync.isEnabled {
                Text("グループと自分で作った単語を、管理画面と同期します。学習の記録はこの端末の中だけに残ります。")
            }
        }
    }
}

/// AI のモデル（サーバーがあるときだけ）。端末ごとの設定で、次にサーバーへ頼むときから効く
private struct AIModelSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            Picker("問題作成・AI チェック", selection: $settings.claudeModel) {
                ForEach(ClaudeModel.allCases) { model in
                    Text(model.label).tag(model)
                }
            }
            Picker("読み上げの声", selection: $settings.ttsModel) {
                ForEach(TTSModel.allCases) { model in
                    Text(model.label).tag(model)
                }
            }
        } header: {
            Text("AI")
        } footer: {
            Text(
                """
                「問題作成」は穴埋めの文章づくり、「AI チェック」は自分で単語を作るときの確認です。\
                速い・安いモデルは、品質が少し下がることがあります。\
                読み上げの声を変えると、その声で読む音声を新しく作ります。
                """
            )
        }
    }
}

/// エクスポート用のファイル本体。
nonisolated struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw BackupError.malformed
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
