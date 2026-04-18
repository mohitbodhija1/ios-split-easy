import Foundation
import Supabase

enum SupabaseProvider {
    static let shared = SupabaseClient(
        supabaseURL: SupabaseCredentials.supabaseURL,
        supabaseKey: SupabaseCredentials.anonKey
    )
}
