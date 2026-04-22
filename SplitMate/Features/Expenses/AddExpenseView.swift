internal import Auth
import SwiftUI

struct AddExpenseView: View {
    let group: GroupRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore

    @State private var members: [GroupMemberRow] = []
    @State private var pendingMembers: [PendingGroupMemberRow] = []
    @State private var profiles: [UUID: Profile] = [:]
    @State private var pendingInviteProfiles: [UUID: PendingFriendInvite] = [:]
    @State private var selectedUsers: Set<UUID> = []
    @State private var selectedPendingInvites: Set<UUID> = []
    @State private var paidByUserId: UUID?
    @State private var amountText = ""
    @State private var descriptionText = ""
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            modalNavBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    amountHero
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(SplitMateTheme.negativeRed)
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                    }
                    sectionLabel("Details")
                    detailsCard
                    sectionLabel("Split")
                    splitCard
                    splitPreviewCard
                }
                .padding(.bottom, 28)
            }
        }
        .background(SplitMateTheme.groupedBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadMembers()
        }
    }

    private var modalNavBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("‹ Cancel")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SplitMateTheme.brandPurple)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(SplitMateTheme.groupedBackground))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Add expense")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SplitMateTheme.labelPrimary)
            Spacer()
            Button {
                Task { await save() }
            } label: {
                Text("Save")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(SplitMateTheme.brandPurple))
            }
            .buttonStyle(.plain)
            .opacity(canSave && !busy ? 1 : 0.4)
            .disabled(!canSave || busy)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            Color.white
                .shadow(color: Color.black.opacity(0.04), radius: 0, y: 1)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SplitMateTheme.separator)
                .frame(height: 0.5)
        }
    }

    private var amountHero: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 3) {
                Text("₹")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color(red: 174 / 255, green: 174 / 255, blue: 178 / 255))
                    .padding(.top, 8)
                TextField("0", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .tracking(-2)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.top, 16)
            Text("tap to edit amount")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 174 / 255, green: 174 / 255, blue: 178 / 255))
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SplitMateTheme.labelSecondary)
            .tracking(0.3)
            .textCase(.uppercase)
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                emojiIconTile("📝", bg: Color(red: 243 / 255, green: 240 / 255, blue: 1))
                TextField("Description", text: $descriptionText)
                    .font(.system(size: 15))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
            }
            .padding(13)
            Divider().padding(.leading, 53)
            HStack(spacing: 10) {
                emojiIconTile("📅", bg: Color(red: 1, green: 240 / 255, blue: 245 / 255))
                Text(todayDetailLine)
                    .font(.system(size: 15))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                Spacer()
            }
            .padding(13)
            Divider().padding(.leading, 53)
            HStack(spacing: 10) {
                emojiIconTile(groupEmoji(for: group.name), bg: Color(red: 240 / 255, green: 244 / 255, blue: 1))
                Text(group.name)
                    .font(.system(size: 15))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                Spacer()
                Text("Group")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SplitMateTheme.brandPurple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(red: 237 / 255, green: 237 / 255, blue: 253 / 255)))
            }
            .padding(13)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .padding(.horizontal, 14)
    }

    private func emojiIconTile(_ emoji: String, bg: Color) -> some View {
        Text(emoji)
            .font(.system(size: 15))
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bg))
    }

    private var todayDetailLine: String {
        let ymd = Self.utcTodayString()
        let tail = monthDayFromExpenseDate(ymd)
        return "Today, \(tail)"
    }

    private func monthDayFromExpenseDate(_ ymd: String) -> String {
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

    private func groupEmoji(for name: String) -> String {
        let options = ["✈️", "🏠", "🏡", "🎉", "🍽️", "🚗", "💼", "🏖️"]
        return options[abs(name.hashValue) % options.count]
    }

    private var splitCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Paid by")
                    .font(.system(size: 15))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                Spacer()
                Menu {
                    ForEach(members.map(\.userId), id: \.self) { id in
                        Button {
                            paidByUserId = id
                        } label: {
                            if paidByUserId == id {
                                Label(userLabel(for: id), systemImage: "checkmark")
                            } else {
                                Text(userLabel(for: id))
                            }
                        }
                    }
                    if !pendingMembers.isEmpty {
                        Divider()
                        ForEach(pendingMembers.map(\.pendingInviteId), id: \.self) { pendingId in
                            Button {
                            } label: {
                                Text("\(pendingLabel(for: pendingId)) (Pending)")
                            }
                            .disabled(true)
                        }
                    }
                } label: {
                    Text(paidByLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SplitMateTheme.brandPurple)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(red: 237 / 255, green: 237 / 255, blue: 253 / 255)))
                }
            }
            .padding(13)
            Divider().padding(.leading, 14)
            HStack {
                Text("Split method")
                    .font(.system(size: 15))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                Spacer()
                Menu {
                    Button("Equally (everyone)") {
                        selectAllParticipants()
                    }
                    Divider()
                    ForEach(members.map(\.userId), id: \.self) { id in
                        Button {
                            toggleUser(id)
                        } label: {
                            if selectedUsers.contains(id) {
                                Label(userLabel(for: id), systemImage: "checkmark")
                            } else {
                                Text(userLabel(for: id))
                            }
                        }
                    }
                    ForEach(pendingMembers.map(\.pendingInviteId), id: \.self) { pendingId in
                        Button {
                            togglePending(pendingId)
                        } label: {
                            let title = "\(pendingLabel(for: pendingId)) (Pending)"
                            if selectedPendingInvites.contains(pendingId) {
                                Label(title, systemImage: "checkmark")
                            } else {
                                Text(title)
                            }
                        }
                    }
                } label: {
                    Text(splitMethodPillTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 26 / 255, green: 122 / 255, blue: 58 / 255))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(red: 234 / 255, green: 250 / 255, blue: 240 / 255)))
                }
            }
            .padding(13)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .padding(.horizontal, 14)
    }

    private var splitMethodPillTitle: String {
        let total = members.count + pendingMembers.count
        if participantCount == total, total > 0 {
            return "Equally"
        }
        if participantCount == 0 {
            return "None"
        }
        return "\(participantCount) selected"
    }

    private var splitPreviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Split preview")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SplitMateTheme.labelSecondary)
                    .textCase(.uppercase)
                    .tracking(0.3)
                Spacer()
                Text("Edit")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SplitMateTheme.brandPurple)
            }
            .padding(.bottom, 12)
            ForEach(splitPreviewRows()) { row in
                HStack(spacing: 8) {
                    Text(row.initial)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(row.avatarColor))
                    Text(row.label)
                        .font(.system(size: 13))
                        .foregroundStyle(SplitMateTheme.labelPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(red: 240 / 255, green: 240 / 255, blue: 245 / 255))
                            .frame(width: 60, height: 4)
                        Capsule()
                            .fill(SplitMateTheme.brandPurple)
                            .frame(width: 60 * row.barFraction, height: 4)
                    }
                    Text(SplitMateTheme.inrString(row.amount))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SplitMateTheme.brandPurple)
                        .frame(minWidth: 56, alignment: .trailing)
                }
                .padding(.bottom, 9)
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

    private struct SplitPreviewRow: Identifiable {
        let id: String
        let label: String
        let initial: String
        let amount: Double
        let barFraction: CGFloat
        let avatarColor: Color
    }

    private func splitPreviewRows() -> [SplitPreviewRow] {
        guard let total = amountValue, total > 0, participantCount > 0 else { return [] }
        let cents = Int((total * 100).rounded())
        let sortedUsers = selectedUsers.sorted { $0.uuidString < $1.uuidString }
        let sortedPending = selectedPendingInvites.sorted { $0.uuidString < $1.uuidString }
        let participantKeys = sortedUsers.map { "u:\($0.uuidString)" } + sortedPending.map { "p:\($0.uuidString)" }
        let count = participantKeys.count
        guard count > 0 else { return [] }
        let low = cents / count
        let extra = cents % count
        let maxShare = Double(low + (count > 0 ? 1 : 0)) / 100.0
        let denom = max(maxShare, 0.0001)

        let palette: [Color] = [
            SplitMateTheme.brandPurple,
            Color(red: 1, green: 107 / 255, blue: 107 / 255),
            Color(red: 78 / 255, green: 205 / 255, blue: 196 / 255),
            SplitMateTheme.positiveGreen,
            SplitMateTheme.orangeAccent
        ]

        var rows: [SplitPreviewRow] = []
        for (i, key) in participantKeys.enumerated() {
            let c = low + (i < extra ? 1 : 0)
            let share = Double(c) / 100
            let idString = String(key.dropFirst(2))
            guard let id = UUID(uuidString: idString) else { continue }
            let label: String
            let initial: String
            if key.hasPrefix("u:") {
                label = userLabel(for: id)
                initial = String(label.prefix(1)).uppercased()
            } else {
                let pl = pendingLabel(for: id)
                label = pl
                initial = String(pl.prefix(1)).uppercased()
            }
            let frac = CGFloat(share / denom)
            let color = palette[abs(id.hashValue) % palette.count]
            rows.append(SplitPreviewRow(id: key, label: label, initial: initial, amount: share, barFraction: frac, avatarColor: color))
        }
        return rows
    }

    private var amountValue: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        guard let amt = amountValue, amt > 0, participantCount > 0 else { return false }
        guard sessionStore.session?.user.id != nil, paidByUserId != nil else { return false }
        return true
    }

    private var participantCount: Int {
        selectedUsers.count + selectedPendingInvites.count
    }

    private var paidByLabel: String {
        guard let paidByUserId else { return "Select" }
        return userLabel(for: paidByUserId)
    }

    private func userLabel(for userId: UUID) -> String {
        if userId == sessionStore.session?.user.id {
            return "You"
        }
        if let username = profiles[userId]?.username, !username.isEmpty {
            return username
        }
        return userId.uuidString.prefix(8).description
    }

    private func pendingLabel(for pendingId: UUID) -> String {
        if let name = pendingInviteProfiles[pendingId]?.name, !name.isEmpty {
            return name
        }
        if let email = pendingInviteProfiles[pendingId]?.email, !email.isEmpty {
            return email
        }
        return "Pending user"
    }

    private func selectAllParticipants() {
        selectedUsers = Set(members.map(\.userId))
        selectedPendingInvites = Set(pendingMembers.map(\.pendingInviteId))
    }

    private func toggleUser(_ id: UUID) {
        if selectedUsers.contains(id) {
            selectedUsers.remove(id)
        } else {
            selectedUsers.insert(id)
        }
    }

    private func togglePending(_ id: UUID) {
        if selectedPendingInvites.contains(id) {
            selectedPendingInvites.remove(id)
        } else {
            selectedPendingInvites.insert(id)
        }
    }

    private func loadMembers() async {
        let gs = GroupService(client: sessionStore.client)
        let fs = FriendService(client: sessionStore.client)
        do {
            // Step 1: fetch membership rows in parallel so we know which ids
            // we actually need to resolve. Two round trips instead of two +
            // N + M sequential ones.
            async let membersFetch = gs.members(groupId: group.id)
            async let pendingMembersFetch = gs.pendingMembers(groupId: group.id)
            let (fetchedMembers, fetchedPending) = try await (membersFetch, pendingMembersFetch)

            members = fetchedMembers
            pendingMembers = fetchedPending

            // Step 2: two batched `IN (...)` queries in parallel – regardless
            // of how many members or pending invites the group has.
            let memberIds = fetchedMembers.map(\.userId)
            let inviteIds = fetchedPending.map(\.pendingInviteId)
            async let profilesFetch = fs.profiles(ids: memberIds)
            async let invitesFetch = fs.pendingInvites(ids: inviteIds)
            let (profileList, inviteList) = try await (profilesFetch, invitesFetch)

            profiles = Dictionary(uniqueKeysWithValues: profileList.map { ($0.id, $0) })
            pendingInviteProfiles = Dictionary(uniqueKeysWithValues: inviteList.map { ($0.id, $0) })

            selectAllParticipants()
            let me = sessionStore.session?.user.id
            if let me, fetchedMembers.contains(where: { $0.userId == me }) {
                paidByUserId = me
            } else {
                paidByUserId = fetchedMembers.first?.userId
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard sessionStore.session?.user.id != nil,
              let paidBy = paidByUserId,
              let total = amountValue, total > 0
        else { return }

        let count = participantCount
        guard count > 0 else { return }

        let cents = Int((total * 100).rounded())
        let sortedUsers = selectedUsers.sorted { $0.uuidString < $1.uuidString }
        let sortedPending = selectedPendingInvites.sorted { $0.uuidString < $1.uuidString }
        let participantKeys = sortedUsers.map { "u:\($0.uuidString)" } + sortedPending.map { "p:\($0.uuidString)" }
        let low = cents / participantKeys.count
        let extra = cents % count

        var userSplits: [(userId: UUID, amount: Double)] = []
        var pendingSplits: [(pendingInviteId: UUID, amount: Double)] = []

        let userSet = Set(sortedUsers)
        for (i, key) in participantKeys.enumerated() {
            let c = low + (i < extra ? 1 : 0)
            let share = Double(c) / 100
            let idString = String(key.dropFirst(2))
            guard let id = UUID(uuidString: idString) else { continue }
            if userSet.contains(id) {
                userSplits.append((userId: id, amount: share))
            } else {
                pendingSplits.append((pendingInviteId: id, amount: share))
            }
        }

        busy = true
        errorMessage = nil
        defer { busy = false }

        let today = Self.utcTodayString()
        do {
            try await ExpenseService(client: sessionStore.client).addExpense(
                groupId: group.id,
                paidBy: paidBy,
                description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: total,
                expenseDate: today,
                splits: userSplits,
                pendingSplits: pendingSplits
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func utcTodayString() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = calendar.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
