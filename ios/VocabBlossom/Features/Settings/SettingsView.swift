import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// 設定。初学者が迷わないよう、項目は学習・音声・データの 3 つに絞る。
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @State private var exportDocument: BackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingImport: Data?
    @State private var message: Message?

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
                    Picker("レベル", selection: $settings.level) {
                        ForEach(CefrLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    Picker("1日の新しい単語", selection: $settings.newWordsPerDay) {
                        ForEach(AppSettings.newWordsPerDayChoices, id: \.self) { count in
                            Text("\(count) 語").tag(count)
                        }
                    }
                    NavigationLink {
                        KnownWordsPickerView()
                    } label: {
                        Label("知っている単語をまとめて登録", systemImage: "checklist")
                    }
                } header: {
                    Text("学習")
                } footer: {
                    Text(
                        """
                        レベルを変えても、覚えた単語と復習の予定はそのまま残ります。
                        復習は 1 日最大 \(settings.reviewLimitPerDay) 語まで自動で調整します。
                        """
                    )
                }

                Section {
                    Toggle("自動で読み上げる", isOn: $settings.soundEnabled)
                    Toggle("正解・不正解の音", isOn: $settings.effectSoundEnabled)
                } header: {
                    Text("音声")
                } footer: {
                    Text("読み上げをオフにしても、スピーカーのボタンからいつでも聞けます。")
                }

                Section {
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
                    Text("読み込むと、いまの進捗はファイルの内容に置き換わります。")
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
        }
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
            message = Message(
                title: "読み込みました",
                detail: "\(archive.progress.count) 語の進捗と \(archive.logs.count) 件の記録を復元しました。"
            )
        } catch {
            message = Message(title: "読み込めませんでした", detail: error.localizedDescription)
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
