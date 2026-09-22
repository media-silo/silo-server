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
let package = Package(
    name: "silo-server",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "SiloKit", targets: ["SiloKit"]),
        .library(name: "Encoder", targets: ["Encoder"]),
        .library(name: "SiloLibrary", targets: ["SiloLibrary"]),
        .executable(name: "silo-ctl", targets: ["silo-ctl"]),
    ],
    dependencies: [
        // The container model. Tracked by branch until it has a release to pin to.
        .package(url: "https://github.com/project-smd/SmdKit.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
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
    ]
)
