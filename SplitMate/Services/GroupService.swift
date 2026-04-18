import Foundation
import Supabase

struct GroupService {
    let client: SupabaseClient

    func myGroupIds(userId: UUID) async throws -> [UUID] {
        struct Row: Decodable {
            let groupId: UUID
            enum CodingKeys: String, CodingKey {
                case groupId = "group_id"
            }
        }
        let rows: [Row] = try await client
            .from("group_members")
            .select("group_id")
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        return rows.map(\.groupId)
    }

    func groups(for userId: UUID) async throws -> [GroupRecord] {
        let ids = try await myGroupIds(userId: userId)
        guard !ids.isEmpty else { return [] }
        let orFilter = ids.map { "id.eq.\($0.uuidString)" }.joined(separator: ",")
        return try await client
            .from("groups")
            .select()
            .or(orFilter)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func members(groupId: UUID) async throws -> [GroupMemberRow] {
        try await client
            .from("group_members")
            .select()
            .eq("group_id", value: groupId.uuidString)
            .execute()
            .value
    }

    func pendingMembers(groupId: UUID) async throws -> [PendingGroupMemberRow] {
        try await client
            .from("pending_group_members")
            .select()
            .eq("group_id", value: groupId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Creates a group and adds `creatorId` as the first member.
    func createGroup(name: String, groupType: String, creatorId: UUID) async throws -> GroupRecord {
        let inserted: GroupRecord = try await client
            .from("groups")
            .insert(NewGroupRow(name: name, createdBy: creatorId, groupType: groupType))
            .select()
            .single()
            .execute()
            .value

        try await client
            .from("group_members")
            .insert(GroupMemberInsert(groupId: inserted.id, userId: creatorId))
            .execute()

        return inserted
    }

    /// Adds a user to a group (caller must already be a member per RLS).
    func addMember(groupId: UUID, userId: UUID) async throws {
        try await client
            .from("group_members")
            .insert(GroupMemberInsert(groupId: groupId, userId: userId))
            .execute()
    }

    func addPendingMember(groupId: UUID, pendingInviteId: UUID, addedBy: UUID) async throws {
        try await client
            .from("pending_group_members")
            .insert(
                PendingGroupMemberInsert(
                    groupId: groupId,
                    pendingInviteId: pendingInviteId,
                    addedBy: addedBy
                )
            )
            .execute()
    }

    /// Hidden pair group for 1:1 splitting (both users are members).
    func pairGroup(for userId: UUID, friendId: UUID) async throws -> GroupRecord? {
        let mine = try await groups(for: userId)
        for g in mine where g.groupType == "pair" {
            let mems = try await members(groupId: g.id)
            let ids = Set(mems.map(\.userId))
            if ids.contains(friendId), ids.contains(userId) {
                return g
            }
        }
        return nil
    }

    /// Finds a group created by the user that already contains this pending invite.
    func pendingInviteGroup(for userId: UUID, pendingInviteId: UUID) async throws -> GroupRecord? {
        let mine = try await groups(for: userId)
        for g in mine {
            let pending = try await pendingMembers(groupId: g.id)
            if pending.contains(where: { $0.pendingInviteId == pendingInviteId }) {
                return g
            }
        }
        return nil
    }

    /// Creates (or returns existing) group dedicated to a pending friend so expenses can be tracked.
    func ensurePendingExpenseGroup(creatorId: UUID, invite: PendingFriendInvite) async throws -> GroupRecord {
        if let existing = try await pendingInviteGroup(for: creatorId, pendingInviteId: invite.id) {
            return existing
        }
        let title = "Pending: \(invite.name)"
        let group = try await createGroup(name: title, groupType: "household", creatorId: creatorId)
        try await addPendingMember(groupId: group.id, pendingInviteId: invite.id, addedBy: creatorId)
        return group
    }

    /// Hidden pair group for 1:1 splitting (both users are members).
    func ensurePairGroup(creatorId: UUID, friendId: UUID) async throws -> GroupRecord {
        if let existing = try await pairGroup(for: creatorId, friendId: friendId) {
            return existing
        }
        let friendProfile = try await FriendService(client: client).profile(id: friendId)
        let title = "Pair: \(friendProfile.username)"
        let group = try await createGroup(name: title, groupType: "pair", creatorId: creatorId)
        try await addMember(groupId: group.id, userId: friendId)
        return group
    }
}

private struct NewGroupRow: Encodable {
    let name: String
    let createdBy: UUID
    let groupType: String

    enum CodingKeys: String, CodingKey {
        case name
        case createdBy = "created_by"
        case groupType = "group_type"
    }
}

private struct GroupMemberInsert: Encodable {
    let groupId: UUID
    let userId: UUID

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case userId = "user_id"
    }
}

private struct PendingGroupMemberInsert: Encodable {
    let groupId: UUID
    let pendingInviteId: UUID
    let addedBy: UUID

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case pendingInviteId = "pending_invite_id"
        case addedBy = "added_by"
    }
}
