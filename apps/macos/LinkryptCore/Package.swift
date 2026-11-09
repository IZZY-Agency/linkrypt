// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LinkryptCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "LinkryptCore", targets: ["LinkryptCore"]),
    ],
    dependencies: [
        // Argon2id passphrase KDF (parity with the web default). Thin wrapper
        // over the reference PHC Argon2 C; param interface matches hash-wasm.
        // Pinned by revision (= tag 1.0.4) because Argon2Swift depends on
        // phc-winner-argon2 via .branch("master"), which SPM disallows under a
        // stable `from:` pin; the revision pin + Package.resolved keep it
        // reproducible.
        .package(
            url: "https://github.com/tmthecoder/Argon2Swift.git",
            revision: "53543623fefe68461b7eeea03d7f96677c2fd76d" // tag 1.0.4
        ),
    ],
    targets: [
        .target(
            name: "LinkryptCore",
            dependencies: [.product(name: "Argon2Swift", package: "Argon2Swift")]
        ),
        .testTarget(name: "LinkryptCoreTests", dependencies: ["LinkryptCore"], exclude: ["Fixtures"]),
    ]
)
