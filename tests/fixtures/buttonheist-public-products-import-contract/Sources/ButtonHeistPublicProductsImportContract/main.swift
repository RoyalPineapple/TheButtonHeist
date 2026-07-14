import ButtonHeist
import ThePlans
import TheScore

@main
struct ButtonHeistPublicProductsImportContract {
    static func main() throws {
        let plan = try HeistPlan("public-products-import-contract") {
            Warn("public products imported")
        }
        let value: HeistValue = .string(plan.name ?? "")
        let commandName = TheFence.Command.runHeist.rawValue
        _ = (plan, value, commandName)
    }
}
