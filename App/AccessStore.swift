import SwiftUI

@MainActor final class AccessStore: ObservableObject {
    @Published private(set) var entries: [AccessEntry] = []
    @Published private(set) var status: WorkerStatus?
    @Published private(set) var desiredRevision = ""
    @Published private(set) var server = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    @Published private(set) var configured = false
    @Published private(set) var refreshing = false
    @Published private(set) var busy = false
    @Published private(set) var online = false
    @Published var errorMessage: String?
    @Published var notice: String?

    let demo: Bool
    private var client: APIClient?
    private var generation = UUID()

    init(demo: Bool = ProcessInfo.processInfo.arguments.contains("--demo")) {
        self.demo = demo
        if demo {
            configured = true; online = true
            entries = [
                AccessEntry(id: "demo-office", address: "203.0.113.42", label: "Работа", expiresAt: Date().addingTimeInterval(7 * 3600 + 24 * 60)),
                AccessEntry(id: "demo-laptop", address: "198.51.100.18", label: "Ноутбук", expiresAt: Date().addingTimeInterval(3600 + 12 * 60))
            ]
            setDemoStatus()
        } else if let token = TokenKeychain.read(), let base = try? InputValidation.server(server) {
            client = APIClient(base: base, token: token); configured = true
        }
    }

    var activeEntries: [AccessEntry] { entries.filter { $0.expiresAt > Date() }.sorted { $0.expiresAt < $1.expiresAt } }

    func configure(server: String, token: String) async -> Bool {
        guard !demo, !busy else { return false }
        do {
            let base = try InputValidation.server(server)
            let token = try InputValidation.token(token)
            try TokenKeychain.save(token)
            busy = true
            defer { busy = false }
            generation = UUID()
            self.server = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            UserDefaults.standard.set(self.server, forKey: "serverURL")
            let newClient = APIClient(base: base, token: token)
            client = newClient; configured = true
            entries = []; status = nil; online = false; desiredRevision = ""
            await load(newClient, generation: generation, showError: true)
            if online { notice = "Подключение сохранено" }
            return online
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func forget() {
        guard !busy, !demo else { return }
        do {
            try TokenKeychain.delete()
            generation = UUID()
            client = nil; configured = false; entries = []; status = nil
            online = false; desiredRevision = ""; notice = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh(showError: Bool = false) async {
        guard !refreshing, !busy else { return }
        if demo { setDemoStatus(); return }
        guard let client else { return }
        refreshing = true
        defer { refreshing = false }
        await load(client, generation: generation, showError: showError)
    }

    private func load(_ client: APIClient, generation expected: UUID, showError: Bool) async {
        do {
            let result = try await client.snapshot()
            guard generation == expected else { return }
            entries = result.entries.entries
            desiredRevision = result.entries.revision
            status = result.status; online = true
        } catch is CancellationError { }
        catch {
            guard generation == expected else { return }
            online = false
            if showError { errorMessage = error.localizedDescription }
        }
    }

    func add(address: String, label: String, ttl: Int) async -> Bool {
        guard !busy else { return false }
        do {
            let address = try InputValidation.address(address)
            if demo {
                entries.removeAll { $0.address == address }
                entries.append(AccessEntry(id: UUID().uuidString, address: address, label: label, expiresAt: Date().addingTimeInterval(Double(ttl))))
                setDemoStatus(); notice = "Добавлено в демонстрации"; return true
            }
            guard let client else { return false }
            return await mutate { try await client.add(address: address, label: label, ttl: ttl) }
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func remove(_ entry: AccessEntry) async {
        guard !busy else { return }
        if demo { entries.removeAll { $0.id == entry.id }; setDemoStatus(); notice = "Удалено в демонстрации"; return }
        guard let client else { return }
        _ = await mutate { try await client.remove(id: entry.id) }
    }

    private func mutate(_ operation: () async throws -> MutationResponse) async -> Bool {
        guard let client else { return false }
        generation = UUID()
        let expected = generation
        busy = true; notice = nil
        defer { busy = false }
        var accepted = false
        do {
            let queued = try await operation()
            accepted = true
            notice = "Применяем изменение…"
            let confirmation = try await client.confirm(queued.revision)
            switch confirmation {
            case .applied: notice = "Изменение применено"
            case .pending: notice = "Запрос сохранён. Подтверждение ещё ожидается."
            case .superseded: notice = "Список изменился на другом устройстве. Загружена текущая версия."
            case .disabled: notice = "Список сохранён, но фильтр на сервере выключен."
            case .failed: notice = "Список сохранён. Сервер сообщил об ошибке применения."
            }
            await load(client, generation: expected, showError: false)
            return true
        } catch is CancellationError {
            if accepted { notice = "Запрос сохранён. Обнови список для проверки применения." }
            return accepted
        } catch {
            if accepted { notice = "Запрос сохранён. Проверь результат после восстановления связи." }
            errorMessage = error.localizedDescription
            await load(client, generation: expected, showError: false)
            return accepted
        }
    }

    private func setDemoStatus() {
        let value = "{\"state\":\"applied\",\"revision\":\"demo\",\"checked_at\":\"\(ISO8601DateFormatter().string(from: Date()))\",\"active_entries\":\(activeEntries.count)}"
        status = try? APICoding.decoder().decode(WorkerStatus.self, from: Data(value.utf8))
        desiredRevision = "demo"
    }
}
