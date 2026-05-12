import Testing
import Foundation
@testable import DripAdvisor

@Suite("KeychainHelper")
struct KeychainHelperTests {

    private static let testService = "com.dripadvisor.test"

    @Test("save then read returns the same value")
    func saveRead() {
        let account = UUID().uuidString
        defer { KeychainHelper.delete(service: Self.testService, account: account) }

        KeychainHelper.save("hello-world", service: Self.testService, account: account)
        let read = KeychainHelper.read(service: Self.testService, account: account)
        #expect(read == "hello-world")
    }

    @Test("save overwrites previous value")
    func saveOverwrites() {
        let account = UUID().uuidString
        defer { KeychainHelper.delete(service: Self.testService, account: account) }

        KeychainHelper.save("v1", service: Self.testService, account: account)
        KeychainHelper.save("v2", service: Self.testService, account: account)
        #expect(KeychainHelper.read(service: Self.testService, account: account) == "v2")
    }

    @Test("delete removes the value")
    func deleteClears() {
        let account = UUID().uuidString
        KeychainHelper.save("x", service: Self.testService, account: account)
        KeychainHelper.delete(service: Self.testService, account: account)
        #expect(KeychainHelper.read(service: Self.testService, account: account) == nil)
    }

    @Test("read returns nil for missing account")
    func missingReadsNil() {
        let account = UUID().uuidString
        #expect(KeychainHelper.read(service: Self.testService, account: account) == nil)
    }
}
