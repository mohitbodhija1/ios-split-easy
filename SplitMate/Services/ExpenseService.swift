import Foundation
import Supabase

struct ExpenseService {
    let client: SupabaseClient

    /// Single round-trip: PostgREST embeds `splits` and `pending_splits` via
    /// foreign-key relationships, replacing the old 1 + 2·N query pattern.
    func expenses(groupId: UUID) async throws -> [ExpenseWithSplits] {
        let rows: [ExpenseWithSplitsDTO] = try await client
            .from("expenses")
            .select("*, splits(*), pending_splits(*)")
            .eq("group_id", value: groupId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map(\.asModel)
    }

    /// Load multiple groups' expenses in parallel, then flatten. Keeps a single
    /// round trip per group while avoiding a client-side for-await loop.
    func expenses(groupIds: [UUID]) async throws -> [UUID: [ExpenseWithSplits]] {
        guard !groupIds.isEmpty else { return [:] }
        return try await withThrowingTaskGroup(of: (UUID, [ExpenseWithSplits]).self) { taskGroup in
            for id in groupIds {
                taskGroup.addTask { (id, try await self.expenses(groupId: id)) }
            }
            var out: [UUID: [ExpenseWithSplits]] = [:]
            for try await (id, exps) in taskGroup {
                out[id] = exps
            }
            return out
        }
    }

    /// Inserts expense (paid_by must be current user per RLS) and split rows; validates totals.
    func addExpense(
        groupId: UUID,
        paidBy: UUID,
        description: String,
        amount: Double,
        expenseDate: String,
        splits: [(userId: UUID, amount: Double)],
        pendingSplits: [(pendingInviteId: UUID, amount: Double)]
    ) async throws {
        let splitSum = splits.reduce(0.0) { $0 + $1.amount } + pendingSplits.reduce(0.0) { $0 + $1.amount }
        guard abs(splitSum - amount) < 0.01 else {
            throw ExpenseServiceError.splitTotalMismatch
        }

        let expense: ExpenseRecord = try await client
            .from("expenses")
            .insert(
                NewExpenseRow(
                    groupId: groupId,
                    paidBy: paidBy,
                    amount: amount,
                    description: description,
                    expenseDate: expenseDate
                )
            )
            .select()
            .single()
            .execute()
            .value

        let splitRows = splits.map {
            NewSplitRow(expenseId: expense.id, userId: $0.userId, amountOwed: $0.amount)
        }
        if !splitRows.isEmpty {
            _ = try await client.from("splits").insert(splitRows).execute()
        }

        let pendingSplitRows = pendingSplits.map {
            NewPendingSplitRow(expenseId: expense.id, pendingInviteId: $0.pendingInviteId, amountOwed: $0.amount)
        }
        if !pendingSplitRows.isEmpty {
            _ = try await client.from("pending_splits").insert(pendingSplitRows).execute()
        }
    }

    func settleUp(
        groupId: UUID,
        payerId: UUID,
        receiverId: UUID,
        amount: Double
    ) async throws {
        let date = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        try await addExpense(
            groupId: groupId,
            paidBy: payerId,
            description: "Settle Up",
            amount: amount,
            expenseDate: date,
            splits: [(userId: receiverId, amount: amount)],
            pendingSplits: []
        )
    }

    func settleUpPending(
        groupId: UUID,
        recorderId: UUID,
        pendingInviteId: UUID,
        amount: Double
    ) async throws {
        let date = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        // To avoid expenses_amount_check (amount > 0), we use the actual settlement amount.
        // We record that the recorder paid 'amount', but we assign a negative split to the pending friend.
        // This transfers the balance correctly while keeping the expense amount positive.
        try await addExpense(
            groupId: groupId,
            paidBy: recorderId,
            description: "Settle Up",
            amount: amount,
            expenseDate: date,
            splits: [(userId: recorderId, amount: 2 * amount)],
            pendingSplits: [(pendingInviteId: pendingInviteId, amount: -amount)]
        )
    }
}

enum ExpenseServiceError: LocalizedError {
    case splitTotalMismatch

    var errorDescription: String? {
        switch self {
        case .splitTotalMismatch:
            return "Split amounts must add up to the expense total."
        }
    }
}

private struct NewExpenseRow: Encodable {
    let groupId: UUID
    let paidBy: UUID
    let amount: Double
    let description: String
    let expenseDate: String

    enum CodingKeys: String, CodingKey {
        case amount, description
        case groupId = "group_id"
        case paidBy = "paid_by"
        case expenseDate = "expense_date"
    }
}

private struct NewSplitRow: Encodable {
    let expenseId: UUID
    let userId: UUID
    let amountOwed: Double

    enum CodingKeys: String, CodingKey {
        case expenseId = "expense_id"
        case userId = "user_id"
        case amountOwed = "amount_owed"
    }
}

private struct NewPendingSplitRow: Encodable {
    let expenseId: UUID
    let pendingInviteId: UUID
    let amountOwed: Double

    enum CodingKeys: String, CodingKey {
        case expenseId = "expense_id"
        case pendingInviteId = "pending_invite_id"
        case amountOwed = "amount_owed"
    }
}

/// Decodes the flat PostgREST response shape produced by
/// `select("*, splits(*), pending_splits(*)")` and maps it into the
/// nested `ExpenseWithSplits` model used by the views.
private struct ExpenseWithSplitsDTO: Decodable {
    let id: UUID
    let groupId: UUID
    let paidBy: UUID
    let amount: Double
    let description: String
    let expenseDate: String
    let createdAt: Date?
    let splits: [SplitRecord]
    let pendingSplits: [PendingSplitRecord]

    enum CodingKeys: String, CodingKey {
        case id, amount, description, splits
        case groupId = "group_id"
        case paidBy = "paid_by"
        case expenseDate = "expense_date"
        case createdAt = "created_at"
        case pendingSplits = "pending_splits"
    }

    var asModel: ExpenseWithSplits {
        ExpenseWithSplits(
            expense: ExpenseRecord(
                id: id,
                groupId: groupId,
                paidBy: paidBy,
                amount: amount,
                description: description,
                expenseDate: expenseDate,
                createdAt: createdAt
            ),
            splits: splits,
            pendingSplits: pendingSplits
        )
    }
}
