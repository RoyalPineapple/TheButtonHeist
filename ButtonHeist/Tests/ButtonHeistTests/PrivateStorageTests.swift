import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist

final class PrivateStorageTests: XCTestCase {

    func testBaseDirectoryUsesExplicitStorageDirectory() {
        let directory = PrivateStorage.resolveBaseDirectory(environment: environment([
            .buttonheistStorageDirectory: "/tmp/buttonheist-storage"
        ]))

        XCTAssertEqual(directory.path, "/tmp/buttonheist-storage")
    }

    func testBaseDirectoryUsesXDGDataHomeWhenStorageDirectoryIsMissing() {
        let directory = PrivateStorage.resolveBaseDirectory(environment: environment([
            .xdgDataHome: "/tmp/xdg-data"
        ]))

        XCTAssertEqual(directory.path, "/tmp/xdg-data/buttonheist")
    }

    func testBaseDirectoryPrefersStorageDirectoryOverXDGDataHome() {
        let directory = PrivateStorage.resolveBaseDirectory(environment: environment([
            .buttonheistStorageDirectory: "/tmp/buttonheist-storage",
            .xdgDataHome: "/tmp/xdg-data"
        ]))

        XCTAssertEqual(directory.path, "/tmp/buttonheist-storage")
    }

    private func environment(_ values: [StorageEnvironmentKey: String]) -> StorageEnvironment {
        StorageEnvironment(testValues: values)
    }
}
