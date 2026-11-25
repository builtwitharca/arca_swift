import Foundation
import Testing

@testable import ArcaLaunch

/// An app hosts its own tests under xcodebuild, so without the check every
/// `xcodebuild test` runs the app's launch path first. Moved from Conflab's
/// TestHostTests (ConflabTests/TestHostTests.swift, 08b94be5), its
/// `detector` alone: the others drive Conflab's own delegate in its host.
/// AT-e69447a3.3 (STc203646d7444f4f1 acceptance.md) cites this file.
@Suite("Test host")
struct TestHostTests {
  @Test("XCTest's variable marks a host, even when empty, and a launch without it is not one")
  func detector() {
    #expect(ArcaLaunch.isTestHost(["XCTestConfigurationFilePath": "/tmp/Conflab.xctestconfiguration"]))
    #expect(ArcaLaunch.isTestHost(["XCTestConfigurationFilePath": ""]))
    #expect(!ArcaLaunch.isTestHost([:]))
    #expect(!ArcaLaunch.isTestHost(["HOME": "/Users/someone", "PATH": "/usr/bin:/bin"]))
  }
}
