import SwiftUI

private enum AppTab { case access, settings }

struct RootView: View {
    @EnvironmentObject private var store: AccessStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .access

    var body: some View {
        TabView(selection: $tab) {
            AccessListView { tab = .settings }
                .tabItem { Label("Доступ", systemImage: "network") }.tag(AppTab.access)
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape") }.tag(AppTab.settings)
        }
        .onAppear {
            if store.demo && ProcessInfo.processInfo.arguments.contains("--preview-settings") { tab = .settings }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                if !store.busy { await store.refresh() }
                do { try await Task.sleep(nanoseconds: 15_000_000_000) }
                catch { break }
            }
        }
        .alert("Не получилось", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("Понятно") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}

struct AccessListView: View {
    @EnvironmentObject private var store: AccessStore
    @State private var adding = false
    @State private var deleting: AccessEntry?
    let openSettings: () -> Void

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: Date(), by: 10)) { _ in
                List {
                    Section {
                        StatusCard()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    if store.demo {
                        Section {
                            Label("Демонстрация · данные вымышлены", systemImage: "eye")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if let notice = store.notice {
                        Section {
                            HStack(spacing: 10) {
                                if store.busy { ProgressView() }
                                else { Image(systemName: "info.circle").foregroundStyle(Color.accentColor) }
                                Text(notice).font(.subheadline)
                            }
                        }
                    }
                    Section {
                        if !store.configured {
                            VStack(spacing: 14) {
                                Image(systemName: "key.horizontal").font(.system(size: 32)).foregroundStyle(Color.accentColor)
                                Text("Подключи Akita").font(.title3.weight(.semibold))
                                Text("Один раз укажи токен API.\nЗатем управляй доступом отсюда.")
                                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                Button("Настроить подключение", action: openSettings).buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                        } else if store.activeEntries.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 32)).foregroundStyle(Color.accentColor)
                                Text("Внешних адресов пока нет").font(.headline)
                                Text("Добавь публичный IP работы,\nчтобы открыть домашние сервисы.")
                                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                Button("Добавить IP") { adding = true }.buttonStyle(.borderedProminent).disabled(store.busy)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                        } else {
                            ForEach(store.activeEntries) { entry in
                                EntryRow(entry: entry)
                                    .swipeActions {
                                        Button("Отозвать", role: .destructive) { deleting = entry }
                                            .disabled(store.busy)
                                    }
                                    .contextMenu {
                                        Button("Отозвать доступ", systemImage: "minus.circle", role: .destructive) { deleting = entry }
                                            .disabled(store.busy)
                                    }
                            }
                        }
                    } header: {
                        Text("Разрешённые адреса")
                    } footer: {
                        Text("Домашняя сеть разрешена отдельно. Временный доступ завершится автоматически.")
                    }
                    if store.configured {
                        Section {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Управление через Tailscale").font(.subheadline.weight(.medium))
                                    Text("IP указывай с рабочего компьютера, а не с iPhone.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(Color.accentColor)
                            }.padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await store.refresh(showError: true) }
            }
            .navigationTitle("Akita Guard")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if store.refreshing { ProgressView() }
                    else {
                        Button { Task { await store.refresh(showError: true) } } label: { Image(systemName: "arrow.clockwise") }
                            .disabled(!store.configured || store.busy).accessibilityLabel("Обновить список")
                    }
                    Button { adding = true } label: { Image(systemName: "plus.circle.fill") }
                        .disabled(!store.configured || store.busy).accessibilityLabel("Добавить IP").accessibilityIdentifier("addIP")
                }
            }
            .sheet(isPresented: $adding) { AddEntryView() }
            .onAppear {
                if store.demo && ProcessInfo.processInfo.arguments.contains("--preview-add") { adding = true }
            }
            .confirmationDialog("Отозвать доступ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                if let entry = deleting {
                    Button("Отозвать \(entry.address)", role: .destructive) {
                        deleting = nil
                        Task { await store.remove(entry) }
                    }
                }
                Button("Отмена", role: .cancel) { deleting = nil }
            } message: { Text("Адрес будет удалён из списка разрешённых.") }
        }
    }
}

private struct StatusCard: View {
    @EnvironmentObject private var store: AccessStore

    private var summary: (String, String, Color) {
        guard store.configured else { return ("Готово к подключению", "Добавь токен в настройках", .secondary) }
        if store.busy { return ("Применяем изменение", "Ожидаем подтверждения Akita", .blue) }
        guard store.online else { return ("Нет связи с Akita", "Проверь Tailscale и обнови список", .orange) }
        guard let status = store.status else { return ("Проверяем состояние", "Ожидаем ответ обработчика", .orange) }
        if status.state == "disabled" { return ("Фильтр выключен", "Список пока не ограничивает доступ", .orange) }
        if status.state == "error" { return ("Ошибка применения", "Проверь обработчик на сервере", .red) }
        if status.state == "applied", status.revision == store.desiredRevision, status.isFresh() {
            return ("Защита включена", "Список применён на Akita", Color.accentColor)
        }
        if !status.isFresh() { return ("Нужно обновить статус", "Нет свежего подтверждения сервера", .orange) }
        return ("Ожидаем применения", "Изменения ещё обрабатываются", .blue)
    }

    var body: some View {
        let state = summary
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("ДОМАШНИЙ ДОСТУП").font(.caption.weight(.semibold)).tracking(1.5)
                Spacer()
                Image(systemName: "shield.lefthalf.filled").font(.title2)
            }.foregroundStyle(Color.accentColor)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(store.activeEntries.count)").font(.system(size: 58, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text("IP в списке").font(.headline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle().fill(state.2).frame(width: 7, height: 7)
                    Text(state.0).font(.subheadline.weight(.semibold))
                }
                Text(state.1).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 26))
        .accessibilityElement(children: .combine)
    }
}

private struct EntryRow: View {
    let entry: AccessEntry

    private var remaining: String {
        let minutes = max(0, Int(entry.expiresAt.timeIntervalSinceNow / 60))
        if minutes == 0 { return "меньше минуты" }
        let hours = minutes / 60
        return hours == 0 ? "\(minutes) мин" : "\(hours) ч \(minutes % 60) мин"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 20)).foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.label?.isEmpty == false ? entry.label! : "Без названия").font(.headline)
                Text(entry.address).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled)
                    .foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text("Ещё \(remaining)")
                    Text("· до \(entry.expiresAt.formatted(.dateTime.hour().minute()))")
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

struct AddEntryView: View {
    @EnvironmentObject private var store: AccessStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var label = "Работа"
    @State private var ttl = 28800
    @State private var submitting = false
    @State private var localError: String?
    @FocusState private var addressFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Например, внешний IP офиса", text: $address)
                        .keyboardType(.asciiCapable).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced)).focused($addressFocused)
                        .accessibilityIdentifier("ipAddress")
                } header: { Text("Публичный IP") } footer: {
                    Text("Узнай адрес на рабочем компьютере. Можно указать IPv4 или IPv6, без маски сети.")
                }
                Section("Название") {
                    TextField("Работа, ноутбук…", text: $label)
                        .onChange(of: label) { _, value in if value.count > 120 { label = String(value.prefix(120)) } }
                }
                Section {
                    Picker("Разрешить на", selection: $ttl) {
                        Text("1 час").tag(3600)
                        Text("4 часа").tag(14400)
                        Text("8 часов").tag(28800)
                        Text("24 часа").tag(86400)
                    }
                    HStack {
                        Text("До").foregroundStyle(.secondary)
                        Spacer()
                        Text(Date().addingTimeInterval(Double(ttl)), format: .dateTime.day().month(.abbreviated).hour().minute())
                    }
                } header: { Text("Время доступа") } footer: {
                    Text("Доступ завершится автоматически. Повторное добавление этого IP обновит срок.")
                }
                Section {
                    Button {
                        addressFocused = false
                        submitting = true
                        Task {
                            let success = await store.add(address: address, label: label.trimmingCharacters(in: .whitespacesAndNewlines), ttl: ttl)
                            submitting = false
                            if success { dismiss() }
                            else { localError = store.errorMessage; store.errorMessage = nil }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if submitting { ProgressView().padding(.trailing, 6) }
                            Text(submitting ? "Применяем…" : "Разрешить доступ").fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(submitting || (try? InputValidation.address(address)) == nil)
                    .accessibilityIdentifier("grantAccess")
                }
            }
            .navigationTitle("Добавить IP").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.disabled(submitting)
                }
            }
        }
        .interactiveDismissDisabled(submitting)
        .alert("Не получилось", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
            Button("Понятно") { localError = nil }
        } message: { Text(localError ?? "") }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AccessStore
    @State private var server = ""
    @State private var token = ""
    @State private var saving = false
    @State private var forgetting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image("AkitaMark").resizable().scaledToFit().frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                        Text("Akita Guard").font(.title3.weight(.semibold)).foregroundStyle(Color.accentColor)
                    }.padding(.vertical, 5)
                    Text("Управление доступом к домашним сервисам с iPhone.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    TextField("http://192.168.1.10:9120", text: $server)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("serverURL")
                } header: { Text("Адрес API") } footer: {
                    Text("Включи Tailscale. Akita доступна через существующий шлюз Home Assistant.")
                }
                Section {
                    SecureField("Токен API", text: $token)
                        .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .privacySensitive().accessibilityIdentifier("apiToken")
                } header: { Text("Токен") } footer: {
                    Text("Вставь только значение токена. Оно хранится в Связке ключей этого iPhone и не синхронизируется с iCloud.")
                }
                Section {
                    Button {
                        saving = true
                        Task { _ = await store.configure(server: server, token: token); saving = false }
                    } label: {
                        HStack {
                            Text("Сохранить и проверить")
                            Spacer()
                            if saving { ProgressView() }
                            else { Image(systemName: "arrow.right.circle") }
                        }
                    }.disabled(saving || store.busy || store.demo || token.isEmpty)
                    if store.demo {
                        Label("Демонстрация · без подключения", systemImage: "eye")
                            .foregroundStyle(.secondary).font(.subheadline)
                    } else if store.configured {
                        Label(store.online ? "Akita отвечает" : "Подключение не подтверждено", systemImage: store.online ? "checkmark.circle.fill" : "wifi.exclamationmark")
                            .foregroundStyle(store.online ? Color.accentColor : .secondary).font(.subheadline)
                    }
                }
                if store.configured && !store.demo {
                    Section {
                        Button("Удалить токен с iPhone", role: .destructive) { forgetting = true }
                            .disabled(store.busy || saving)
                    } footer: { Text("Разрешённые IP на Akita останутся без изменений.") }
                }
                Section {
                    LabeledContent("Сервер", value: "Akita")
                    LabeledContent("Версия", value: "1.0")
                } footer: {
                    Text(store.demo ? "Демонстрационный режим. Подключений к серверу нет." : "Tailscale защищает путь до домашнего шлюза. Между шлюзом и Akita API использует HTTP внутри LAN.")
                }
            }
            .navigationTitle("Настройки")
            .onAppear {
                server = store.server
                token = store.demo ? "" : (TokenKeychain.read() ?? "")
            }
            .confirmationDialog("Удалить токен с этого iPhone?", isPresented: $forgetting, titleVisibility: .visible) {
                Button("Удалить токен", role: .destructive) { store.forget(); token = "" }
                Button("Отмена", role: .cancel) { }
            }
        }
    }
}

#Preview { RootView().environmentObject(AccessStore(demo: true)) }
