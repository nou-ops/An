// swift-tools-version: 5.9
//
// FieldwatchCore — منفذ Swift لمنطق Fieldwatch 1.1.17 (Kotlin/Android).
// هذا الـ package لا يحتوي ولا يجب أن يحتوي أبدًا على أي import لـ Android/CoreBluetooth.
// (قاعدة الـ handoff: "Never put Android imports in FieldwatchCore")
//
import PackageDescription

let package = Package(
    name: "FieldwatchCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),   // حتى تعمل الاختبارات على ماك بدون محاكي iOS
    ],
    products: [
        .library(name: "FieldwatchCore", targets: ["FieldwatchCore"]),
    ],
    targets: [
        // Resources/fieldwatch-signatures-v2.json = كتالوج Fieldwatch 1.1.17 الرسمي (catalogVersion 88)
        .target(name: "FieldwatchCore", resources: [.process("Resources")]),
        .testTarget(
            name: "FieldwatchCoreTests",
            dependencies: ["FieldwatchCore"]
        ),
    ]
)
