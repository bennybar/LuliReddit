import SwiftUI

enum SnackbarDuration {
    case short, long, indefinite

    fileprivate var seconds: Double? {
        switch self {
        case .short: 4
        case .long: 10
        case .indefinite: nil
        }
    }
}

/// `AppNavigator.showSnackbar`'s transient capsule. It lives in a small window of
/// its own above the app's, as snackbars must also read over sheets and media
/// viewers. The window only exists on screen while a toast shows, and only takes
/// touches on the capsule itself.
@MainActor @Observable final class ToastCenter {
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let actionLabel: String?
        let onAction: (() -> Void)?
    }

    private(set) var current: Toast?
    /// Extra bottom padding (the home shell's tab bar sets it).
    var bottomPadding: CGFloat = 0
    /// Where the capsule is on screen, for the window's hit test.
    fileprivate(set) var capsuleFrame: CGRect = .zero

    private var window: ToastWindow?
    private var hideTask: Task<Void, Never>?

    func show(_ message: String, actionLabel: String?, duration: SnackbarDuration, onAction: (() -> Void)?) {
        let toast = Toast(message: message, actionLabel: actionLabel, onAction: onAction)
        attachWindow()
        withAnimation(.spring(duration: 0.3)) { current = toast }
        hideTask?.cancel()
        guard let seconds = duration.seconds else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { dismiss() }
        }
    }

    func dismiss() {
        hideTask?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { current = nil } completion: { [self] in
            // A new toast may have come up during the fade.
            if current == nil { window?.isHidden = true }
        }
    }

    private func attachWindow() {
        if window == nil {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            guard let scene else { return }
            let new = ToastWindow(windowScene: scene)
            new.toasts = self
            new.windowLevel = .alert + 1
            let host = UIHostingController(rootView: ToastHost(center: self))
            host.view.backgroundColor = .clear
            new.rootViewController = host
            window = new
        }
        // The app's light/dark setting, as this window doesn't inherit the root view's.
        window?.overrideUserInterfaceStyle = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first?.keyWindow?.traitCollection.userInterfaceStyle ?? .unspecified
        window?.isHidden = false
    }
}

private final class ToastWindow: UIWindow {
    weak var toasts: ToastCenter?

    /// Everything but the capsule goes through to the app beneath.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let toasts, toasts.capsuleFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

private struct ToastHost: View {
    let center: ToastCenter

    var body: some View {
        VStack {
            Spacer()
            if let toast = center.current {
                HStack(spacing: 12) {
                    Text(toast.message)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                    if let label = toast.actionLabel {
                        Button(label) {
                            center.dismiss()
                            toast.onAction?()
                        }
                        .font(.subheadline.weight(.semibold))
                        .fixedSize()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .onTapGesture { center.dismiss() }
                .accessibilityAddTraits(.isStaticText)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { center.capsuleFrame = $0 }
                .padding(.horizontal, 16)
                .padding(.bottom, 12 + center.bottomPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .frame(maxWidth: .infinity)
        .tint(IlayTheme.accent)
    }
}
