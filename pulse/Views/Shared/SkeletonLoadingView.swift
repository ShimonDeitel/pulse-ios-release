import SwiftUI

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.15),
                        Color.white.opacity(0.08),
                        Color.white.opacity(0)
                    ],
                    startPoint: .init(x: phase - 0.5, y: 0.5),
                    endPoint: .init(x: phase + 0.5, y: 0.5)
                )
                .blendMode(.plusLighter)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 2
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(PulseColors.surfaceContainer)
            .frame(width: width, height: height)
            .shimmer()
    }
}

// MARK: - Preset Skeleton Screens

struct SkeletonCardLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                SkeletonBlock(width: 44, height: 44, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBlock(width: 140, height: 14)
                    SkeletonBlock(width: 90, height: 10)
                }
                Spacer()
                SkeletonBlock(width: 48, height: 48, cornerRadius: 24)
            }
            SkeletonBlock(height: 8, cornerRadius: 4)
            HStack {
                SkeletonBlock(width: 80, height: 10)
                Spacer()
                SkeletonBlock(width: 40, height: 14)
            }
        }
        .padding(20)
        .background(PulseColors.surfaceElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: M3Shapes.extraLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: M3Shapes.extraLarge, style: .continuous)
                .stroke(PulseColors.outlineVariant, lineWidth: 0.5)
        )
        .padding(.horizontal, 20)
    }
}

struct SkeletonDashboardLoading: View {
    var body: some View {
        VStack(spacing: 16) {
            // Header skeleton
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBlock(width: 100, height: 12)
                    SkeletonBlock(width: 160, height: 24)
                }
                Spacer()
                SkeletonBlock(width: 44, height: 44, cornerRadius: 22)
            }
            .padding(.horizontal, 20)

            // Stat chips
            HStack(spacing: 8) {
                SkeletonBlock(width: 70, height: 28, cornerRadius: 14)
                SkeletonBlock(width: 70, height: 28, cornerRadius: 14)
                SkeletonBlock(width: 70, height: 28, cornerRadius: 14)
            }
            .padding(.horizontal, 20)

            // Quick actions
            SkeletonBlock(height: 90, cornerRadius: 20)
                .padding(.horizontal, 20)

            // Goal cards
            ForEach(0..<3, id: \.self) { _ in
                SkeletonCardLoading()
            }
        }
    }
}

struct SkeletonRoadmapLoading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                SkeletonBlock(width: 48, height: 48, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBlock(width: 180, height: 18)
                    SkeletonBlock(width: 120, height: 12)
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            // Progress bar
            SkeletonBlock(height: 8, cornerRadius: 4)
                .padding(.horizontal, 20)

            // Steps
            ForEach(0..<6, id: \.self) { i in
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 0) {
                        SkeletonBlock(width: 32, height: 32, cornerRadius: 16)
                        if i < 5 {
                            SkeletonBlock(width: 2, height: 40, cornerRadius: 1)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(width: CGFloat.random(in: 120...220), height: 14)
                        SkeletonBlock(width: CGFloat.random(in: 180...280), height: 10)
                        SkeletonBlock(width: CGFloat.random(in: 100...160), height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// (SkeletonCommunityLoading removed — Community feature deleted.)
