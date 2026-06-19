import SwiftUI

/// The current user's avatar — shows their profile picture if set, otherwise an
/// initial on a tinted circle. Observes SocialStore so it updates the moment the
/// user changes their photo.
struct MyAvatarView: View {
    @ObservedObject private var store = SocialStore.shared
    let size: CGFloat
    var initial: String = "U"
    var color: Color = PulseColors.signal

    var body: some View {
        Group {
            if let img = store.profileImage() {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(color.opacity(0.16))
                    .overlay(
                        Text(initial)
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundColor(color)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
