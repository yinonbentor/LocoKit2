import Testing
@testable import LocoKit2

@Suite struct SmokeTests {
    @Test func toolchainSmokeTest() {
        #expect(1 + 1 == 2)
    }
}
