import Foundation
import Darwin

public struct AccessEntry: Codable, Identifiable, Equatable {
    public let id: String
    public let address: String
    public let label: String?
    public let expiresAt: Date

    public init(id: String, address: String, label: String?, expiresAt: Date) {
        self.id = id; self.address = address; self.label = label; self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case id, address, label
        case expiresAt = "expires_at"
    }
}

public struct EntriesResponse: Decodable {
    public let version: Int
    public let revision: String
    public let entries: [AccessEntry]
}

public struct WorkerStatus: Decodable {
    public let state: String
    public let revision: String?
    public let checkedAt: Date?
    public let activeEntries: Int?
    public let errorType: String?

    enum CodingKeys: String, CodingKey {
        case state, revision
        case checkedAt = "checked_at"
        case activeEntries = "active_entries"
        case errorType = "error_type"
    }

    public func isFresh(at now: Date = Date()) -> Bool {
        guard let checkedAt else { return false }
        return (-60...30).contains(now.timeIntervalSince(checkedAt))
    }
}

public struct MutationResponse: Decodable {
    public let state: String
    public let revision: String
    public let entry: AccessEntry?
}

public struct Snapshot {
    public let entries: EntriesResponse
    public let status: WorkerStatus
}

public enum Confirmation: Equatable {
    case applied, pending, superseded, disabled, failed
}

public enum AccessError: LocalizedError {
    case invalidServer, invalidAddress, invalidToken, unauthorized, invalidRequest
    case missingEntry, serverUnavailable, unexpectedResponse, pending, transport

    public var errorDescription: String? {
        switch self {
        case .invalidServer: return "Укажи адрес API без пути, логина и пароля. Для HTTP нужен частный IPv4-адрес."
        case .invalidAddress: return "Введи один IPv4 или IPv6 адрес без маски сети."
        case .invalidToken: return "Вставь токен API целиком, без имени переменной и пробелов."
        case .unauthorized: return "Токен не принят. Проверь его в настройках."
        case .invalidRequest: return "Сервер отклонил запрос. Нужен публичный IP и срок от минуты до 24 часов."
        case .missingEntry: return "Этот адрес уже удалён. Обнови список."
        case .serverUnavailable: return "Обработчик на Akita временно недоступен. Попробуй обновить список."
        case .unexpectedResponse: return "Ответ не похож на API Akita. Проверь адрес сервера."
        case .pending: return "Запрос сохранён, но подтверждение применения пока не получено."
        case .transport: return "Нет связи с Akita. Включи Tailscale и разреши приложению доступ к локальной сети."
        }
    }
}

public enum InputValidation {
    public static func address(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var v4 = in_addr()
        var v6 = in6_addr()
        guard inet_pton(AF_INET, value, &v4) == 1 || inet_pton(AF_INET6, value, &v6) == 1 else {
            throw AccessError.invalidAddress
        }
        return value
    }

    public static func server(_ raw: String) throws -> URL {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: value), let url = parts.url,
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { throw AccessError.invalidServer }
        if scheme == "http" {
            var numeric = in_addr()
            guard inet_pton(AF_INET, host, &numeric) == 1 else { throw AccessError.invalidServer }
            let octets = host.split(separator: ".").compactMap { UInt8($0) }
            guard octets.count == 4 else { throw AccessError.invalidServer }
            let a = octets[0], b = octets[1]
            let local = a == 10 || a == 127 || (a == 192 && b == 168)
                || (a == 172 && (16...31).contains(b)) || (a == 100 && (64...127).contains(b))
            guard local else { throw AccessError.invalidServer }
        }
        return url
    }

    public static func token(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 32, value.utf8.allSatisfy({ $0 > 32 && $0 < 127 }),
              !value.contains("=") else { throw AccessError.invalidToken }
        return value
    }
}

public enum APICoding {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let whole = ISO8601DateFormatter()
            whole.formatOptions = [.withInternetDateTime]
            guard let date = fractional.date(from: text) ?? whole.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid API timestamp"))
            }
            return date
        }
        return decoder
    }
}
