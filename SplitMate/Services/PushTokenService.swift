import Foundation
import Supabase

struct PushTokenService {
    let client: SupabaseClient

    func upsertToken(userId: UUID, hexToken: String) async throws {
        let row = PushTokenUpsert(
            userId: userId,
            token: hexToken,
            platform: "ios"
        )
        _ = try await client
            .from("push_tokens")
            .upsert(row, onConflict: "user_id,token")
            .execute()
    }
}

private struct PushTokenUpsert: Encodable {
    let userId: UUID
    let token: String
    let platform: String

    enum CodingKeys: String, CodingKey {
        case token, platform
        case userId = "user_id"
    }
}
