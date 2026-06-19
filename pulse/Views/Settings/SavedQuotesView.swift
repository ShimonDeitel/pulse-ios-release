import SwiftUI

/// The user's saved daily quotes. Long-press the Daily Motivation widget →
/// "Save quote" to add one here. Pushed from Profile → Saved Quotes.
struct SavedQuotesView: View {
    @ObservedObject private var store = SocialStore.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            if store.savedQuotes.isEmpty {
                emptyState
            } else {
                VStack(spacing: 12) {
                    ForEach(store.savedQuotes, id: \.self) { quote in
                        // Icon + actions on their own row, the quote on a full
                        // width row below — so the text can never be clipped or
                        // dimmed behind the menu button.
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "quote.opening")
                                    .font(.system(size: 16))
                                    .foregroundColor(PulseColors.signal.opacity(0.6))
                                Spacer()
                                Menu {
                                    ShareLink(item: QuoteShare.shareText(quote)) {
                                        Label("Share as quote note", systemImage: "square.and.arrow.up")
                                    }
                                    Button(role: .destructive) {
                                        store.unsaveQuote(quote); PulseHaptics.light()
                                    } label: { Label("Remove", systemImage: "trash") }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 15))
                                        .foregroundColor(PulseColors.muted)
                                        .frame(width: 32, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("More options")
                            }
                            Text(quote)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(PulseColors.ink)
                                .lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PulseColors.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(PulseColors.hair, lineWidth: 1))
                    }
                }
                .padding(.horizontal, PulseSpacing.screenEdge)
                .padding(.top, 12)
                .padding(.bottom, PulseSpacing.screenBottom)
            }
        }
        .pulseScreen()
        .navigationTitle("Saved Quotes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 60)
            Image(systemName: "bookmark")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundColor(PulseColors.muted)
            Text("No saved quotes yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(PulseColors.ink)
            Text("On the dashboard, long-press the Daily Motivation card and tap \u{201C}Save quote\u{201D} to keep your favorites here.")
                .font(.system(size: 14))
                .foregroundColor(PulseColors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
