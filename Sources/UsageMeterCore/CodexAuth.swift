import Foundation

/// Přihlášení, které na Mac ukládá `codex login`: soubor `auth.json`
/// s `{"tokens": {"access_token": "…"}, "account_id": "…"}`.
/// Respektuje `$CODEX_HOME`, jinak `~/.codex`.
///
/// Narozdíl od Claude/Muse cest není potřeba keychain ani vlastní cache:
/// čtení souboru je levné a CLI si token refreshuje samo, takže se soubor čte
/// znovu každý poll a rotace se projeví automaticky. Obsah souboru nikdy
/// nelogovat — je to plnohodnotný Bearer token.
public enum CodexAuth {
    public struct Credentials: Equatable, Sendable {
        public let accessToken: String
        public let accountId: String?

        public init(accessToken: String, accountId: String?) {
            self.accessToken = accessToken
            self.accountId = accountId
        }
    }

    public static func readCredentials() throws -> Credentials {
        guard let data = try? Data(contentsOf: authFileURL()) else {
            throw KeychainError.notFound
        }
        return try parse(data)
    }

    static func authFileURL() -> URL {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home).appendingPathComponent("auth.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
    }

    /// Split out pro unit testy bez sahání na skutečný soubor.
    static func parse(_ data: Data) throws -> Credentials {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = root["tokens"] as? [String: Any],
            let token = tokens["accessToken"] as? String ?? tokens["access_token"] as? String,
            !token.isEmpty
        else { throw KeychainError.unexpectedData }
        let accountId = tokens["accountId"] as? String
            ?? tokens["account_id"] as? String
            ?? root["accountId"] as? String
            ?? root["account_id"] as? String
        return Credentials(accessToken: token, accountId: accountId)
    }
}
