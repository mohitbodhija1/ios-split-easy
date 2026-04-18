import Foundation

/// Supabase URL and anon key are read in this order:
/// 1. Process environment (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) — use **Xcode → Scheme → Edit Scheme → Run → Environment Variables**
/// 2. Info.plist entries with the same keys (if you add them under target **Info** or build settings)
///
/// Do not ship placeholder values; DNS will fail with "hostname could not be found" (-1003).
enum SupabaseCredentials {
    static let supabaseURL: URL = {
        let raw = Self.string(
            envKey: "SUPABASE_URL",
            infoPlistKey: "SUPABASE_URL"
        )
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host,
              host.hasSuffix("supabase.co"),
              !Self.isPlaceholderSupabaseHost(host),
              url.scheme == "https"
        else {
            preconditionFailure(
                """
                Invalid or missing SUPABASE_URL (got: \(raw.isEmpty ? "(empty)" : raw)).

                In Xcode: Product → Scheme → Edit Scheme → Run → Environment Variables, add:
                  SUPABASE_URL = https://<your-project-ref>.supabase.co
                  SUPABASE_ANON_KEY = <anon key from Supabase Dashboard → Project Settings → API>

                Or add the same keys to your app Info.plist.
                """
            )
        }
        return url
    }()

    static let anonKey: String = {
        let raw = Self.string(
            envKey: "SUPABASE_ANON_KEY",
            infoPlistKey: "SUPABASE_ANON_KEY"
        )
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20,
              !Self.isPlaceholderAnonKey(trimmed)
        else {
            preconditionFailure(
                """
                Invalid or missing SUPABASE_ANON_KEY.

                In Xcode: Scheme → Run → Environment Variables, add SUPABASE_ANON_KEY from
                Supabase Dashboard → Project Settings → API → Project API keys → anon public.
                """
            )
        }
        return trimmed
    }()

    private static func string(envKey: String, infoPlistKey: String) -> String {
        if let v = ProcessInfo.processInfo.environment[envKey], !v.isEmpty {
            return v
        }
        if let v = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String, !v.isEmpty {
            return v
        }
        return ""
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
