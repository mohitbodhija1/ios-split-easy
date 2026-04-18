import SwiftUI

/// Multi-step onboarding adapted from the SplitEasy-style HTML flow; branded for SplitMate.
struct OnboardingView: View {
    var onFinished: (_ openSignUp: Bool) -> Void

    @State private var page = 0
    private let pageCount = 5

    private let brandPurple = Color(red: 108 / 255, green: 99 / 255, blue: 255 / 255)
    private let brandPink = Color(red: 224 / 255, green: 64 / 255, blue: 251 / 255)

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomeSlide.tag(0)
                splitSmarterSlide.tag(1)
                groupsSlide.tag(2)
                settleUpSlide.tag(3)
                getStartedSlide.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.35), value: page)

            pageDots

            if page < pageCount - 1 {
                HStack {
                    Button("Back") {
                        if page > 0 { page -= 1 }
                    }
                    .disabled(page == 0)
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Skip") { page = pageCount - 1 }
                        .foregroundStyle(.secondary)

                    Button("Next") { page += 1 }
                        .buttonStyle(.borderedProminent)
                        .tint(brandPurple)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.bar)
            } else {
                HStack {
                    Button("Back") {
                        if page > 0 { page -= 1 }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.bar)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< pageCount, id: \.self) { i in
                Capsule()
                    .fill(i == page ? brandPurple : Color.secondary.opacity(0.25))
                    .frame(width: i == page ? 22 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.25), value: page)
                    .onTapGesture { page = i }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Slide 0 Welcome

    private var welcomeSlide: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [brandPurple, brandPink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .padding(.bottom, 20)

            Text("SplitMate")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 26 / 255, green: 26 / 255, blue: 46 / 255))

            Text("Split bills with family & friends.\nNo awkward money talks.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.horizontal, 24)

            HStack(spacing: -10) {
                onboardingAvatar("Y", color: brandPurple, z: 5)
                onboardingAvatar("A", color: Color(red: 1, green: 107 / 255, blue: 107 / 255), z: 4)
                onboardingAvatar("K", color: Color(red: 78 / 255, green: 205 / 255, blue: 196 / 255), z: 3)
                onboardingAvatar("R", color: Color(red: 1, green: 217 / 255, blue: 61 / 255), z: 2)
                Text("+8")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color(.systemGray5)))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            }
            .padding(.top, 28)

            Text("Trusted by groups everywhere")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 12)

            Spacer()

            Button {
                page = 1
            } label: {
                Text("Get started — it's free")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [brandPurple, brandPink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)

            Button {
                onFinished(false)
            } label: {
                Text("Already have an account? ")
                    .foregroundStyle(.secondary)
                + Text("Sign in")
                    .foregroundStyle(brandPurple)
                    .fontWeight(.medium)
            }
            .font(.footnote)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 240 / 255, green: 244 / 255, blue: 1),
                    Color(red: 253 / 255, green: 240 / 255, blue: 250 / 255),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func onboardingAvatar(_ letter: String, color: Color, z: CGFloat) -> some View {
        Text(letter)
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(Circle().fill(color))
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .zIndex(z)
    }

    // MARK: - Slide 1 Split smarter

    private var splitSmarterSlide: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Split smarter")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(brandPurple)
                    .textCase(.uppercase)
                    .padding(.top, 16)

                Text("Fair splits,\nevery time")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 26 / 255, green: 26 / 255, blue: 46 / 255))
                    .padding(.top, 8)

                Text("Add any expense and split evenly, by percentage, or by exact amounts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                expensePreviewCard
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        chip("Even split")
                        chip("By shares")
                    }
                    HStack(spacing: 8) {
                        chip("Exact amounts")
                        chip("Percentages")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var expensePreviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("🍕  Dinner at Olio")
                        .font(.subheadline.weight(.semibold))
                    Text("Paid by you · Today")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("₹3,200")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(brandPurple)
            }

            VStack(spacing: 8) {
                splitBarRow(letter: "Y", color: brandPurple, width: 0.35, value: "₹1,120")
                splitBarRow(letter: "A", color: Color(red: 1, green: 107 / 255, blue: 107 / 255), width: 0.25, value: "₹800")
                splitBarRow(letter: "K", color: Color(red: 78 / 255, green: 205 / 255, blue: 196 / 255), width: 0.40, value: "₹1,280")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 249 / 255, green: 249 / 255, blue: 1))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(red: 237 / 255, green: 232 / 255, blue: 1), lineWidth: 1)
                )
        )
    }

    private func splitBarRow(letter: String, color: Color, width: CGFloat, value: String) -> some View {
        HStack(spacing: 8) {
            Text(letter)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(color))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [brandPurple, Color(red: 156 / 255, green: 143 / 255, blue: 1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * width))
                }
            }
            .frame(height: 6)
            Text(value)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
        }
    }

    private func chip(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(brandPurple)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(red: 240 / 255, green: 238 / 255, blue: 1))
            )
    }

    // MARK: - Slide 2 Groups

    private var groupsSlide: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Stay organized")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(brandPurple)
                    .textCase(.uppercase)
                    .padding(.top, 16)

                Text("Groups for every\noccasion")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Text("Family, friends, trips, flatmates — keep every circle separate and clear.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    groupMiniCard(emoji: "🏠", name: "Family", count: "5 members", balance: "You owe ₹640", owe: true)
                    groupMiniCard(emoji: "✈️", name: "Goa Trip", count: "4 members", balance: "Owed ₹2,100", owe: false)
                    groupMiniCard(emoji: "🏡", name: "Flatmates", count: "3 members", balance: "You owe ₹920", owe: true)
                    groupMiniCard(emoji: "🎉", name: "Weekend crew", count: "6 members", balance: "Owed ₹450", owe: false)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                VStack(spacing: 0) {
                    activityRow(icon: "🛒", title: "Arjun added \"Groceries\"", sub: "Family · 2 min ago", amt: "₹1,450")
                    Divider().padding(.leading, 42)
                    activityRow(icon: "🚕", title: "Kriti paid \"Cab ride\"", sub: "Goa Trip · 1h ago", amt: "₹380")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 1, green: 250 / 255, blue: 240 / 255))
    }

    private func groupMiniCard(emoji: String, name: String, count: String, balance: String, owe: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emoji).font(.title2)
            Text(name).font(.caption.weight(.semibold))
            Text(count).font(.caption2).foregroundStyle(.tertiary)
            Text(balance)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(owe ? Color(red: 1, green: 107 / 255, blue: 107 / 255) : Color(red: 46 / 255, green: 204 / 255, blue: 113 / 255))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        )
    }

    private func activityRow(icon: String, title: String, sub: String, amt: String) -> some View {
        HStack(spacing: 10) {
            Text(icon)
                .font(.body)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 1, green: 248 / 255, blue: 224 / 255)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.medium))
                Text(sub).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Text(amt).font(.caption.weight(.semibold))
        }
        .padding(.vertical, 9)
    }

    // MARK: - Slide 3 Settle up

    private var settleUpSlide: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Stress-free payback")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(brandPurple)
                    .textCase(.uppercase)
                    .padding(.top, 16)

                Text("Settle up\nin seconds")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Text("Send and receive money instantly — right from the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                settleCard
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                settleSummary
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 240 / 255, green: 254 / 255, blue: 1))
    }

    private var settleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Suggested settlement")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            HStack {
                VStack(spacing: 6) {
                    Text("Y")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(brandPurple))
                    Text("You").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0, green: 200 / 255, blue: 215 / 255), brandPurple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 48, height: 3)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(brandPurple)
                    }
                    Text("sends").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                VStack(spacing: 6) {
                    Text("A")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color(red: 1, green: 107 / 255, blue: 107 / 255)))
                    Text("Arjun").font(.caption2).foregroundStyle(.secondary)
                }
            }

            Text("₹640.00")
                .font(.title2.weight(.bold))
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                settleMethod("⚡", "UPI", active: true)
                settleMethod("🏦", "Bank", active: false)
                settleMethod("💵", "Cash", active: false)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color(red: 208 / 255, green: 240 / 255, blue: 1), lineWidth: 1)
                )
        )
    }

    private func settleMethod(_ icon: String, _ label: String, active: Bool) -> some View {
        VStack(spacing: 4) {
            Text(icon).font(.body)
            Text(label).font(.caption2.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(active ? Color(red: 240 / 255, green: 238 / 255, blue: 1) : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(active ? brandPurple : Color(.separator), lineWidth: active ? 2 : 1)
                )
        )
        .foregroundStyle(active ? brandPurple : .secondary)
    }

    private var settleSummary: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Total you owe").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("₹1,560").font(.caption.weight(.medium))
            }
            HStack {
                Text("Total owed to you").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("₹2,550").font(.caption.weight(.medium))
            }
            Divider().padding(.top, 4)
            HStack {
                Text("Net balance").font(.subheadline.weight(.bold))
                Spacer()
                Text("+₹990")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(red: 46 / 255, green: 204 / 255, blue: 113 / 255))
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 240 / 255, green: 244 / 255, blue: 1),
                            Color(red: 248 / 255, green: 240 / 255, blue: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    // MARK: - Slide 4 Get started

    private var getStartedSlide: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("You're all set")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color(red: 201 / 255, green: 168 / 255, blue: 1))
                    .textCase(.uppercase)
                    .padding(.top, 24)

                Text("Everything you need,\nnothing you don't")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Text("Create an account to sync groups, friends, and expenses.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                VStack(spacing: 0) {
                    perkRow(icon: "💜", title: "Free forever", sub: "No hidden fees, ever", tint: brandPurple.opacity(0.35))
                    perkRow(icon: "🔒", title: "Bank-grade security", sub: "Your data stays private", tint: Color.cyan.opacity(0.25))
                    perkRow(icon: "🌍", title: "Multi-currency", sub: "Track balances in your currency", tint: Color.red.opacity(0.22))
                    perkRow(icon: "⚡", title: "Instant notifications", sub: "Know when expenses are added", tint: Color.green.opacity(0.22))
                }
                .padding(.top, 20)
                .padding(.horizontal, 8)

                Button {
                    onFinished(true)
                } label: {
                    Text("Create my free account")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [brandPurple, brandPink],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Text("By continuing, you agree to our Terms & Privacy Policy")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 26 / 255, green: 5 / 255, blue: 51 / 255),
                    Color(red: 13 / 255, green: 26 / 255, blue: 102 / 255),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func perkRow(icon: String, title: String, sub: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(sub).font(.caption2).foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(brandPurple.opacity(0.8))
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().background(.white.opacity(0.08))
        }
    }
}

#Preview {
    OnboardingView { _ in }
}
