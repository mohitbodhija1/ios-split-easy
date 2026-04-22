internal import Auth
import SwiftUI

struct GroupDetailView: View {
    let group: GroupRecord
    @Environment(SessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var expenses: [ExpenseWithSplits] = []
    @State private var members: [GroupMemberRow] = []
    @State private var pendingMembers: [PendingGroupMemberRow] = []
    @State private var profiles: [UUID: Profile] = [:]
    @State private var pendingInviteProfiles: [UUID: PendingFriendInvite] = [:]
    @State private var errorMessage: String?
    @State private var showAddExpense = false
    @State private var showAddMember = false
    @State private var isLoadingDetail = false
    @State private var hasLoadedGroupOnce = false
    @State private var lastLoadedGroupId: UUID?

    private var currentUserId: UUID? { sessionStore.session?.user.id }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroHeader
                    memberStrip
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(SplitMateTheme.negativeRed)
                            .padding(.horizontal, 18)
                            .padding(.top, 8)
                    }
                    if !settlementRows.isEmpty {
                        settleStrip
                    }
                    expensesSection
                    expenseFeed
                }
                .padding(.bottom, 32)
            }
            if isLoadingDetail {
                ZStack {
                    SplitMateTheme.groupedBackground.opacity(0.92)
                    ProgressView("Loading group…")
                        .tint(SplitMateTheme.brandPurple)
                }
                .allowsHitTesting(true)
            }
        }
        .background(SplitMateTheme.groupedBackground)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAddExpense, onDismiss: {
            Task { await reload() }
        }) {
            NavigationStack {
                AddExpenseView(group: group)
            }
        }
        .sheet(isPresented: $showAddMember) {
            AddMemberSheet(group: group, onAdded: {
                Task { await reload() }
            })
        }
        .task(id: group.id) {
            if lastLoadedGroupId != group.id {
                hasLoadedGroupOnce = false
                lastLoadedGroupId = group.id
            }
            await reload()
        }
        .refreshable {
            await reload()
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Text("‹")
                        .font(.system(size: 18, weight: .medium))
                    Text("Groups")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 10)

            Text(groupEmoji(for: group.name))
                .font(.system(size: 26))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.18)))
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            Text(group.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.white)
                .tracking(-0.4)
                .padding(.horizontal, 18)

            Text(heroSubtitle)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.65))
                .padding(.horizontal, 18)
                .padding(.top, 2)

            HStack(spacing: 8) {
                statPill(value: SplitMateTheme.inrString(totalSpent), label: "Total spent")
                statPill(value: SplitMateTheme.inrString(perPersonApprox), label: "Per person")
                statPill(
                    value: youAreOwedFormatted,
                    label: youAreOwed >= 0 ? "You're owed" : "You owe",
                    valueColor: youAreOwed >= 0
                        ? Color(red: 134 / 255, green: 239 / 255, blue: 172 / 255)
                        : Color(red: 1, green: 180 / 255, blue: 180 / 255)
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    SplitMateTheme.brandPurple,
                    Color(red: 155 / 255, green: 93 / 255, blue: 229 / 255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var heroSubtitle: String {
        let n = members.count + pendingMembers.count
        let memberPart = "\(n) member\(n == 1 ? "" : "s")"
        if let range = expenseDateRangeText {
            return "\(memberPart) · \(range)"
        }
        return memberPart
    }

    private var expenseDateRangeText: String? {
        let dates = expenses.map(\.expense.expenseDate).sorted()
        guard let first = dates.first, let last = dates.last else { return nil }
        if first == last { return shortMonthDay(from: first) }
        return "\(shortMonthDay(from: first)) – \(shortMonthDay(from: last))"
    }

    private var totalSpent: Double {
        expenses.reduce(0) { $0 + $1.expense.amount }
    }

    private var perPersonApprox: Double {
        let n = members.count + pendingMembers.count
        guard n > 0 else { return 0 }
        return totalSpent / Double(n)
    }

    private var youAreOwed: Double {
        guard let uid = currentUserId else { return 0 }
        return groupNetBalance(currentUserId: uid, expenses: expenses)
    }

    private var youAreOwedFormatted: String {
        let v = youAreOwed
        if abs(v) < 0.01 { return SplitMateTheme.inrString(0) }
        let sign = v > 0 ? "+" : ""
        return sign + SplitMateTheme.inrString(v)
    }

    private func statPill(value: String, label: String, valueColor: Color = .white) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(0.4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.12)))
    }

    // MARK: - Members

    private var memberStrip: some View {
        HStack(spacing: 0) {
            let displayMembers = members.prefix(5)
            ForEach(Array(displayMembers.enumerated()), id: \.element.userId) { index, m in
                avatarInitial(for: m.userId)
                    .offset(x: index == 0 ? 0 : -8)
            }
            if members.count > 5 {
                Text("+\(members.count - 5)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 110 / 255, green: 110 / 255, blue: 115 / 255))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(red: 232 / 255, green: 232 / 255, blue: 237 / 255)))
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: -8)
            }
            Text("\(members.count + pendingMembers.count) members")
                .font(.system(size: 12))
                .foregroundStyle(SplitMateTheme.labelSecondary)
                .padding(.leading, 10)
            Spacer(minLength: 8)
            Button {
                showAddMember = true
            } label: {
                Text("+ Add")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SplitMateTheme.brandPurple)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(red: 237 / 255, green: 237 / 255, blue: 253 / 255)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .background(Color.white)
    }

    private func avatarInitial(for userId: UUID) -> some View {
        let name = profiles[userId]?.username ?? "?"
        let initial = String(name.prefix(1)).uppercased()
        let bg = avatarColor(for: userId)
        return Text(initial)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 32, height: 32)
            .background(Circle().fill(bg))
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }

    // MARK: - Settlements

    private var settlementRows: [(from: UUID, to: UUID, amount: Double)] {
        var nets: [UUID: Double] = [:]
        for m in members {
            nets[m.userId] = memberNetInGroup(userId: m.userId, expenses: expenses)
        }
        return minimalSettlements(balances: nets)
    }

    private var settleStrip: some View {
        let rows = Array(settlementRows.prefix(4))
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Suggested settlements")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SplitMateTheme.labelSecondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Spacer()
                if settlementRows.count > 4 {
                    Text("View all")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SplitMateTheme.brandPurple)
                }
            }
            .padding(.bottom, 12)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                settlementRowView(from: row.from, to: row.to, amount: row.amount)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private func settlementRowView(from: UUID, to: UUID, amount: Double) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                miniAvatar(userId: from)
                Text(displayName(for: from))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("→")
                .font(.system(size: 14))
                .foregroundStyle(SplitMateTheme.labelSecondary)
            HStack(spacing: 6) {
                miniAvatar(userId: to)
                Text(displayName(for: to))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(SplitMateTheme.inrString(amount))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SplitMateTheme.brandPurple)
        }
        .padding(.bottom, 8)
    }

    private func miniAvatar(userId: UUID) -> some View {
        let name = profiles[userId]?.username ?? "?"
        let initial = String(name.prefix(1)).uppercased()
        return Text(initial)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(avatarColor(for: userId)))
    }

    private func displayName(for userId: UUID) -> String {
        if userId == currentUserId { return "You" }
        return profiles[userId]?.username ?? userId.uuidString.prefix(6).description
    }

    // MARK: - Expenses

    private var expensesSection: some View {
        HStack {
            Text("Expenses")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SplitMateTheme.labelSecondary)
                .textCase(.uppercase)
                .tracking(0.4)
            Spacer()
            Button {
                showAddExpense = true
            } label: {
                Text("+ Add")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SplitMateTheme.brandPurple)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var expenseFeed: some View {
        VStack(spacing: 0) {
            if expenses.isEmpty {
                Text("No expenses yet.")
                    .font(.subheadline)
                    .foregroundStyle(SplitMateTheme.labelSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(Array(expenses.enumerated()), id: \.element.id) { index, item in
                    expenseRow(item)
                    if index < expenses.count - 1 {
                        Divider()
                            .background(Color(red: 240 / 255, green: 240 / 255, blue: 245 / 255))
                            .padding(.leading, 64)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .padding(.horizontal, 14)
    }

    private func expenseRow(_ item: ExpenseWithSplits) -> some View {
        let emoji = expenseEmoji(for: item.expense.description)
        let bg = expenseIconBackground(for: item.expense.description)
        let paidName = paidByLabel(item.expense.paidBy)
        let dateLine = shortMonthDay(from: item.expense.expenseDate)
        let (shareText, shareStyle) = currentUserShareLine(item: item)

        return HStack(alignment: .center, spacing: 12) {
            Text(emoji)
                .font(.system(size: 18))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(bg))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.expense.description.isEmpty ? "Expense" : item.expense.description)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                Text("Paid by \(paidName) · \(dateLine)")
                    .font(.system(size: 11))
                    .foregroundStyle(SplitMateTheme.labelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                Text(SplitMateTheme.inrString(item.expense.amount))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                Text(shareText)
                    .font(.system(size: 11))
                    .foregroundStyle(shareStyle)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func paidByLabel(_ paidBy: UUID) -> String {
        if paidBy == currentUserId { return "you" }
        return profiles[paidBy]?.username ?? "member"
    }

    private func currentUserShareLine(item: ExpenseWithSplits) -> (String, Color) {
        guard let uid = currentUserId else { return ("", SplitMateTheme.labelSecondary) }
        let mySplit = item.splits.first(where: { $0.userId == uid })?.amountOwed ?? 0
        if item.expense.paidBy == uid {
            let back = item.expense.amount - mySplit
            if back > 0.01 {
                return ("you get back \(SplitMateTheme.inrString(back))", SplitMateTheme.positiveGreen)
            }
            return ("—", SplitMateTheme.labelSecondary)
        }
        if mySplit > 0.01 {
            return ("you owe \(SplitMateTheme.inrString(mySplit))", SplitMateTheme.negativeRed)
        }
        if allSplitsEqual(item), item.splits.count > 1 {
            let each = item.splits.first?.amountOwed ?? 0
            return ("\(SplitMateTheme.inrString(each)) each", SplitMateTheme.labelSecondary)
        }
        return ("—", SplitMateTheme.labelSecondary)
    }

    private func allSplitsEqual(_ item: ExpenseWithSplits) -> Bool {
        guard let first = item.splits.first?.amountOwed else { return false }
        return item.splits.allSatisfy { abs($0.amountOwed - first) < 0.01 }
    }

    private func reload() async {
        errorMessage = nil
        let showBlockingLoader = !hasLoadedGroupOnce
        if showBlockingLoader { isLoadingDetail = true }
        defer {
            if showBlockingLoader {
                isLoadingDetail = false
                hasLoadedGroupOnce = true
            }
        }
        let client = sessionStore.client
        let gs = GroupService(client: client)
        let es = ExpenseService(client: client)
        let fs = FriendService(client: client)
        do {
            // Three top-level fetches run in parallel.
            async let membersFetch = gs.members(groupId: group.id)
            async let pendingMembersFetch = gs.pendingMembers(groupId: group.id)
            async let expensesFetch = es.expenses(groupId: group.id)
            let (fetchedMembers, fetchedPending, fetchedExpenses) = try await (membersFetch, pendingMembersFetch, expensesFetch)

            members = fetchedMembers
            pendingMembers = fetchedPending
            expenses = fetchedExpenses

            // Collect every profile / invite id we need in one shot, then two
            // batched `.in` queries instead of one per row.
            var profileIds = Set<UUID>(fetchedMembers.map(\.userId))
            for e in fetchedExpenses { profileIds.insert(e.expense.paidBy) }
            let inviteIds = Set(fetchedPending.map(\.pendingInviteId))

            async let profilesFetch = fs.profiles(ids: Array(profileIds))
            async let invitesFetch = fs.pendingInvites(ids: Array(inviteIds))
            let (profileList, inviteList) = try await (profilesFetch, invitesFetch)

            profiles = Dictionary(uniqueKeysWithValues: profileList.map { ($0.id, $0) })
            pendingInviteProfiles = Dictionary(uniqueKeysWithValues: inviteList.map { ($0.id, $0) })
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Group detail helpers

private func groupNetBalance(currentUserId: UUID, expenses: [ExpenseWithSplits]) -> Double {
    var net = 0.0
    for item in expenses {
        if item.expense.paidBy == currentUserId {
            for s in item.splits where s.userId != currentUserId {
                net += s.amountOwed
            }
            for ps in item.pendingSplits {
                net += ps.amountOwed
            }
        } else {
            if let mySplit = item.splits.first(where: { $0.userId == currentUserId }) {
                net -= mySplit.amountOwed
            }
        }
    }
    return net
}

private func memberNetInGroup(userId: UUID, expenses: [ExpenseWithSplits]) -> Double {
    var net = 0.0
    for item in expenses {
        if item.expense.paidBy == userId {
            for s in item.splits where s.userId != userId {
                net += s.amountOwed
            }
            net += item.pendingSplits.reduce(0) { $0 + $1.amountOwed }
        } else {
            if let mine = item.splits.first(where: { $0.userId == userId }) {
                net -= mine.amountOwed
            }
        }
    }
    return net
}

private func minimalSettlements(balances: [UUID: Double]) -> [(from: UUID, to: UUID, amount: Double)] {
    var debtors: [(UUID, Double)] = balances.compactMap { id, v in
        v < -0.01 ? (id, -v) : nil
    }.sorted { $0.1 > $1.1 }
    var creditors: [(UUID, Double)] = balances.compactMap { id, v in
        v > 0.01 ? (id, v) : nil
    }.sorted { $0.1 > $1.1 }

    var edges: [(UUID, UUID, Double)] = []
    var di = 0
    var ci = 0
    while di < debtors.count && ci < creditors.count {
        let pay = min(debtors[di].1, creditors[ci].1)
        if pay > 0.0001 {
            edges.append((debtors[di].0, creditors[ci].0, pay))
        }
        var d = debtors[di]
        d.1 -= pay
        debtors[di] = d
        var c = creditors[ci]
        c.1 -= pay
        creditors[ci] = c
        if debtors[di].1 < 0.0001 { di += 1 }
        if creditors[ci].1 < 0.0001 { ci += 1 }
    }
    return edges
}

private func groupEmoji(for name: String) -> String {
    let options = ["✈️", "🏠", "🏡", "🎉", "🍽️", "🚗", "💼", "🏖️"]
    return options[abs(name.hashValue) % options.count]
}

private func expenseEmoji(for description: String) -> String {
    let options = ["🍹", "🏨", "🛵", "🍕", "🚢", "🛒", "☕️", "🎫", "💡", "🎬"]
    return options[abs(description.hashValue) % options.count]
}

private func expenseIconBackground(for description: String) -> Color {
    let palette: [Color] = [
        Color(red: 1, green: 251 / 255, blue: 240 / 255),
        Color(red: 240 / 255, green: 244 / 255, blue: 1),
        Color(red: 240 / 255, green: 250 / 255, blue: 248 / 255),
        Color(red: 240 / 255, green: 250 / 255, blue: 242 / 255),
        Color(red: 243 / 255, green: 240 / 255, blue: 1)
    ]
    return palette[abs(description.hashValue) % palette.count]
}

private func avatarColor(for userId: UUID) -> Color {
    let palette: [Color] = [
        SplitMateTheme.brandPurple,
        Color(red: 1, green: 107 / 255, blue: 107 / 255),
        Color(red: 78 / 255, green: 205 / 255, blue: 196 / 255),
        Color(red: 1, green: 217 / 255, blue: 61 / 255),
        SplitMateTheme.positiveGreen
    ]
    return palette[abs(userId.hashValue) % palette.count]
}

private func shortMonthDay(from ymd: String) -> String {
    let parts = ymd.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return ymd }
    var c = DateComponents()
    c.year = parts[0]
    c.month = parts[1]
    c.day = parts[2]
    let cal = Calendar(identifier: .gregorian)
    guard let date = cal.date(from: c) else { return ymd }
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f.string(from: date)
}

private struct AddMemberSheet: View {
    let group: GroupRecord
    var onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore

    @State private var approvedFriends: [Profile] = []
    @State private var pendingInvites: [PendingFriendInvite] = []
    @State private var existingMemberIds: Set<UUID> = []
    @State private var existingPendingInviteIds: Set<UUID> = []
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                if approvedFriends.isEmpty, pendingInvites.isEmpty {
                    Text("No approved or pending friends yet.")
                        .foregroundStyle(.secondary)
                }
                if !approvedFriends.isEmpty {
                    Section("Approved Friends") {
                        ForEach(approvedFriends) { friend in
                            HStack {
                                Text(friend.username)
                                Spacer()
                                if existingMemberIds.contains(friend.id) {
                                    Text("In group")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button("Add") {
                                        Task { await add(friend) }
                                    }
                                    .disabled(busy)
                                }
                            }
                        }
                    }
                }
                if !pendingInvites.isEmpty {
                    Section("Pending Friends") {
                        ForEach(pendingInvites) { invite in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(invite.name)
                                    Text(invite.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if existingPendingInviteIds.contains(invite.id) {
                                    Text("In group")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button("Add") {
                                        Task { await addPending(invite) }
                                    }
                                    .disabled(busy)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadCandidates()
            }
        }
    }

    private func loadCandidates() async {
        guard let uid = sessionStore.session?.user.id else { return }
        let friendService = FriendService(client: sessionStore.client)
        let groupService = GroupService(client: sessionStore.client)
        do {
            // All four independent lookups in parallel; roughly 4x faster than
            // the old sequential chain when the DB round trip dominates.
            async let approved = friendService.acceptedFriends(for: uid)
            async let invites = friendService.pendingInvites(for: uid)
            async let members = groupService.members(groupId: group.id)
            async let pendingMembers = groupService.pendingMembers(groupId: group.id)
            let (fetchedApproved, fetchedInvites, fetchedMembers, fetchedPending) =
                try await (approved, invites, members, pendingMembers)

            approvedFriends = fetchedApproved
            pendingInvites = fetchedInvites
            existingMemberIds = Set(fetchedMembers.map(\.userId))
            existingPendingInviteIds = Set(fetchedPending.map(\.pendingInviteId))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add(_ friend: Profile) async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await GroupService(client: sessionStore.client).addMember(groupId: group.id, userId: friend.id)
            onAdded()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addPending(_ invite: PendingFriendInvite) async {
        guard let uid = sessionStore.session?.user.id else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await GroupService(client: sessionStore.client).addPendingMember(
                groupId: group.id,
                pendingInviteId: invite.id,
                addedBy: uid
            )
            onAdded()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
