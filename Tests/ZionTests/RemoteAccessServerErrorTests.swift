import Network
import XCTest
@testable import Zion

final class RemoteAccessServerErrorTests: XCTestCase {
    func testIsAddressInUseErrorMatchesNWError() {
        let error = NWError.posix(.EADDRINUSE)

        XCTAssertTrue(RemoteAccessServer.isAddressInUseError(error))
    }

    func testIsAddressInUseErrorMatchesNSErrorFallback() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EADDRINUSE))

        XCTAssertTrue(RemoteAccessServer.isAddressInUseError(error))
    }

    func testIsAddressInUseErrorRejectsDifferentErrors() {
        let error = NWError.posix(.ECONNREFUSED)

        XCTAssertFalse(RemoteAccessServer.isAddressInUseError(error))
    }
}
