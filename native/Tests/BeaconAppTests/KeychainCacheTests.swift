import Foundation
import XCTest

@testable import Beacon

@MainActor
final class KeychainCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Keychain.resetCacheForTesting()
    }

    override func tearDown() {
        Keychain.resetCacheForTesting()
        super.tearDown()
    }

    func testConcurrentReadsShareOneKeychainRequest() async {
        let probe = KeychainLoaderProbe(result: "secret")

        async let first = Keychain.read("concurrent", loader: { probe.load() })
        async let second = Keychain.read("concurrent", loader: { probe.load() })
        let values = await [first, second]

        XCTAssertEqual(values, ["secret", "secret"])
        XCTAssertEqual(probe.callCount, 1)
    }

    func testMissingCredentialIsCached() async {
        let probe = KeychainLoaderProbe(result: nil)

        let first = await Keychain.read("missing", loader: { probe.load() })
        let second = await Keychain.read("missing", loader: { probe.load() })

        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(probe.callCount, 1)
    }
}

private final class KeychainLoaderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let result: String?
    private var calls = 0

    init(result: String?) {
        self.result = result
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    func load() -> String? {
        lock.lock()
        calls += 1
        lock.unlock()
        Thread.sleep(forTimeInterval: 0.05)
        return result
    }
}
