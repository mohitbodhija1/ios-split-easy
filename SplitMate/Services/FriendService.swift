import Foundation
import Supabase

struct FriendService {
    let client: SupabaseClient

    func searchProfiles(matching query: String, excluding userId: UUID) async throws -> [Profile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        return try await client
            .from("profiles")
            .select()
            .ilike("username", pattern: "%\(trimmed)%")
            .neq("id", value: userId.uuidString)
            .limit(20)
            .execute()
            .value
    }

    func searchProfiles(name: String, email: String, excluding userId: UUID) async throws -> [Profile] {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        var merged: [UUID: Profile] = [:]

        if !trimmedEmail.isEmpty {
            let emailResults: [Profile] = try await client
                .from("profiles")
                .select()
                .ilike("email", pattern: trimmedEmail)
                .neq("id", value: userId.uuidString)
                .limit(20)
                .execute()
                .value
            for profile in emailResults {
                merged[profile.id] = profile
            }
        }

        if trimmedName.count >= 2 {
            let nameResults: [Profile] = try await client
                .from("profiles")
                .select()
                .ilike("username", pattern: "%\(trimmedName)%")
                .neq("id", value: userId.uuidString)
                .limit(20)
                .execute()
                .value
            for profile in nameResults {
                merged[profile.id] = profile
            }
        }

        return merged.values.sorted {
            $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending
        }
    }

    func sendFriendRequest(from: UUID, to: UUID) async throws {
        let row = FriendRequestInsert(fromUser: from, toUser: to, status: "pending")
        _ = try await client.from("friend_requests").insert(row).execute()
    }

    func createPendingInvite(from inviterId: UUID, name: String, phone: String?, email: String) async throws {
        let row = PendingFriendInviteInsert(
            inviterId: inviterId,
            name: name,
            phone: phone,
            email: email.lowercased(),
            status: "pending"
        )
        _ = try await client.from("pending_friend_invites").insert(row).execute()
    }

    func pendingInvites(for inviterId: UUID) async throws -> [PendingFriendInvite] {
        try await client
            .from("pending_friend_invites")
            .select()
            .eq("inviter_id", value: inviterId.uuidString)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func pendingInvite(id: UUID) async throws -> PendingFriendInvite {
        try await client
            .from("pending_friend_invites")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }

    func incomingPending(for userId: UUID) async throws -> [FriendRequest] {
        try await client
            .from("friend_requests")
            .select()
            .eq("to_user", value: userId.uuidString)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func outgoingPending(for userId: UUID) async throws -> [FriendRequest] {
        try await client
            .from("friend_requests")
            .select()
            .eq("from_user", value: userId.uuidString)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func updateRequest(id: UUID, status: String) async throws {
        _ = try await client
            .from("friend_requests")
            .update(FriendRequestStatusUpdate(status: status))
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Profiles of users you have an accepted friendship with (either direction).
    func acceptedFriends(for userId: UUID) async throws -> [Profile] {
        let requests: [FriendRequest] = try await client
            .from("friend_requests")
            .select()
            .eq("status", value: "accepted")
            .or("from_user.eq.\(userId.uuidString),to_user.eq.\(userId.uuidString)")
            .execute()
            .value

        var otherIds: [UUID] = []
        for r in requests {
            if r.fromUser == userId { otherIds.append(r.toUser) }
            else if r.toUser == userId { otherIds.append(r.fromUser) }
        }

        var profiles: [Profile] = []
        for oid in Set(otherIds) {
            if let p = try? await profile(id: oid) {
                profiles.append(p)
            }
        }
        return profiles.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
    }

    func profile(id: UUID) async throws -> Profile {
        try await client
            .from("profiles")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }
}

private struct FriendRequestInsert: Encodable {
    let fromUser: UUID
    let toUser: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case fromUser = "from_user"
        case toUser = "to_user"
        case status
    }
}

private struct FriendRequestStatusUpdate: Encodable {
    let status: String
}

private struct PendingFriendInviteInsert: Encodable {
    let inviterId: UUID
    let name: String
    let phone: String?
    let email: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case name, phone, email, status
        case inviterId = "inviter_id"
    }
}
