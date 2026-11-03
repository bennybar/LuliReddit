/// A loading / loaded / failed value for a screen's state.
enum Async<Value> {
    case loading
    case data(Value)
    case error(Error)

    /// The value, when there is one.
    var value: Value? {
        if case let .data(value) = self { value } else { nil }
    }
}
