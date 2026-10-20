// swift-tools-version:5.9
import Foundation
import PackageDescription

// The XCTest suites need Xcode. With only the Command Line Tools installed, run
// `HOUSE_NO_XCTEST=1 swift test`: it leaves them out and runs the Swift Testing ones.
let xctest = ProcessInfo.processInfo.environment["HOUSE_NO_XCTEST"] == nil

// What the macOS and iOS apps share: the plan store, the device platforms and the
// Mac ⇄ iPhone sync. Smart Life / Tuya is a separate module (HouseSmartLife), so a build
// can leave it out: the App Store edition of the iPhone app does.
let package = Package(
    name: "HouseCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "HouseCore", targets: ["HouseCore"]),
        .library(name: "HouseSmartLife", targets: ["HouseSmartLife"]),
    ],
    targets: [
        .target(name: "HouseCore", path: "Sources/HouseCore"),
        .target(name: "HouseSmartLife", dependencies: ["HouseCore"], path: "Sources/HouseSmartLife"),
        .testTarget(name: "HomeStoreTests", dependencies: ["HouseCore"], path: "Tests/HomeStoreTests"),
    ] + (xctest ? [
        .testTarget(name: "HouseCoreTests", dependencies: ["HouseCore"], path: "Tests/HouseCoreTests"),
        .testTarget(name: "HouseSmartLifeTests", dependencies: ["HouseSmartLife"], path: "Tests/HouseSmartLifeTests"),
    ] : [])
)
