import Foundation
import Supabase

struct ExpenseService {
    let client: SupabaseClient

    func expenses(groupId: UUID) async throws -> [ExpenseWithSplits] {
        let expenses: [ExpenseRecord] = try await client
            .from("expenses")
            .select()
            .eq("group_id", value: groupId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value

        var out: [ExpenseWithSplits] = []
        for e in expenses {
            let splits: [SplitRecord] = try await client
                .from("splits")
                .select()
                .eq("expense_id", value: e.id.uuidString)
                .execute()
                .value
            let pendingSplits: [PendingSplitRecord] = (try? await client
                .from("pending_splits")
                .select()
                .eq("expense_id", value: e.id.uuidString)
                .execute()
                .value) ?? []
            out.append(ExpenseWithSplits(expense: e, splits: splits, pendingSplits: pendingSplits))
        }
        return out
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
