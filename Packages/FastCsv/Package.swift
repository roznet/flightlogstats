// swift-tools-version:6.0

import PackageDescription

// The CSV parser runs once per byte of a log, which is 5x slower unoptimised.
// Optimisation is per module, so it lives in its own package and is built -O
// in Debug too: the app stays debuggable, parsing stays fast.
let package = Package(
    name: "FastCsv",
    platforms: [.iOS(.v18), .macOS(.v15), .macCatalyst(.v18)],
    products: [
        .library(name: "FastCsv", targets: ["FastCsv"]),
    ],
    targets: [
        .target(
            name: "FastCsv",
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        .testTarget(name: "FastCsvTests", dependencies: ["FastCsv"]),
    ],
    swiftLanguageModes: [.v5]
)
