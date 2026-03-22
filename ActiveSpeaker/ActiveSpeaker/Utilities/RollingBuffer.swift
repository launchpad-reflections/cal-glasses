import Foundation

/// Fixed-capacity circular buffer that computes running variance.
final class RollingBuffer<T: FloatingPoint> {
    private var storage: [T]
    private var index: Int = 0
    private var full: Bool = false
    let capacity: Int

    var count: Int {
        full ? capacity : index
    }

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = []
        self.storage.reserveCapacity(capacity)
    }

    func append(_ value: T) {
        if storage.count < capacity {
            storage.append(value)
        } else {
            storage[index] = value
        }
        index = (index + 1) % capacity
        if index == 0 && storage.count == capacity {
            full = true
        }
    }

    func variance() -> T {
        let n = count
        guard n >= 2 else { return T.zero }

        let nT = T(exactly: n) ?? T.zero
        var sum = T.zero
        var sumSq = T.zero

        for i in 0..<n {
            let v = storage[i]
            sum += v
            sumSq += v * v
        }

        let mean = sum / nT
        return sumSq / nT - mean * mean
    }

    func reset() {
        storage.removeAll(keepingCapacity: true)
        index = 0
        full = false
    }
}
