import SwiftUI

/// Imperative sheets and alerts, the way the Flutter build used
/// `showModalBottomSheet` / `showDialog`: call an async function, get the result
/// back. `OverlayHost` (at the app root) draws whatever is open, each over the one
/// below. For a sheet that belongs to a screen, plain `.sheet` is still the way;
/// this is for flows outside a view (startup prompts) or awaiting a result.
///
/// ```
/// let reason: String? = await Overlays.show(detents: [.medium]) { done in ReportSheet(onPick: done) }
/// ```
/// nil = dismissed, or swiped away.
@MainActor enum Overlays {
    struct AlertButton {
        let title: String
        var role: ButtonRole? = nil
        let value: Any?
    }

    fileprivate final class Entry: Identifiable {
        enum Kind {
            case sheet(AnyView, Set<PresentationDetent>)
            case alert(title: String, message: String?, buttons: [AlertButton])
        }
        var kind: Kind!
        var result: Any?
        let resume: (Any?) -> Void
        init(resume: @escaping (Any?) -> Void) { self.resume = resume }
    }

    fileprivate static let state = OverlayState()

    /// A sheet; `done(result)` closes it. Returns once its slide-out has finished,
    /// so whatever is shown next isn't refused for presenting during a dismissal.
    static func show<T>(
        detents: Set<PresentationDetent> = [.large],
        @ViewBuilder content: @escaping (_ done: @escaping (T?) -> Void) -> some View
    ) async -> T? {
        await withCheckedContinuation { continuation in
            let entry = Entry { continuation.resume(returning: $0 as? T) }
            entry.kind = .sheet(AnyView(content { [weak entry] result in
                guard let entry else { return }
                entry.result = result
                state.stack.removeAll { $0 === entry }
            }), detents)
            state.stack.append(entry)
        }
    }

    /// Fire-and-forget variant for sheets with no result.
    static func launch(
        detents: Set<PresentationDetent> = [.large],
        @ViewBuilder content: @escaping (_ done: @escaping () -> Void) -> some View
    ) {
        Task {
            let _: Bool? = await show(detents: detents) { done in content { done(nil) } }
        }
    }

    /// An alert; the result is the `value` of the button tapped.
    static func alert<T>(_ title: String, message: String? = nil, buttons: [(title: String, role: ButtonRole?, value: T)]) async -> T? {
        await withCheckedContinuation { continuation in
            let entry = Entry { continuation.resume(returning: $0 as? T) }
            entry.kind = .alert(title: title, message: message, buttons: buttons.map { AlertButton(title: $0.title, role: $0.role, value: $0.value) })
            state.stack.append(entry)
        }
    }

    static func dismissAll() { state.stack.removeAll() }

    /// Sheets finish in `onDismiss`. An alert has none: wait out its fade the same way.
    fileprivate static func finishAlert(_ entry: Entry) {
        state.stack.removeAll { $0 === entry }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            entry.resume(entry.result)
        }
    }
}

@MainActor @Observable private final class OverlayState {
    var stack: [Overlays.Entry] = []
}

/// Presents `Overlays` entry number `depth`, and hosts the next one inside it:
/// SwiftUI presents a sheet from a sheet only when it's attached to the first's content.
struct OverlayHost: ViewModifier {
    var depth = 0

    private var entry: Overlays.Entry? {
        let stack = Overlays.state.stack
        return depth < stack.count ? stack[depth] : nil
    }

    private var sheet: Binding<Overlays.Entry?> {
        Binding(get: {
            if let entry, case .sheet = entry.kind { entry } else { nil }
        }, set: { new in
            // Swiped away, or dismissed along with the sheet beneath it.
            if new == nil, let entry { Overlays.state.stack.removeAll { $0 === entry } }
        })
    }

    private var alert: Binding<Bool> {
        Binding(get: {
            if let entry, case .alert = entry.kind { true } else { false }
        }, set: { open in
            if !open, let entry, case .alert = entry.kind { Overlays.finishAlert(entry) }
        })
    }

    func body(content: Content) -> some View {
        content
            .modifier(SheetPresenter(depth: depth, sheet: sheet))
            .alert(alertTitle, isPresented: alert) {
                if let entry, case let .alert(_, _, buttons) = entry.kind {
                    ForEach(buttons.indices, id: \.self) { i in
                        Button(buttons[i].title, role: buttons[i].role) { entry.result = buttons[i].value }
                    }
                }
            } message: {
                if let entry, case let .alert(_, message?, _) = entry.kind { Text(message) }
            }
    }

    private var alertTitle: String {
        if let entry, case let .alert(title, _, _) = entry.kind { title } else { "" }
    }
}

private struct SheetPresenter: ViewModifier {
    let depth: Int
    let sheet: Binding<Overlays.Entry?>
    /// The entry on screen: the stack has moved on by the time onDismiss runs.
    @State private var presented: Overlays.Entry?

    func body(content: Content) -> some View {
        content
            .onChange(of: sheet.wrappedValue?.id) { if let entry = sheet.wrappedValue { presented = entry } }
            .sheet(item: sheet, onDismiss: {
                presented?.resume(presented?.result)
                presented = nil
            }) { entry in
                if case let .sheet(view, detents) = entry.kind {
                    view
                        .presentationDetents(detents)
                        .modifier(OverlayHost(depth: depth + 1))
                }
            }
    }
}
