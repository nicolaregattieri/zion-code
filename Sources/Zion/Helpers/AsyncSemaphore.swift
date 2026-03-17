import Foundation

actor AsyncSemaphore {
    private let maxConcurrent: Int
    private var currentCount: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int = 2) {
        self.maxConcurrent = maxConcurrent
    }

    func acquire() async {
        if currentCount < maxConcurrent {
            currentCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            currentCount -= 1
        }
    }

    var isFull: Bool {
        currentCount >= maxConcurrent
    }
}
