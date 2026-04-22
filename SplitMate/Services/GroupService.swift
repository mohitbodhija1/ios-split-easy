import Foundation
import Supabase

struct GroupService {
    let client: SupabaseClient

    /// Single PostgREST call: inner-join `group_members` so only groups the
    /// user is a member of are returned. Replaces the old two-trip pattern
    /// that also built an unbounded `or(id.eq.x,id.eq.y,…)` filter.
    func groups(for userId: UUID) async throws -> [GroupRecord] {
        try await client
            .from("groups")
            .select("*, group_members!inner(user_id)")
            .eq("group_members.user_id", value: userId.uuidString)
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

    /// Batched variant used by list screens so they can resolve membership for
    /// many groups in a single round trip instead of N.
    func members(for groupIds: [UUID]) async throws -> [UUID: [GroupMemberRow]] {
        guard !groupIds.isEmpty else { return [:] }
        let rows: [GroupMemberRow] = try await client
            .from("group_members")
            .select()
            .in("group_id", values: groupIds.map(\.uuidString))
            .execute()
            .value
        var out: [UUID: [GroupMemberRow]] = [:]
        for row in rows {
            out[row.groupId, default: []].append(row)
        }
        return out
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

    func pendingMembers(for groupIds: [UUID]) async throws -> [UUID: [PendingGroupMemberRow]] {
        guard !groupIds.isEmpty else { return [:] }
        let rows: [PendingGroupMemberRow] = try await client
            .from("pending_group_members")
            .select()
            .in("group_id", values: groupIds.map(\.uuidString))
            .order("created_at", ascending: false)
            .execute()
            .value
        var out: [UUID: [PendingGroupMemberRow]] = [:]
        for row in rows {
            out[row.groupId, default: []].append(row)
        }
        return out
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
    ///
    /// Previous implementation issued 1 + N queries (one per pair group).
    /// Now: 1 query for my pair groups, 1 query for all their members; then
    /// resolution happens client-side in O(M) where M is total member rows.
    func pairGroup(for userId: UUID, friendId: UUID) async throws -> GroupRecord? {
        let myPairGroups: [GroupRecord] = try await client
            .from("groups")
            .select("*, group_members!inner(user_id)")
            .eq("group_members.user_id", value: userId.uuidString)
            .eq("group_type", value: "pair")
            .execute()
            .value
        guard !myPairGroups.isEmpty else { return nil }

        let membersByGroup = try await members(for: myPairGroups.map(\.id))
        return myPairGroups.first { g in
            let ids = Set((membersByGroup[g.id] ?? []).map(\.userId))
            return ids.contains(friendId) && ids.contains(userId)
        }
    }

    /// Finds a group created by the user that already contains this pending invite.
    ///
    /// Replaces the 1 + N pattern with a single `pending_group_members` query
    /// followed by a single-row group fetch.
    func pendingInviteGroup(for userId: UUID, pendingInviteId: UUID) async throws -> GroupRecord? {
        let rows: [PendingGroupMemberRow] = try await client
            .from("pending_group_members")
            .select()
            .eq("pending_invite_id", value: pendingInviteId.uuidString)
            .eq("added_by", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        guard let first = rows.first else { return nil }
        return try await client
            .from("groups")
            .select()
            .eq("id", value: first.groupId.uuidString)
            .single()
            .execute()
            .value
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
