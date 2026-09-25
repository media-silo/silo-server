// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if !canImport(SwiftUI)
// The console is a Mac app; where SwiftUI is not, the target still builds so the package is
// checked whole on Linux, and running it says so.
@main
enum SiloAdminStub {
    static func main() {
        print("SiloAdmin is a macOS app; this platform has no window server for it.")
    }
}
#endif
