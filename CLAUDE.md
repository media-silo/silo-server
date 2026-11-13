# Guidance for agents working in silo-server

These are the shapes this codebase settles on for concurrency and types. Each rule says why, so
that a case it doesn't cover can be argued from the reason rather than the letter. Where code
here doesn't match yet, it is a gap to close, not a precedent to follow.

## Concurrency: every task has an owner

- **Prefer structured concurrency.** Work belongs to a task tree: `async let`, a task group
  (`withTaskGroup`, `withThrowingTaskGroup`, `withDiscardingTaskGroup`), or a background
  service whose `run()` owns its children. Cancellation and errors then reach the work, and the
  owner waits for it before it ends.
- **No `Task {}` or `Task.detached` on the server or library side** unless something holds the
  handle and awaits or cancels it. A fire-and-forget task is owned by nothing. A shutdown neither
  waits for it nor stops it, and its errors go nowhere. A task that several callers join and all
  await (`LibraryLane.walk`) is owned; a task started from a request and left running is not.
  Long-running work started by a request is queued to a background service instead.
- **Awaiting an unstructured task's `.value` from inside a group does not forward cancellation
  to it.** Put the work in `group.addTask { … }` itself.
- **Cancellation is checked between units of work, and a cancelled unit is not a failure.** Finish
  the step under way, stop before the next, and leave persistent state saying where it stopped,
  so the next start picks it up. Don't record cancellation as a refusal or an error.
- **SwiftUI is different.** In `SiloAdmin`, a button's `Task {}` and a view's `.task` are normal.
  Keep a stored task only where it is cancelled when replaced, or when its view goes.

## Background services

- **A service's `run()` never returns while the silo runs.** Wire puts every `@BackgroundService`
  in one `ServiceGroup`, and ServiceLifecycle's default `successTerminationBehavior` is
  `.cancelGroup`, so one service returning cancels all the others. Work done once at start
  (resuming what was under way) is the first thing the service's loop does, not a service of its
  own.
- **Honour graceful shutdown.** Wrap the loop in `cancelWhenGracefulShutdown`. Outside a service
  group it simply runs, so tests can call `run()` directly and cancel it.
- **The type that does the work is the service.** Don't add a type whose `run()` only calls
  another type's. A target that declares a `@BackgroundService` depends on ServiceLifecycle;
  `SiloApp` does (`StoreService`).
- **Test a service by running it.** Run it in a task group beside the test, wait for state the
  test can observe (a record leaving `underWay`), then cancel the group. Don't add test-only entry
  points that drain its queue. The server suite runs with background services off, so
  end-to-end behaviour that needs one is tested on the service.

## Queues and signals

- **A queue is an `AsyncStream` of the items themselves.** `continuation.yield` is synchronous
  and `Sendable`, so a synchronous method can enqueue, and the stream's single consumer owns
  what's in it. Don't keep an `AsyncStream<Void>` as a wake-up beside a lock-guarded array that
  holds the real items.
- **An `AsyncStream<Void>` with `.bufferingNewest(1)` is right only when the signal means "do
  another pass"** and each pass reads its state fresh, so many requests coalesce into one
  (`CheckSignal`).
- **Order per key with lanes owned by the consumer.** To make one library's items in order while
  libraries run side by side, the consumer keeps a dictionary of per-key streams as a local
  variable in its loop, each drained by a child of its task group. The state is local, so it
  needs no lock.
- **A queue that loses its items on restart is backed by persistent records.** The service
  re-queues what the records say is under way when it starts, and the work is idempotent, so an
  item queued twice is done once.

## Types

- **A struct by default.** A service that holds only `let`s (other services, configuration,
  streams, loggers) is a struct. Wire's `@Singleton` and `@BackgroundService` accept structs, and
  most services here already are.
- **A class or actor only for shared mutable state or identity.** That means it owns a `Mutex`
  (which is `~Copyable`, so a copyable struct can't hold one), a `var` that other callers see, a
  cache, or a stored task, or it needs identity: an `@Observable` model, an `NSObject` delegate,
  a `deinit`. Prefer `Mutex` to `@unchecked Sendable` with plain `var`s; keep
  `@unchecked Sendable` to narrow, commented wrappers of non-`Sendable` system types.
- **A choice is an enum, not a struct of optionals.** If exactly one of several things is set,
  or which fields mean anything depends on a state, make it an enum with associated values
  (`StoreStep`, `StoreRecord.State`). Code then switches over it exhaustively, and a state the
  type can't hold can't be written. A struct whose comment says "exactly one of" or "or", whose
  code counts its non-nil fields, or which every reader tests field by field to learn which kind
  it is, is this pattern.
- **Keep the wire shape when a type becomes an enum.** Write its `Codable` by hand: an object of
  one key, the kind, holding its payload, or a flat object with the state as a name beside its
  fields. Don't use Swift's synthesized enum coding, which wraps payloads in `_0`, for a new API.
  A body that doesn't decode to one case is the request's fault, so answer it 400 at decoding,
  and don't record it to refuse later.
