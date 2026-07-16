import ButtonHeist
import ThePlans
import TheScore

@main
struct ButtonHeistPublicProductsImportContract {
    static func main() throws {
        let plan = try HeistPlan("public-products-import-contract") {
            Warn("public products imported")
        }
        let planName = plan.name ?? "public-products-import-contract"
        let value: HeistValue = .string(planName.description)
        let commandName = TheFence.Command.runHeist.rawValue
        _ = (plan, value, commandName)
    }
}
