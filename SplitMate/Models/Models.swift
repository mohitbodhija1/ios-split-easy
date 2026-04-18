import Foundation

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    var username: String
    var email: String?
    var avatarUrl: String?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, username, email
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
    }
}

struct GroupRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date?
    var createdBy: UUID
    var groupType: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
        case createdBy = "created_by"
        case groupType = "group_type"
    }
}

struct GroupMemberRow: Codable, Hashable {
    var groupId: UUID
    var userId: UUID
    var joinedAt: Date?

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
    }
}

struct PendingGroupMemberRow: Codable, Identifiable, Hashable {
    let id: UUID
    var groupId: UUID
    var pendingInviteId: UUID
    var addedBy: UUID
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case pendingInviteId = "pending_invite_id"
        case addedBy = "added_by"
        case createdAt = "created_at"
    }
}

struct FriendRequest: Codable, Identifiable, Hashable {
    let id: UUID
    var fromUser: UUID
    var toUser: UUID
    var status: String
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case fromUser = "from_user"
        case toUser = "to_user"
        case createdAt = "created_at"
    }
}

struct PendingFriendInvite: Codable, Identifiable, Hashable {
    let id: UUID
    var inviterId: UUID
    var name: String
    var phone: String?
    var email: String
    var status: String
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, phone, email, status
        case inviterId = "inviter_id"
        case createdAt = "created_at"
    }
}

struct ExpenseRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var groupId: UUID
    var paidBy: UUID
    var amount: Double
    var description: String
    /// Postgres `date` is returned as `"YYYY-MM-DD"`.
    var expenseDate: String
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, amount, description
        case groupId = "group_id"
        case paidBy = "paid_by"
        case expenseDate = "expense_date"
        case createdAt = "created_at"
    }
}

struct SplitRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var expenseId: UUID
    var userId: UUID
    var amountOwed: Double

    enum CodingKeys: String, CodingKey {
        case id
        case expenseId = "expense_id"
        case userId = "user_id"
        case amountOwed = "amount_owed"
    }
}

struct PendingSplitRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var expenseId: UUID
    var pendingInviteId: UUID
    var amountOwed: Double

    enum CodingKeys: String, CodingKey {
        case id
        case expenseId = "expense_id"
        case pendingInviteId = "pending_invite_id"
        case amountOwed = "amount_owed"
    }
}

struct ExpenseWithSplits: Identifiable, Hashable {
    var expense: ExpenseRecord
    var splits: [SplitRecord]
    var pendingSplits: [PendingSplitRecord]

    var id: UUID { expense.id }
}

extension Double {
    var moneyFormatted: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: self)) ?? String(format: "%.2f", self)
    }
}
