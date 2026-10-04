/// One-slot memo. The key must name every dependency, since nothing else invalidates the slot.
struct Memo<Key: Equatable, Value> {
    private var slot: (key: Key, value: Value)?

    mutating func value(for key: Key, build: () -> Value) -> Value {
        if let slot, slot.key == key { return slot.value }
        let built = build()
        slot = (key, built)
        return built
    }
}

/// A tiny LRU. A render re-asks the same query, backspace revisits the last few,
/// and a picker's two limits alternate - none of which a one-slot memo serves.
struct SmallMemo<Key: Equatable, Value> {
    private var slots: [(key: Key, value: Value)] = []
    private let capacity: Int

    init(capacity: Int = 12) {
        self.capacity = capacity
    }

    mutating func value(for key: Key, build: () -> Value) -> Value {
        if let index = slots.firstIndex(where: { $0.key == key }) {
            let hit = slots.remove(at: index)
            slots.append(hit)
            return hit.value
        }
        let built = build()
        slots.append((key, built))
        if slots.count > capacity { slots.removeFirst() }
        return built
    }
}
