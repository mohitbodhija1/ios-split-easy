import Foundation

/// Supabase URL and anon key are read in this order:
/// 1. Process environment (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) — use **Xcode → Scheme → Edit Scheme → Run → Environment Variables**
/// 2. Info.plist entries with the same keys (if you add them under target **Info** or build settings)
/// 3. `SupabaseBakedSecrets`, written by `ci_scripts/ci_post_clone.sh` during Xcode Cloud builds
///
/// Do not ship placeholder values; DNS will fail with "hostname could not be found" (-1003).
enum SupabaseCredentials {
    private static let fallbackURL = URL(string: "https://invalid.supabase.co")!
    private static let fallbackAnonKey = "invalid-supabase-anon-key"

    static let validationError: String? = {
        let rawURL = Self.string(
            envKey: "SUPABASE_URL",
            infoPlistKey: "SUPABASE_URL",
            baked: SupabaseBakedSecrets.url
        )
        let rawKey = Self.string(
            envKey: "SUPABASE_ANON_KEY",
            infoPlistKey: "SUPABASE_ANON_KEY",
            baked: SupabaseBakedSecrets.anonKey
        )
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let isValidURL = Self.isValidSupabaseURL(trimmedURL)
        let isValidKey = Self.isValidAnonKey(trimmedKey)
        guard !isValidURL || !isValidKey else { return nil }

        let currentURL = trimmedURL.isEmpty ? "(empty)" : trimmedURL
        return """
        Supabase is not configured correctly.

        Current values:
          SUPABASE_URL = \(currentURL)
          SUPABASE_ANON_KEY = \(trimmedKey.isEmpty ? "(empty)" : "(set, \(trimmedKey.count) chars)")

        Fix:
        1) Xcode → Product → Scheme → Edit Scheme → Run → Environment Variables
           SUPABASE_URL = https://<your-project-ref>.supabase.co
           SUPABASE_ANON_KEY = <anon key from Supabase Dashboard → Project Settings → API>
        2) Or add the same keys to app Info.plist.
        """
    }()

    static let supabaseURL: URL = {
        let raw = Self.string(
            envKey: "SUPABASE_URL",
            infoPlistKey: "SUPABASE_URL",
            baked: SupabaseBakedSecrets.url
        )
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidSupabaseURL(trimmed), let url = URL(string: trimmed) else {
            return fallbackURL
        }
        return url
    }()

    static let anonKey: String = {
        let raw = Self.string(
            envKey: "SUPABASE_ANON_KEY",
            infoPlistKey: "SUPABASE_ANON_KEY",
            baked: SupabaseBakedSecrets.anonKey
        )
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.isValidAnonKey(trimmed) ? trimmed : fallbackAnonKey
    }()

    private static func string(envKey: String, infoPlistKey: String, baked: String) -> String {
        if let v = ProcessInfo.processInfo.environment[envKey], !v.isEmpty {
            return v
        }
        if let v = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String, !v.isEmpty {
            return v
        }
        let trimmedBaked = baked.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBaked.isEmpty {
            return trimmedBaked
        }
        return ""
    }

    private static func isValidSupabaseURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw),
              let host = url.host,
              host.hasSuffix("supabase.co"),
              !Self.isPlaceholderSupabaseHost(host),
              url.scheme == "https"
        else {
            return false
        }
        return true
    }

    private static func isValidAnonKey(_ raw: String) -> Bool {
        raw.count >= 20 && !Self.isPlaceholderAnonKey(raw)
    }

    private static func isPlaceholderSupabaseHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return h.contains("your_project_ref")
            || h.contains("your-project-ref")
            || h.contains("placeholder")
            || h == "xxx.supabase.co"
    }

    private static func isPlaceholderAnonKey(_ key: String) -> Bool {
        let k = key.uppercased()
        return k.contains("YOUR_SUPABASE") || k.contains("YOUR_ANON") || k == "YOUR_SUPABASE_ANON_KEY"
    }
}
