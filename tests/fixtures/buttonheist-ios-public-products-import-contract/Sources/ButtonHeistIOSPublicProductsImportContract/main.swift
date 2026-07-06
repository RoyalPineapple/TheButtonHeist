#if !canImport(UIKit)
#error("iOS public products import contract must be built for iOS/UIKit.")
#endif

#if !DEBUG
#error("iOS public products import contract must be built with DEBUG enabled.")
#endif

import Foundation
import ButtonHeistTesting
import TheInsideJob

@main
struct ButtonHeistIOSPublicProductsImportContract {
    @MainActor
    static func main() async {
        TheInsideJob.configure(token: "public-products-import-contract")
        let job = TheInsideJob(token: "public-products-import-contract")
        await job.stop()
    }
}

@MainActor
func xctestShapeCompiles() async throws {
    try await runHeist("Checkout.pay") {
        Activate(.label("Pay"))
            .expect(.appeared(.label("Payment Complete")))
    }
}

@MainActor
func argumentShapesCompile() async throws {
    try await runHeist("Cart.addItem", argument: "Milk") { item in
        Activate(.label(item))
            .expect(.appeared(.label("Milk")))
    }

    try await runHeist("Rows.activate", argument: .label("Milk")) { target in
        Activate(target)
            .expect(.appeared(.label("Milk")))
    }
}

@MainActor
func prebuiltPlanShapeCompiles() async throws {
    let plan = try HeistPlan("Checkout.pay") {
        Activate(.label("Pay"))
            .expect(.appeared(.label("Payment Complete")))
    }

    _ = try await runHeist(plan)
}

func scopedSessionShapeCompiles() {
    withJoinedHeistSession(token: "public-products-import-contract") { session in
        _ = session.token
        _ = session.requestedPort
        _ = session.listeningPort
        _ = session.allowedScopes
        _ = session.readyMessage
    }
}

func kifStyleReplacementShapeCompiles() {
    let receiptsURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("buttonheist-receipts", isDirectory: true)

    runHeistSync("Checkout.pay", recordReceipt: .always, to: receiptsURL) {
        Activate(.label("Pay"))
            .expect(.appeared(.label("Payment Complete")))
    }
}

func boundedTakeoverShapeCompiles() throws {
    try withJoinedHeistSession(token: "checkout-probe") { session in
        try AdoptionProbe.run(endpoint: session.endpoint, token: session.token)
    }
}

func manualJoinShapeCompiles() {
    guard CommandLine.arguments.contains("--manual-join-heist") else { return }
    joinHeist(token: "manual-checkout-probe", port: 1456)
}

func systemDialogPairingInAppContractShapeCompiles() {
    seedLocationPermissionAsGranted()

    let receiptsURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("buttonheist-receipts", isDirectory: true)

    runHeistSync("Permissions.location.granted", recordReceipt: .always, to: receiptsURL) {
        WaitFor(.exists(.label("Location Enabled")), timeout: .seconds(5))

        Activate(.label("Continue"))
            .expect(.appeared(.label("Map")))
    }
}

private enum AdoptionProbe {
    static func run(endpoint: String, token: String) throws {
        _ = (endpoint, token)
    }
}

private func seedLocationPermissionAsGranted() {}
