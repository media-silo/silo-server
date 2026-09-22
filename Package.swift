// swift-tools-version: 6.4
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import PackageDescription

// One package, several products, because the pieces have to be named from two places: the silo
// server links all of them, and the ingestion tool in smd-tools links the ones a client needs —
// the rules, the encoder, and later the client, discovery and file serving — by this package's
// URL. SwiftPM cannot reach a package inside a folder of another, so the pieces share a manifest.
//
// Swift 6.4 and macOS 26 are the floor the server's stack sets: the swift-http-api-proposal server
// the silo will serve on is built with them, and the ingestion tool raised its own floor to match.
// Nothing below the server imports anything Apple-only; the Linux CI job is what keeps that true.
// The flag set wire-mvc and wire-open-api compile their own API with, applied to the modules that name
// the proposal's types — the controllers, the composition root and the tests. Kept whole, as
// task-cluster keeps it, because the point is to agree with the packages these modules call.
let proposalSettings: [SwiftSetting] = [
    .strictMemorySafety(),
    .enableExperimentalFeature("SuppressedAssociatedTypesWithDefaults"),
    .enableExperimentalFeature("LifetimeDependence"),
    .enableExperimentalFeature("Lifetimes"),
    .enableUpcomingFeature("LifetimeDependence"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

// The three build plugins the server and its tests apply, in this order: the graph once, then each
// adapter's own generator. The bundled per-adapter plugins cannot express an app that uses both.
let wirePlugins: [Target.PluginUsage] = [
    .plugin(name: "WireBuildPlugin", package: "swift-wire"),
    .plugin(name: "WireMVCRouteGenPlugin", package: "wire-mvc"),
    .plugin(name: "WireOpenAPIGenPlugin", package: "wire-open-api"),
]

let package = Package(
    name: "silo-server",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "SiloKit", targets: ["SiloKit"]),
        .library(name: "Encoder", targets: ["Encoder"]),
        .library(name: "SiloLibrary", targets: ["SiloLibrary"]),
        .library(name: "SiloStore", targets: ["SiloStore"]),
        .executable(name: "silo-ctl", targets: ["silo-ctl"]),
        .executable(name: "silo", targets: ["silo"]),
    ],
    dependencies: [
        // The container model. Tracked by branch until it has a release to pin to.
        .package(url: "https://github.com/project-smd/SmdKit.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        // The index. SQLite, bundled, so the Linux build needs no system library beyond what the
        // package brings; a derived cache the silo can throw away, per Silo.md.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.0"),
        // The server's stack, as task-cluster spells it. The wire packages are named at their own
        // organisation because SwiftPM keys a dependency by URL and a redirect is not an identity.
        .package(url: "https://github.com/swift-wire/swift-wire.git", branch: "main"),
        .package(url: "https://github.com/swift-wire/wire-open-api.git", branch: "main"),
        // `NIOHTTPServer` is the trait that stands a test suite up on a real loopback server.
        .package(url: "https://github.com/swift-wire/wire-mvc.git", branch: "main", traits: [.defaults, "NIOHTTPServer"]),
        // A fork, pinned: WireOpenAPI dispatches each operation by calling the generated per-operation
        // method, which the stock generator emits fileprivate. Points back at the release once upstream
        // takes it.
        .package(url: "https://github.com/tachyonics/swift-openapi-generator.git", revision: "9e655e0adb9b993ef4cb29a6aa0dfc59b9b42b09"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-configuration", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-http-api-proposal.git", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/swift-server/swift-http-server.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.13.2"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0"),
    ],
    targets: [
        // Facts, rules, recipes: what the silo decides with. Pure, and testable on literal values.
        .target(
            name: "SiloKit",
            dependencies: [
                .product(name: "SmdKit", package: "SmdKit"),
                .product(name: "SmdSidecar", package: "SmdKit"),
            ]
        ),
        // A library on disk: its layout, the walk that finds every sidecar in it, the checks a
        // sidecar has to pass, and the placement that puts a finished file into it.
        .target(
            name: "SiloLibrary",
            dependencies: [
                "SiloKit",
                .product(name: "SmdKit", package: "SmdKit"),
                .product(name: "SmdSidecar", package: "SmdKit"),
            ]
        ),
        // ffprobe and ffmpeg, driven as processes. The one place a recipe becomes an argument list.
        .target(
            name: "Encoder",
            dependencies: ["SiloKit"]
        ),
        // The silo's own state: the index over a library's sidecars, kept in SQLite and rebuilt
        // from them, and later the files that hold jobs, nodes and rulesets.
        .target(
            name: "SiloStore",
            dependencies: [
                "SiloKit",
                "SiloLibrary",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SmdKit", package: "SmdKit"),
                .product(name: "SmdSidecar", package: "SmdKit"),
            ]
        ),
        // The document and its generated types. Depends on the Wire product without importing it:
        // that is how WireOpenAPI discovers which module carries a document.
        .target(
            name: "SiloAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "Wire", package: "swift-wire"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        // The controllers: the document's operations, the two raw routes that stream, and health.
        .target(
            name: "SiloApp",
            dependencies: [
                "SiloAPI",
                "SiloKit",
                "SiloLibrary",
                "SiloStore",
                .product(name: "SmdKit", package: "SmdKit"),
                .product(name: "SmdSidecar", package: "SmdKit"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "Wire", package: "swift-wire"),
                .product(name: "WireMVC", package: "wire-mvc"),
                .product(name: "WireOpenAPI", package: "wire-open-api"),
                .product(name: "HTTPAPIs", package: "swift-http-api-proposal"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "BasicContainers", package: "swift-collections"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: proposalSettings
        ),
        // The composition root. No main.swift: the route generator emits the entry point from the
        // `@WireMVCBootstrap` type. `SiloAPI`, `SiloStore` and `SiloKit` are direct dependencies because
        // the codegen plugins walk this target's own.
        .executableTarget(
            name: "silo",
            dependencies: [
                "SiloApp",
                "SiloAPI",
                "SiloKit",
                "SiloLibrary",
                "SiloStore",
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "Wire", package: "swift-wire"),
                .product(name: "WireOpenAPI", package: "wire-open-api"),
                .product(name: "WireMVC", package: "wire-mvc"),
                .product(name: "WireMVCRouter", package: "wire-mvc"),
                .product(name: "HTTPAPIs", package: "swift-http-api-proposal"),
                .product(name: "NIOHTTPServer", package: "swift-http-server"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "BasicContainers", package: "swift-collections"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            swiftSettings: proposalSettings,
            plugins: wirePlugins
        ),
        .executableTarget(
            name: "silo-ctl",
            dependencies: [
                "SiloKit",
                "Encoder",
                "SiloLibrary",
                .product(name: "SmdKit", package: "SmdKit"),
                .product(name: "SmdSidecar", package: "SmdKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "SiloKitTests", dependencies: ["SiloKit"]),
        .testTarget(name: "EncoderTests", dependencies: ["Encoder", "SiloKit"]),
        .testTarget(name: "SiloLibraryTests", dependencies: ["SiloLibrary", "SiloKit"]),
        .testTarget(name: "SiloStoreTests", dependencies: ["SiloStore", "SiloLibrary", "SiloKit"]),
        // Depends on the executable, because the composition root lives there and is what the suite
        // trait stands up; applies the same three plugins because a contributor proxy is generated per
        // target.
        .testTarget(
            name: "SiloTests",
            dependencies: [
                "silo",
                "SiloApp",
                "SiloAPI",
                "SiloKit",
                "SiloLibrary",
                "SiloStore",
                .product(name: "SmdKit", package: "SmdKit"),
                .product(name: "SmdSidecar", package: "SmdKit"),
                .product(name: "Wire", package: "swift-wire"),
                .product(name: "WireMVC", package: "wire-mvc"),
                .product(name: "WireMVCTesting", package: "wire-mvc"),
                .product(name: "WireOpenAPI", package: "wire-open-api"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ],
            swiftSettings: proposalSettings,
            plugins: wirePlugins
        ),
    ]
)
