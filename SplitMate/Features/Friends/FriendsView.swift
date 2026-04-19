internal import Auth
import SwiftUI

struct FriendsView: View {
    @Environment(SessionStore.self) private var sessionStore

    @State private var incoming: [FriendRequest] = []
    @State private var friends: [Profile] = []
    @State private var pendingInvites: [PendingFriendInvite] = []
    @State private var incomingProfiles: [UUID: Profile] = [:]
    @State private var friendNetBalances: [UUID: Double] = [:]
    @State private var pendingInviteTotals: [UUID: Double] = [:]
    @State private var errorMessage: String?
    @State private var pendingPairFriend: Profile?
    @State private var selectedFriendForDetail: Profile?
    @State private var selectedPendingInviteForDetail: PendingFriendInvite?
    @State private var pendingExpenseInvite: PendingFriendInvite?
    @State private var isLoading = false
    @State private var showingAddFriendSheet = false
    @State private var searchQuery = ""

    private var filteredFriends: [Profile] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return friends }
        return friends.filter { f in
            f.username.lowercased().contains(q)
                || (f.email?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    if isLoading {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(SplitMateTheme.negativeRed)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 8)
                    }
                    searchBar
                    if !incoming.isEmpty {
                        incomingRequestsSummaryCard
                        incomingRequestsActionsCard
                    }
                    if !pendingInvites.isEmpty {
                        sectionLabel("Pending friends")
                        pendingInvitesCard
                    }
                    sectionLabel("Friends")
                    friendsCard
                }
                .padding(.bottom, 24)
            }
            .background(SplitMateTheme.groupedBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAddFriendSheet) {
                AddFriendSheet { profile in
                    if await sendRequest(to: profile) {
                        await reload()
                        return true
                    }
                    return false
                } onCreatePendingInvite: { name, phone, email in
                    if await sendPendingInvite(name: name, phone: phone, email: email) {
                        await reload()
                        return true
                    }
                    return false
                }
            }
            .navigationDestination(item: $pendingPairFriend) { friend in
                PairExpenseLoaderView(friend: friend)
            }
            .navigationDestination(item: $selectedFriendForDetail) { friend in
                FriendExpenseDetailView(friend: friend)
            }
            .navigationDestination(item: $selectedPendingInviteForDetail) { invite in
                PendingFriendExpenseDetailView(invite: invite)
            }
            .navigationDestination(item: $pendingExpenseInvite) { invite in
                PendingExpenseLoaderView(invite: invite)
            }
            .task(id: sessionStore.session?.user.id) {
                await reload()
            }
            .refreshable {
                await reload()
            }
        }
    }

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("Friends")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                    .tracking(-0.5)
                Spacer()
                Button {
                    showingAddFriendSheet = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(SplitMateTheme.brandPurple)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
            }
            Color.clear.frame(height: 12)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Text("🔍")
                .font(.system(size: 14))
                .opacity(0.35)
            TextField(
                "",
                text: $searchQuery,
                prompt: Text("Search friends...")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 174 / 255, green: 174 / 255, blue: 178 / 255))
            )
            .font(.system(size: 14))
            .foregroundStyle(SplitMateTheme.labelPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    /// Matches HTML `.req-card` (peach strip + dot + count).
    private var incomingRequestsSummaryCard: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(red: 1, green: 149 / 255, blue: 0))
                .frame(width: 8, height: 8)
            Text("\(incoming.count) pending request\(incoming.count == 1 ? "" : "s")")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(red: 122 / 255, green: 69 / 255, blue: 0))
            Spacer()
            Text("\(incoming.count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(red: 1, green: 149 / 255, blue: 0)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 1, green: 243 / 255, blue: 224 / 255))
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
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

    /// White list card under `.req-card` for Accept / Decline (not in static HTML; keeps existing APIs).
    private var incomingRequestsActionsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(incoming.enumerated()), id: \.element.id) { index, req in
                incomingRequestRow(req: req)
                if index < incoming.count - 1 {
                    Divider()
                        .background(Color(red: 240 / 255, green: 240 / 255, blue: 245 / 255))
                        .padding(.leading, 68)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private func incomingRequestRow(req: FriendRequest) -> some View {
        let name = incomingProfiles[req.fromUser]?.username ?? "User"
        let initial = String(name.prefix(1)).uppercased()
        return HStack(spacing: 12) {
            Circle()
                .fill(Color(red: 1, green: 149 / 255, blue: 0))
                .frame(width: 42, height: 42)
                .overlay(
                    Text(initial)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                Text("wants to connect")
                    .font(.system(size: 12))
                    .foregroundStyle(SplitMateTheme.labelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button("Decline") {
                    Task { await respond(req, status: "rejected") }
                }
                .font(.system(size: 13, weight: .medium))
                .buttonStyle(.bordered)
                .tint(SplitMateTheme.labelSecondary)
                Button("Accept") {
                    Task { await respond(req, status: "accepted") }
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .tint(SplitMateTheme.brandPurple)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var pendingInvitesCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(pendingInvites.enumerated()), id: \.element.id) { index, invite in
                pendingInviteRow(invite: invite, colorIndex: index)
                if index < pendingInvites.count - 1 {
                    Divider()
                        .background(Color(red: 240 / 255, green: 240 / 255, blue: 245 / 255))
                        .padding(.leading, 68)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private func pendingInviteAvatarColor(index: Int) -> Color {
        let palette: [Color] = [
            Color(red: 1, green: 149 / 255, blue: 0),
            Color(red: 1, green: 107 / 255, blue: 107 / 255),
            SplitMateTheme.brandPurple,
            SplitMateTheme.positiveGreen,
            Color(red: 0, green: 200 / 255, blue: 215 / 255)
        ]
        return palette[index % palette.count]
    }

    private func pendingInviteRow(invite: PendingFriendInvite, colorIndex: Int) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedPendingInviteForDetail = invite
            } label: {
                Text(String(invite.name.prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(pendingInviteAvatarColor(index: colorIndex)))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    selectedPendingInviteForDetail = invite
                } label: {
                    Text(invite.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SplitMateTheme.labelPrimary)
                }
                .buttonStyle(.plain)
                Text(invite.email)
                    .font(.system(size: 12))
                    .foregroundStyle(SplitMateTheme.labelSecondary)
                let total = pendingInviteTotals[invite.id] ?? 0
                if total > 0.0001 {
                    Text("pending share \(SplitMateTheme.inrString(total))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 1, green: 149 / 255, blue: 0))
                } else {
                    Text("No pending share yet")
                        .font(.system(size: 11))
                        .foregroundStyle(SplitMateTheme.labelSecondary)
                }
            }
            Spacer(minLength: 0)
            Button {
                pendingExpenseInvite = invite
            } label: {
                Text("+")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(SplitMateTheme.brandPurple))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var friendsCard: some View {
        Group {
            if filteredFriends.isEmpty {
                Text(searchQuery.isEmpty ? "No friends yet." : "No matches.")
                    .font(.subheadline)
                    .foregroundStyle(SplitMateTheme.labelSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white)
                    )
                    .padding(.horizontal, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredFriends.enumerated()), id: \.element.id) { index, f in
                        friendRow(f: f)
                        if index < filteredFriends.count - 1 {
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
        }
    }

    private func friendRow(f: Profile) -> some View {
        let palette: [Color] = [
            SplitMateTheme.orangeAccent,
            Color(red: 1, green: 107 / 255, blue: 107 / 255),
            SplitMateTheme.brandPurple,
            SplitMateTheme.positiveGreen,
            Color(red: 0, green: 200 / 255, blue: 215 / 255)
        ]
        let bg = palette[abs(f.id.hashValue) % palette.count]
        return HStack(spacing: 12) {
            Button {
                selectedFriendForDetail = f
            } label: {
                Text(String(f.username.prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(bg))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    selectedFriendForDetail = f
                } label: {
                    Text(f.username)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SplitMateTheme.labelPrimary)
                }
                .buttonStyle(.plain)
                if let email = f.email, !email.isEmpty {
                    Text(email)
                        .font(.system(size: 12))
                        .foregroundStyle(SplitMateTheme.labelSecondary)
                }
                let net = friendNetBalances[f.id] ?? 0
                if abs(net) > 0.0001 {
                    Text(net > 0 ? "owes you \(SplitMateTheme.inrString(net))" : "you owe \(SplitMateTheme.inrString(-net))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(net > 0 ? SplitMateTheme.positiveGreen : Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255))
                } else {
                    Text("Settled up")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SplitMateTheme.positiveGreen)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        guard let uid = sessionStore.session?.user.id else { return }
        let fs = FriendService(client: sessionStore.client)
        do {
            incoming = try await fs.incomingPending(for: uid)
            friends = try await fs.acceptedFriends(for: uid)
            do {
                pendingInvites = try await fs.pendingInvites(for: uid)
            } catch {
                pendingInvites = []
            }
            var map: [UUID: Profile] = [:]
            for r in incoming {
                if let p = try? await fs.profile(id: r.fromUser) {
                    map[r.fromUser] = p
                }
            }
            incomingProfiles = map
            friendNetBalances = try await loadFriendBalances(currentUserId: uid, friends: friends)
            pendingInviteTotals = try await loadPendingInviteTotals(currentUserId: uid, pendingInvites: pendingInvites)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadFriendBalances(currentUserId: UUID, friends: [Profile]) async throws -> [UUID: Double] {
        let groupService = GroupService(client: sessionStore.client)
        let expenseService = ExpenseService(client: sessionStore.client)
        var balances: [UUID: Double] = [:]

        for friend in friends {
            guard let pair = try await groupService.pairGroup(for: currentUserId, friendId: friend.id) else {
                balances[friend.id] = 0
                continue
            }
            let expenses = try await expenseService.expenses(groupId: pair.id)
            balances[friend.id] = pairNetBalance(
                currentUserId: currentUserId,
                friendId: friend.id,
                expenses: expenses
            )
        }
        return balances
    }

    private func loadPendingInviteTotals(
        currentUserId: UUID,
        pendingInvites: [PendingFriendInvite]
    ) async throws -> [UUID: Double] {
        var totals: [UUID: Double] = [:]
        for invite in pendingInvites {
            totals[invite.id] = 0
        }
        guard !pendingInvites.isEmpty else { return totals }

        let inviteIdSet = Set(pendingInvites.map(\.id))
        let groups = try await GroupService(client: sessionStore.client).groups(for: currentUserId)
        let expenseService = ExpenseService(client: sessionStore.client)

        for group in groups {
            let expenses = try await expenseService.expenses(groupId: group.id)
            for item in expenses {
                for pendingSplit in item.pendingSplits where inviteIdSet.contains(pendingSplit.pendingInviteId) {
                    totals[pendingSplit.pendingInviteId, default: 0] += pendingSplit.amountOwed
                }
            }
        }
        return totals
    }

    private func sendRequest(to profile: Profile) async -> Bool {
        guard let uid = sessionStore.session?.user.id else { return false }
        do {
            try await FriendService(client: sessionStore.client).sendFriendRequest(from: uid, to: profile.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func sendPendingInvite(name: String, phone: String?, email: String) async -> Bool {
        guard let uid = sessionStore.session?.user.id else { return false }
        do {
            try await FriendService(client: sessionStore.client).createPendingInvite(
                from: uid,
                name: name,
                phone: phone,
                email: email
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func respond(_ req: FriendRequest, status: String) async {
        do {
            try await FriendService(client: sessionStore.client).updateRequest(id: req.id, status: status)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PendingExpenseLoaderView: View {
    let invite: PendingFriendInvite
    @Environment(SessionStore.self) private var sessionStore

    @State private var group: GroupRecord?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding()
            } else if let group {
                AddExpenseView(group: group)
            } else {
                ProgressView("Preparing…")
            }
        }
        .navigationTitle(group == nil ? invite.name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(group != nil ? .hidden : .automatic, for: .navigationBar)
        .task {
            await load()
        }
    }

    private func load() async {
        guard let uid = sessionStore.session?.user.id else { return }
        do {
            group = try await GroupService(client: sessionStore.client)
                .ensurePendingExpenseGroup(creatorId: uid, invite: invite)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FriendExpenseRow: Identifiable {
    let item: ExpenseWithSplits
    let groupName: String
    var id: UUID { item.id }
}

private enum FriendDetailTab: String, CaseIterable {
    case expenses = "Expenses"
    case groups = "Groups"
    case activity = "Activity"
}

private struct FriendExpenseDetailView: View {
    let friend: Profile
    @Environment(SessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [FriendExpenseRow] = []
    @State private var sharedGroupNames: [String] = []
    @State private var sharedGroupsCount = 0
    @State private var totalTogether: Double = 0
    @State private var errorMessage: String?
    @State private var netBalance: Double = 0
    @State private var isLoading = false
    @State private var pairGroupForExpense: GroupRecord?
    @State private var selectedTab: FriendDetailTab = .expenses
    @State private var showSettleUp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                friendDetailHero
                Color.clear.frame(height: 12)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(SplitMateTheme.negativeRed)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                }
                if isLoading {
                    ProgressView("Loading…")
                        .tint(SplitMateTheme.brandPurple)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    statsRow
                    tabPicker
                    tabContent
                }
            }
            .padding(.bottom, 28)
        }
        .background(SplitMateTheme.groupedBackground)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $pairGroupForExpense) { group in
            NavigationStack {
                AddExpenseView(group: group)
            }
        }
        .sheet(isPresented: $showSettleUp) {
            FriendSettleUpSheet(
                displayName: friend.username,
                initial: String(friend.username.prefix(1)).uppercased(),
                avatarColor: friendHeroAvatarColor,
                fullAmount: abs(netBalance),
                friendOwesYou: netBalance > 0.0001,
                onConfirm: { amount in
                    guard let uid = sessionStore.session?.user.id else { return }
                    let groupService = GroupService(client: sessionStore.client)
                    let expenseService = ExpenseService(client: sessionStore.client)
                    do {
                        if let pair = try await groupService.pairGroup(for: uid, friendId: friend.id) {
                            let payerId = netBalance > 0 ? friend.id : uid
                            let receiverId = netBalance > 0 ? uid : friend.id
                            try await expenseService.settleUp(
                                groupId: pair.id,
                                payerId: payerId,
                                receiverId: receiverId,
                                amount: amount
                            )
                            await load()
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            )
        }
        .task {
            await load()
        }
    }

    /// Matches HTML `.fd-hero` — white block: back link, avatar, name, email, balance strip.
    private var friendDetailHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Text("‹")
                            .font(.system(size: 18, weight: .medium))
                        Text("Friends")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(SplitMateTheme.brandPurple)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    Task { await openAddExpense() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(SplitMateTheme.brandPurple)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(SplitMateTheme.groupedBackground))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                Text(String(friend.username.prefix(1)).uppercased())
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(friendHeroAvatarColor))
                Text(friend.username)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                    .tracking(-0.3)
                    .padding(.top, 10)
                if let email = friend.email, !email.isEmpty {
                    Text(email)
                        .font(.system(size: 13))
                        .foregroundStyle(SplitMateTheme.labelSecondary)
                        .padding(.top, 2)
                }

                Group {
                    if isLoading {
                        HStack {
                            ProgressView()
                                .tint(SplitMateTheme.brandPurple)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    } else {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                if abs(netBalance) < 0.0001 {
                                    Text("All settled")
                                        .font(.system(size: 12))
                                        .foregroundStyle(SplitMateTheme.labelSecondary)
                                    Text(SplitMateTheme.inrString(0))
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(SplitMateTheme.labelPrimary)
                                } else if netBalance > 0 {
                                    Text("\(friend.username) owes you")
                                        .font(.system(size: 12))
                                        .foregroundStyle(SplitMateTheme.labelSecondary)
                                    Text(SplitMateTheme.inrString(netBalance))
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(SplitMateTheme.positiveGreen)
                                } else {
                                    Text("You owe \(friend.username)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(SplitMateTheme.labelSecondary)
                                    Text(SplitMateTheme.inrString(-netBalance))
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(SplitMateTheme.negativeRed)
                                }
                            }
                            Spacer(minLength: 12)
                            if abs(netBalance) > 0.0001 {
                                Button {
                                    showSettleUp = true
                                } label: {
                                    Text("Settle up")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(SplitMateTheme.brandPurple))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(SplitMateTheme.groupedBackground)
                )
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    /// HTML mock uses coral `#FF6B6B` for friend avatar; keep stable per friend.
    private var friendHeroAvatarColor: Color {
        Color(red: 1, green: 107 / 255, blue: 107 / 255)
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            statChip(value: "\(rows.count)", label: "Shared expenses")
            statChip(value: SplitMateTheme.inrString(totalTogether), label: "Total together")
            statChip(value: "\(sharedGroupsCount)", label: "Groups shared")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private func statChip(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(SplitMateTheme.labelPrimary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(SplitMateTheme.labelSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        )
    }

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(FriendDetailTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                        .foregroundStyle(selectedTab == tab ? SplitMateTheme.brandPurple : SplitMateTheme.labelSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedTab == tab ? Color(red: 237 / 255, green: 237 / 255, blue: 253 / 255) : Color.white)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .expenses:
            expensesFeed
        case .groups:
            groupsFeed
        case .activity:
            Text("No recent activity.")
                .font(.subheadline)
                .foregroundStyle(SplitMateTheme.labelSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
    }

    private var expensesFeed: some View {
        Group {
            if rows.isEmpty, !isLoading {
                Text("No shared expenses yet.")
                    .font(.subheadline)
                    .foregroundStyle(SplitMateTheme.labelSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        friendExpenseRow(row)
                        if index < rows.count - 1 {
                            Divider()
                                .background(Color(red: 240 / 255, green: 240 / 255, blue: 245 / 255))
                                .padding(.leading, 62)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                )
            }
        }
        .padding(.horizontal, 14)
    }

    private var groupsFeed: some View {
        Group {
            if sharedGroupNames.isEmpty {
                Text("No shared groups yet.")
                    .font(.subheadline)
                    .foregroundStyle(SplitMateTheme.labelSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sharedGroupNames.enumerated()), id: \.offset) { index, name in
                        HStack {
                            Text(name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(SplitMateTheme.labelPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(red: 192 / 255, green: 192 / 255, blue: 200 / 255))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        if index < sharedGroupNames.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                )
            }
        }
        .padding(.horizontal, 14)
    }

    private func friendExpenseRow(_ row: FriendExpenseRow) -> some View {
        let emoji = friendExpenseEmoji(for: row.item.expense.description)
        let bg = friendExpenseIconBackground(for: row.item.expense.description)
        let sub = "\(row.groupName) · \(friendShortMonthDay(from: row.item.expense.expenseDate))"
        let (share, shareColor) = friendShareLine(row.item)

        return HStack(alignment: .center, spacing: 12) {
            Text(emoji)
                .font(.system(size: 17))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(bg))
            VStack(alignment: .leading, spacing: 1) {
                Text(row.item.expense.description.isEmpty ? "Expense" : row.item.expense.description)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                Text(subtitleLine(row: row, baseSub: sub))
                    .font(.system(size: 11))
                    .foregroundStyle(SplitMateTheme.labelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                Text(SplitMateTheme.inrString(row.item.expense.amount))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                Text(share)
                    .font(.system(size: 11))
                    .foregroundStyle(shareColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func subtitleLine(row: FriendExpenseRow, baseSub: String) -> String {
        let paid = row.item.expense.paidBy
        guard let uid = sessionStore.session?.user.id else { return baseSub }
        if paid == friend.id {
            return "\(baseSub) · Paid by \(friend.username)"
        }
        if paid == uid {
            return baseSub
        }
        return "\(baseSub) · Paid by member"
    }

    private func friendShareLine(_ item: ExpenseWithSplits) -> (String, Color) {
        guard let uid = sessionStore.session?.user.id else { return ("", SplitMateTheme.labelSecondary) }
        let paid = item.expense.paidBy
        let my = item.splits.first(where: { $0.userId == uid })?.amountOwed ?? 0
        let fr = item.splits.first(where: { $0.userId == friend.id })?.amountOwed ?? 0

        if paid == uid, fr > 0.01 {
            return ("\(friend.username) owes \(SplitMateTheme.inrString(fr))", SplitMateTheme.positiveGreen)
        }
        if paid == friend.id, my > 0.01 {
            return ("You owe \(SplitMateTheme.inrString(my))", SplitMateTheme.negativeRed)
        }
        if my > 0.01 {
            return ("You owe \(SplitMateTheme.inrString(my))", SplitMateTheme.negativeRed)
        }
        if fr > 0.01 {
            return ("\(friend.username) owes \(SplitMateTheme.inrString(fr))", SplitMateTheme.positiveGreen)
        }
        return ("—", SplitMateTheme.labelSecondary)
    }

    private func openAddExpense() async {
        guard let uid = sessionStore.session?.user.id else { return }
        errorMessage = nil
        do {
            let g = try await GroupService(client: sessionStore.client).ensurePairGroup(creatorId: uid, friendId: friend.id)
            pairGroupForExpense = g
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let uid = sessionStore.session?.user.id else { return }
        errorMessage = nil
        do {
            let gs = GroupService(client: sessionStore.client)
            let es = ExpenseService(client: sessionStore.client)
            let myGroups = try await gs.groups(for: uid)
            var shared: [GroupRecord] = []
            for g in myGroups {
                let mems = try await gs.members(groupId: g.id)
                let ids = Set(mems.map(\.userId))
                if ids.contains(friend.id), ids.contains(uid) {
                    shared.append(g)
                }
            }
            sharedGroupsCount = shared.count
            sharedGroupNames = shared.map(\.name).sorted()

            var combined: [FriendExpenseRow] = []
            var total: Double = 0
            var netSum = 0.0
            for g in shared {
                let exps = try await es.expenses(groupId: g.id)
                netSum += pairNetBalance(currentUserId: uid, friendId: friend.id, expenses: exps)
                for item in exps {
                    combined.append(FriendExpenseRow(item: item, groupName: g.name))
                    total += item.expense.amount
                }
            }
            combined.sort { $0.item.expense.expenseDate > $1.item.expense.expenseDate }
            rows = combined
            totalTogether = total
            netBalance = netSum
        } catch {
            errorMessage = error.localizedDescription
            rows = []
            sharedGroupNames = []
            sharedGroupsCount = 0
            totalTogether = 0
            netBalance = 0
        }
    }
}

private struct FriendSettleUpSheet: View {
    private enum AmountMode: String, CaseIterable {
        case full = "Full"
        case custom = "Custom"
    }

    let displayName: String
    let initial: String
    let avatarColor: Color
    let fullAmount: Double
    /// When false, current user owes `friend`.
    let friendOwesYou: Bool
    let onConfirm: (Double) async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var amountMode: AmountMode = .full
    @State private var customAmountText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var chosenAmount: Double? {
        switch amountMode {
        case .full:
            return fullAmount > 0.0001 ? fullAmount : nil
        case .custom:
            let raw = customAmountText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let v = Double(raw), v > 0.0001, v <= fullAmount + 0.01 else { return nil }
            return v
        }
    }

    private var confirmationLine: String {
        guard let amt = chosenAmount else {
            return "Choose full balance or enter a custom amount up to \(SplitMateTheme.inrString(fullAmount))."
        }
        return "Are you sure you want to settle up \(SplitMateTheme.inrString(amt)) with \(displayName)? This will record a payment."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    heroRow
                    Group {
                        if let amt = chosenAmount {
                            Text(SplitMateTheme.inrString(amt))
                                .font(.system(size: 42, weight: .bold))
                                .foregroundStyle(SplitMateTheme.labelPrimary)
                                .tracking(-1.5)
                        } else {
                            Text("—")
                                .font(.system(size: 42, weight: .bold))
                                .foregroundStyle(SplitMateTheme.labelSecondary)
                                .tracking(-1.5)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    Text("Outstanding balance")
                        .font(.system(size: 13))
                        .foregroundStyle(SplitMateTheme.labelSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(SplitMateTheme.negativeRed)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                    }

                    amountModePicker
                        .padding(.horizontal, 18)
                        .padding(.top, 28)

                    if amountMode == .custom {
                        TextField("Amount (max \(SplitMateTheme.inrString(fullAmount)))", text: $customAmountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 17, weight: .medium))
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(SplitMateTheme.groupedBackground)
                            )
                            .padding(.horizontal, 18)
                            .padding(.top, 12)
                    }

                    Text(confirmationLine)
                        .font(.system(size: 15))
                        .foregroundStyle(SplitMateTheme.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.top, 22)

                    confirmButton
                }
                .padding(.bottom, 32)
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("‹ Back")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SplitMateTheme.brandPurple)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(SplitMateTheme.groupedBackground))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            Spacer()
            Text("Settle up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SplitMateTheme.labelPrimary)
            Spacer()
            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private var heroRow: some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Y")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(SplitMateTheme.brandPurple))
                Text("You")
                    .font(.system(size: 12))
                    .foregroundStyle(SplitMateTheme.labelSecondary)
            }
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    Capsule()
                        .fill(SplitMateTheme.brandPurple)
                        .frame(width: 44, height: 2.5)
                    Text("›")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(SplitMateTheme.brandPurple)
                }
                Text("with")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 174 / 255, green: 174 / 255, blue: 178 / 255))
            }
            VStack(spacing: 6) {
                Text(initial)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(avatarColor))
                Text(displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(SplitMateTheme.labelSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    private var amountModePicker: some View {
        Picker("Amount", selection: $amountMode) {
            ForEach(AmountMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var confirmButton: some View {
        Button {
            guard let amt = chosenAmount else { return }
            Task {
                isLoading = true
                errorMessage = nil
                await onConfirm(amt)
                isLoading = false
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text("Confirm")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(SplitMateTheme.brandPurple)
            )
        }
        .buttonStyle(.plain)
        .disabled(chosenAmount == nil || isLoading)
        .opacity((chosenAmount == nil || isLoading) ? 0.4 : 1)
        .padding(.horizontal, 18)
        .padding(.top, 28)
    }
}

private func friendExpenseEmoji(for description: String) -> String {
    let options = ["🍹", "🏨", "🛵", "🍕", "🚢", "🛒", "☕️", "🎫", "💡", "🎬"]
    return options[abs(description.hashValue) % options.count]
}

private func friendExpenseIconBackground(for description: String) -> Color {
    let palette: [Color] = [
        Color(red: 1, green: 251 / 255, blue: 240 / 255),
        Color(red: 240 / 255, green: 244 / 255, blue: 1),
        Color(red: 240 / 255, green: 250 / 255, blue: 242 / 255),
        Color(red: 243 / 255, green: 240 / 255, blue: 1),
        Color(red: 240 / 255, green: 250 / 255, blue: 248 / 255)
    ]
    return palette[abs(description.hashValue) % palette.count]
}

private func friendShortMonthDay(from ymd: String) -> String {
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

private struct PendingInviteExpenseItem: Identifiable {
    let id: UUID
    let description: String
    let groupName: String
    let amount: Double
    let date: String
}

private struct PendingFriendExpenseDetailView: View {
    let invite: PendingFriendInvite
    @Environment(SessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var items: [PendingInviteExpenseItem] = []
    @State private var errorMessage: String?
    @State private var totalPendingShare: Double = 0
    @State private var isLoading = false
    @State private var showSettleUp = false
    @State private var pendingExpenseInvite: PendingFriendInvite?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                Color.clear.frame(height: 12)
                
                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(SplitMateTheme.negativeRed)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                }

                if isLoading {
                    ProgressView("Loading…")
                        .tint(SplitMateTheme.brandPurple)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    statsRow
                    
                    Text("EXPENSES")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SplitMateTheme.labelSecondary)
                        .tracking(0.3)
                        .padding(.horizontal, 18)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    expenseList
                }
            }
            .padding(.bottom, 28)
        }
        .background(SplitMateTheme.groupedBackground)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $pendingExpenseInvite) { invite in
            PendingExpenseLoaderView(invite: invite)
        }
        .sheet(isPresented: $showSettleUp) {
            FriendSettleUpSheet(
                displayName: invite.name,
                initial: String(invite.name.prefix(1)).uppercased(),
                avatarColor: Color(red: 1, green: 149 / 255, blue: 0),
                fullAmount: totalPendingShare,
                friendOwesYou: true,
                onConfirm: { amount in
                    guard let uid = sessionStore.session?.user.id else { return }
                    let groupService = GroupService(client: sessionStore.client)
                    let expenseService = ExpenseService(client: sessionStore.client)
                    do {
                        let group = try await groupService.ensurePendingExpenseGroup(creatorId: uid, invite: invite)
                        try await expenseService.settleUpPending(
                            groupId: group.id,
                            recorderId: uid,
                            pendingInviteId: invite.id,
                            amount: amount
                        )
                        await load()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            )
        }
        .task {
            await load()
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Text("‹")
                            .font(.system(size: 18, weight: .medium))
                        Text("Friends")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(SplitMateTheme.brandPurple)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    pendingExpenseInvite = invite
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(SplitMateTheme.brandPurple)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(SplitMateTheme.groupedBackground))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                Text(String(invite.name.prefix(1)).uppercased())
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color(red: 1, green: 149 / 255, blue: 0)))
                
                Text(invite.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                    .tracking(-0.3)
                    .padding(.top, 10)
                
                Text(invite.email)
                    .font(.system(size: 13))
                    .foregroundStyle(SplitMateTheme.labelSecondary)
                    .padding(.top, 2)

                Group {
                    if isLoading {
                        HStack {
                            ProgressView()
                                .tint(SplitMateTheme.brandPurple)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    } else {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                if totalPendingShare < 0.0001 {
                                    Text("No pending share")
                                        .font(.system(size: 12))
                                        .foregroundStyle(SplitMateTheme.labelSecondary)
                                    Text(SplitMateTheme.inrString(0))
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(SplitMateTheme.labelPrimary)
                                } else {
                                    Text("Pending share")
                                        .font(.system(size: 12))
                                        .foregroundStyle(SplitMateTheme.labelSecondary)
                                    Text(SplitMateTheme.inrString(totalPendingShare))
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(Color(red: 1, green: 149 / 255, blue: 0))
                                }
                            }
                            Spacer(minLength: 12)
                            if totalPendingShare > 0.0001 {
                                Button {
                                    showSettleUp = true
                                } label: {
                                    Text("Settle up")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(SplitMateTheme.brandPurple))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(SplitMateTheme.groupedBackground)
                )
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            statChip(value: "\(items.count)", label: "Shared expenses")
            statChip(value: SplitMateTheme.inrString(totalPendingShare), label: "Total pending")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private func statChip(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(SplitMateTheme.labelPrimary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(SplitMateTheme.labelSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        )
    }

    private var expenseList: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                Text("No expenses yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(SplitMateTheme.labelSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    expenseRow(item: item)
                    if index < items.count - 1 {
                        Divider()
                            .background(SplitMateTheme.separator.opacity(0.6))
                            .padding(.leading, 68)
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

    private func expenseRow(item: PendingInviteExpenseItem) -> some View {
        HStack(spacing: 12) {
            Text(friendExpenseEmoji(for: item.description))
                .font(.system(size: 20))
                .frame(width: 44, height: 44)
                .background(Circle().fill(friendExpenseIconBackground(for: item.description)))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.description.isEmpty ? "Expense" : item.description)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SplitMateTheme.labelPrimary)
                Text(item.groupName)
                    .font(.system(size: 12))
                    .foregroundStyle(SplitMateTheme.labelSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(SplitMateTheme.inrString(item.amount))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 149 / 255, blue: 0))
                Text(friendShortMonthDay(from: item.date))
                    .font(.system(size: 11))
                    .foregroundStyle(SplitMateTheme.labelSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let uid = sessionStore.session?.user.id else { return }
        errorMessage = nil
        do {
            let gs = GroupService(client: sessionStore.client)
            let es = ExpenseService(client: sessionStore.client)
            let groups = try await gs.groups(for: uid)

            var loadedItems: [PendingInviteExpenseItem] = []
            var total = 0.0
            for group in groups {
                let expenses = try await es.expenses(groupId: group.id)
                for expense in expenses {
                    for pendingSplit in expense.pendingSplits where pendingSplit.pendingInviteId == invite.id {
                        loadedItems.append(
                            PendingInviteExpenseItem(
                                id: pendingSplit.id,
                                description: expense.expense.description,
                                groupName: group.name,
                                amount: pendingSplit.amountOwed,
                                date: expense.expense.expenseDate
                            )
                        )
                        total += pendingSplit.amountOwed
                    }
                }
            }
            items = loadedItems.sorted { $0.date > $1.date }
            totalPendingShare = total
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private func pairNetBalance(currentUserId: UUID, friendId: UUID, expenses: [ExpenseWithSplits]) -> Double {
    var net = 0.0

    for item in expenses {
        if item.expense.paidBy == currentUserId {
            if let friendShare = item.splits.first(where: { $0.userId == friendId }) {
                net += friendShare.amountOwed
            }
        } else if item.expense.paidBy == friendId {
            if let myShare = item.splits.first(where: { $0.userId == currentUserId }) {
                net -= myShare.amountOwed
            }
        }
    }
    return net
}

private struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var sessionStore

    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var results: [Profile] = []
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isSearching = false
    @State private var invitingIds: Set<UUID> = []
    @State private var showPendingInviteAction = false

    let onInvite: (Profile) async -> Bool
    let onCreatePendingInvite: (String, String?, String) async -> Bool

    var body: some View {
        NavigationStack {
            List {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Phone no.", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Button("Find Friend") {
                        Task { await search() }
                    }
                    .disabled(isSearchDisabled || isSearching)
                    if isSearching {
                        ProgressView("Searching…")
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
                if showPendingInviteAction {
                    Section {
                        Button("Add \(pendingInviteDisplayName) as Pending Friend") {
                            Task { await addPendingFriend() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                if let successMessage {
                    Section {
                        Text(successMessage)
                            .foregroundStyle(.green)
                    }
                }
                if !results.isEmpty {
                    Section("Matches") {
                        ForEach(results) { profile in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.username)
                                    if let profileEmail = profile.email, !profileEmail.isEmpty {
                                        Text(profileEmail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Invite") {
                                    Task { await invite(profile) }
                                }
                                .disabled(invitingIds.contains(profile.id))
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Friend")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var isSearchDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func search() async {
        errorMessage = nil
        successMessage = nil
        results = []
        showPendingInviteAction = false

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let uid = sessionStore.session?.user.id else { return }
        guard !trimmedName.isEmpty || !trimmedPhone.isEmpty || !trimmedEmail.isEmpty else { return }

        if trimmedName.isEmpty, trimmedEmail.isEmpty, !trimmedPhone.isEmpty {
            errorMessage = "Phone lookup is not available yet. Please add name or email too."
            return
        }

        do {
            isSearching = true
            defer { isSearching = false }
            results = try await FriendService(client: sessionStore.client)
                .searchProfiles(name: trimmedName, email: trimmedEmail, excluding: uid)
            if results.isEmpty {
                if !trimmedEmail.isEmpty {
                    showPendingInviteAction = true
                } else {
                    errorMessage = "No matching users found. Add an email to create a pending friend."
                }
            }
        } catch {
            isSearching = false
            errorMessage = error.localizedDescription
        }
    }

    private func invite(_ profile: Profile) async {
        invitingIds.insert(profile.id)
        defer { invitingIds.remove(profile.id) }

        let didInvite = await onInvite(profile)
        if didInvite {
            results.removeAll { $0.id == profile.id }
        } else {
            errorMessage = "Could not send request. Please try again."
        }
    }

    private var pendingInviteDisplayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmail.isEmpty ? "Friend" : trimmedEmail
    }

    private func addPendingFriend() async {
        errorMessage = nil
        successMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty else {
            errorMessage = "Email is required to add a pending friend."
            return
        }

        let finalName = trimmedName.isEmpty ? trimmedEmail : trimmedName
        let finalPhone = trimmedPhone.isEmpty ? nil : trimmedPhone

        let didCreate = await onCreatePendingInvite(finalName, finalPhone, trimmedEmail)
        if didCreate {
            successMessage = "Pending friend added."
            dismiss()
        } else {
            errorMessage = "Could not add pending friend. Please try again."
        }
    }
}

/// Creates or opens a pair `GroupRecord` then presents add expense (embedded).
private struct PairExpenseLoaderView: View {
    let friend: Profile
    @Environment(SessionStore.self) private var sessionStore

    @State private var group: GroupRecord?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding()
            } else if let group {
                AddExpenseView(group: group)
            } else {
                ProgressView("Preparing…")
            }
        }
        .navigationTitle(group == nil ? friend.username : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(group != nil ? .hidden : .automatic, for: .navigationBar)
        .task {
            await load()
        }
    }

    private func load() async {
        guard let uid = sessionStore.session?.user.id else { return }
        do {
            group = try await GroupService(client: sessionStore.client).ensurePairGroup(creatorId: uid, friendId: friend.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
