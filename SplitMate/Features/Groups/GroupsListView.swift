internal import Auth
import SwiftUI

struct GroupsListView: View {
    @Environment(SessionStore.self) private var sessionStore
    @State private var groups: [GroupRecord] = []
    @State private var summaries: [UUID: GroupListSummary] = [:]
    @State private var errorMessage: String?
    @State private var showCreate = false
    @State private var isLoadingGroups = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    if isLoadingGroups {
                        ProgressView("Loading groups…")
                            .tint(SplitMateTheme.brandPurple)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(SplitMateTheme.negativeRed)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 8)
                    }
                    if !isLoadingGroups || !groups.isEmpty {
                        netBalanceBanner
                    }
                    sectionLabel("Your groups")
                    VStack(spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, g in
                            NavigationLink(value: g) {
                                groupRow(g, summary: summaries[g.id])
                            }
                            .buttonStyle(.plain)
                            if index < groups.count - 1 {
                                Divider()
                                    .background(SplitMateTheme.separator.opacity(0.6))
                                    .padding(.leading, 68)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white)
                    )
                    .padding(.horizontal, 14)
                }
                .padding(.bottom, 24)
            }
            .background(SplitMateTheme.groupedBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: GroupRecord.self) { g in
                GroupDetailView(group: g)
            }
            .sheet(isPresented: $showCreate) {
                CreateGroupSheet(onCreated: { new in
                    groups.insert(new, at: 0)
                })
            }
            .task(id: sessionStore.session?.user.id) {
                await load()
            }
            .refreshable {
                await load()
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            Text("Groups")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(SplitMateTheme.labelPrimary)
                .tracking(-0.5)
            Spacer()
            Button {
                showCreate = true
            } label: {
                Text("+")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(SplitMateTheme.brandPurple)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private var netBalanceBanner: some View {
        let total = groups.reduce(0.0) { partial, g in
            partial + (summaries[g.id]?.netForCurrentUser ?? 0)
        }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Net balance")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(formattedNetBanner(total))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            Spacer()
            Text("Settle up")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.2)))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [SplitMateTheme.brandPurple, SplitMateTheme.brandPurpleSoft],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
    }

    private func formattedNetBanner(_ net: Double) -> String {
        if abs(net) < 0.01 {
            return SplitMateTheme.inrString(0)
        }
        let sign = net > 0 ? "+" : ""
        return sign + SplitMateTheme.inrString(net)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SplitMateTheme.labelSecondary)
            .tracking(0.3)
            .textCase(.uppercase)
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
    }

    private func groupRow(_ g: GroupRecord, summary: GroupListSummary?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(groupEmoji(for: g))
                .font(.system(size: 20))
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(iconBackground(for: g)))
            VStack(alignment: .leading, spacing: 2) {
                Text(g.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                Text(subtitle(for: g, summary: summary))
                    .font(.system(size: 12))
                    .foregroundStyle(SplitMateTheme.labelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            balanceColumn(summary: summary)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 192 / 255, green: 192 / 255, blue: 200 / 255))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func balanceColumn(summary: GroupListSummary?) -> some View {
        let net = summary?.netForCurrentUser ?? 0
        if abs(net) < 0.01 {
            VStack(alignment: .trailing, spacing: 1) {
                Text(SplitMateTheme.inrString(0))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SplitMateTheme.labelSecondary)
                Text("settled")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 174 / 255, green: 174 / 255, blue: 178 / 255))
            }
        } else if net > 0 {
            VStack(alignment: .trailing, spacing: 1) {
                Text("+" + inrCompact(net))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SplitMateTheme.positiveGreen)
                Text("owed to you")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 174 / 255, green: 174 / 255, blue: 178 / 255))
            }
        } else {
            VStack(alignment: .trailing, spacing: 1) {
                Text(inrCompact(net))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SplitMateTheme.negativeRed)
                Text("you owe")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 174 / 255, green: 174 / 255, blue: 178 / 255))
            }
        }
    }

    private func inrCompact(_ amount: Double) -> String {
        SplitMateTheme.inrString(amount)
    }

    private func subtitle(for g: GroupRecord, summary: GroupListSummary?) -> String {
        let members = summary?.memberCount ?? 0
        let expenses = summary?.expenseCount ?? 0
        if g.groupType == "pair" {
            return "Pair · \(expenses) expenses"
        }
        return "\(members) members · \(expenses) expenses"
    }

    private func iconBackground(for g: GroupRecord) -> Color {
        let palette: [Color] = [
            Color(red: 1, green: 240 / 255, blue: 240 / 255),
            Color(red: 240 / 255, green: 244 / 255, blue: 1),
            Color(red: 240 / 255, green: 250 / 255, blue: 242 / 255),
            Color(red: 1, green: 251 / 255, blue: 240 / 255)
        ]
        return palette[abs(g.name.hashValue) % palette.count]
    }

    private func groupEmoji(for g: GroupRecord) -> String {
        let options = ["🏠", "✈️", "🏡", "🎉", "🍽️", "🚗", "💼", "🏖️"]
        return options[abs(g.name.hashValue) % options.count]
    }

    private func load() async {
        errorMessage = nil
        isLoadingGroups = true
        defer { isLoadingGroups = false }
        guard let uid = sessionStore.session?.user.id else { return }
        let gs = GroupService(client: sessionStore.client)
        let es = ExpenseService(client: sessionStore.client)
        do {
            groups = try await gs.groups(for: uid)
            var map: [UUID: GroupListSummary] = [:]
            for g in groups {
                let mems = try await gs.members(groupId: g.id)
                let pending = (try? await gs.pendingMembers(groupId: g.id)) ?? []
                let exps = try await es.expenses(groupId: g.id)
                let net = groupNetBalance(currentUserId: uid, expenses: exps)
                map[g.id] = GroupListSummary(
                    memberCount: mems.count + pending.count,
                    expenseCount: exps.count,
                    netForCurrentUser: net
                )
            }
            summaries = map
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct GroupListSummary {
    let memberCount: Int
    let expenseCount: Int
    let netForCurrentUser: Double
}

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

private struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore

    var onCreated: (GroupRecord) -> Void

    @State private var name = ""
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                Section("Group name") {
                    TextField("Trip, home, …", text: $name)
                }
                Section {
                    Button("Create") {
                        Task {
                            await create()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                }
            }
            .navigationTitle("New group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func create() async {
        guard let uid = sessionStore.session?.user.id else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let g = try await GroupService(client: sessionStore.client)
                .createGroup(name: name.trimmingCharacters(in: .whitespacesAndNewlines), groupType: "household", creatorId: uid)
            onCreated(g)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
