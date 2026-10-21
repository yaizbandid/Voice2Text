// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Voice2Text",
    platforms: [
        // macOS 15 ขึ้นไป เพื่อใช้ Apple Translation framework (แปลภาษาในเครื่อง)
        .macOS("15.0")
    ],
    products: [
        .executable(name: "Voice2Text", targets: ["Voice2Text"]),
        .executable(name: "v2t", targets: ["V2TCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "Voice2TextCore",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        // ส่วนวิเคราะห์คลิป (แท็บ "วิเคราะห์คลิป") — แยกจากส่วนถอดเสียงเดิม ดู SPEC.md
        .target(
            name: "ClipAnalysisCore",
            dependencies: ["Voice2TextCore"]
        ),
        .executableTarget(
            name: "Voice2Text",
            dependencies: ["Voice2TextCore", "ClipAnalysisCore"]
        ),
        .executableTarget(
            name: "V2TCLI",
            dependencies: ["Voice2TextCore", "ClipAnalysisCore"]
        ),
        .testTarget(
            name: "ClipAnalysisCoreTests",
            dependencies: ["ClipAnalysisCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
