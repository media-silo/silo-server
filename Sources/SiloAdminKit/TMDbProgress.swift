// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

extension AdminConsole {
    /// How far a reading against TMDb has got, for the console to show while it runs: the step it is on
    /// and, when the step reads several things, how many of them are read. A long series asks TMDb and
    /// the silo hundreds of questions, and the operator sees each step as it goes.
    public struct TMDbProgress: Hashable, Sendable {
        public var step: String
        public var done: Int
        /// How many the step reads; none when it reads one thing.
        public var total: Int?

        public init(_ step: String, done: Int = 0, of total: Int? = nil) {
            self.step = step
            self.done = done
            self.total = total
        }
    }

    /// How many of a step's questions are asked of TMDb and the silo at once: enough that a series'
    /// specials are read in seconds rather than minutes, and few enough to stay inside TMDb's rate.
    static let questionsAtOnce = 6

    /// `body` for each item, at most `questionsAtOnce` at a time, the results in the items' order. The
    /// first error ends the step, and the rest are cancelled. `done` is told how many are done after each.
    nonisolated static func concurrently<Item: Sendable, Answer: Sendable>(
        _ items: [Item],
        done: @Sendable (Int) async -> Void = { _ in },
        _ body: @escaping @Sendable (Item) async throws -> Answer
    ) async throws -> [Answer] {
        try await withThrowingTaskGroup(of: (Int, Answer).self) { group in
            var answers = [Answer?](repeating: nil, count: items.count)
            var next = 0
            func ask() {
                guard next < items.count else { return }
                let index = next
                group.addTask { (index, try await body(items[index])) }
                next += 1
            }
            for _ in 0..<questionsAtOnce { ask() }
            var finished = 0
            while let (index, answer) = try await group.next() {
                answers[index] = answer
                finished += 1
                await done(finished)
                ask()
            }
            return answers.compactMap { $0 }
        }
    }
}
