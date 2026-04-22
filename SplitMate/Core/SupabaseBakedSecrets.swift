import Foundation

/// Build-time baked Supabase credentials.
///
/// The committed version of this file contains EMPTY strings on purpose.
/// Real values are written here by `ci_scripts/ci_post_clone.sh` during
/// Xcode Cloud builds from the workflow's environment variables.
///
/// DO NOT commit real values to source control. Local development should
/// continue to use Scheme → Run → Environment Variables (or the
/// `Secrets.local.xcconfig` file, which is gitignored).
enum SupabaseBakedSecrets {
    static let url: String = ""
    static let anonKey: String = ""
}
