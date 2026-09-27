import Foundation

/// Čte API klíč, který na Mac ukládá `muse login`: keychain položka
/// `ai.meta.dev.credentials` s JSON `{"api_key": "LLM|…", "access_token": "dca:…"}`.
/// Autorizuje `POST /v1/responses` i `GET /v1/models`; surový OAuth token (`dca:…`)
/// API klíčem není.
///
/// Čtení jde přes `/usr/bin/security` (stejný trik jako u Claude: binárka je
/// partition `apple-tool:`, takže čtení nepromptuje; jednorázový "Always Allow"
/// grant stačí). Narozdíl od Claude cesty není potřeba vlastní cache položka:
/// čtení přes `security` je levné a nepromptuje, takže se klíč čte pokaždé znovu
/// a rotace po re-loginu se projeví automaticky. 401 → jeden re-read a retry
/// řeší `MuseUsageClient`.
public enum MuseKeychain {
    public static let service = "ai.meta.dev.credentials"

    public static func readApiKey() throws -> String {
        let output = try Keychain.readSecretViaSecurityTool(service: service)
        return try parse(Keychain.decodeSecurityToolOutput(output))
    }

    /// Split out pro unit testy bez sahání na skutečnou keychain.
    static func parse(_ data: Data) throws -> String {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let key = root["api_key"] as? String,
            !key.isEmpty
        else { throw KeychainError.unexpectedData }
        return key
    }
}
