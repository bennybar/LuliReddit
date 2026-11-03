import SwiftUI

/// A placeholder card shown while a feed loads: it breathes rather than shimmers, the
/// way the system's own placeholders do.
struct PostSkeleton: View {
    @State private var dim = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                bar(28, 28, radius: 14)
                bar(120, 12)
            }
            bar(nil, 14).padding(.top, 12)
            bar(220, 14).padding(.top, 6)
            bar(nil, 160, radius: 12).padding(.top, 12)
            HStack(spacing: 8) {
                bar(80, 22)
                bar(64, 22)
            }
            .padding(.top, 12)
        }
        .padding(16)
        .opacity(dim ? 0.5 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityHidden(true)
    }

    private func bar(_ width: CGFloat?, _ height: CGFloat, radius: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color(.tertiarySystemFill))
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, height: height)
    }
}
