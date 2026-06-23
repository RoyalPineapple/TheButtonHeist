#if !canImport(UIKit)
#error("TheInsideJob import contract must be built for iOS/UIKit.")
#endif

#if !DEBUG
#error("TheInsideJob import contract must be built with DEBUG enabled.")
#endif

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
