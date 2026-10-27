// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "esp_service",
  platforms: [
    .iOS("13.0")
  ],
  products: [
    .library(name: "esp-service", targets: ["esp_service"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "esp_service",
      dependencies: [],
      resources: []
    )
  ]
)
