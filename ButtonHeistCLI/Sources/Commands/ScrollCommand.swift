import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist
import ThePlans

struct ScrollSelectionInput: ParsableArguments {
    @OptionGroup var element: AccessibilityTargetOptions

    @Option(name: .long, help: "Current-capture containerName from get_interface")
    var containerName: String?

    mutating func validate() throws {
        _ = try scrollSelection()
    }

    func scrollSelection() throws -> ScrollContainerSelection {
        if let containerName {
            let parsedContainerName: ContainerName
            do {
                parsedContainerName = try ContainerName(validating: containerName)
            } catch {
                throw ValidationError("--container-name must not be empty")
            }
            if try element.hasTarget {
                throw ValidationError("--container-name cannot be combined with element target options")
            }
            return .container(parsedContainerName)
        }
        if let target = try element.parsedTarget() {
            return .element(target)
        }
        return .visibleContainer
    }
}

extension ScrollContainerSelection {
    var cliTarget: AccessibilityTarget? {
        guard case .element(let target) = self else { return nil }
        return target
    }

    var cliContainerName: ContainerName? {
        guard case .container(let containerName) = self else { return nil }
        return containerName
    }
}

struct ScrollCommand: ConnectedOneShotCLICommand {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Scroll a scroll view by one page",
        discussion: """
            Scrolls the nearest scroll view ancestor of a target element by
            approximately one page in the given direction. Defaults to down.

            Examples:
              buttonheist scroll
              buttonheist scroll btn_list
              buttonheist scroll btn_list -d up
              buttonheist scroll --identifier "myElement" -d down
            """
    )

    @OptionGroup var selection: ScrollSelectionInput

    @Option(
        name: .shortAndLong,
        help: "Scroll direction: \(Self.catalogAllowedValuesDescription(for: FenceParameters.scrollDirection))"
    )
    var direction: String = Self.catalogDefaultArgument(for: FenceParameters.scrollDirection)

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions
    @OptionGroup var timeoutOption: TimeoutOption

    var runnerStatusMessage: String? { "Sending scroll..." }

    func requestArguments() throws -> TheFence.CommandArgumentEnvelope {
        guard let scrollDirection = Self.catalogCanonicalValue(direction, for: FenceParameters.scrollDirection) else {
            throw ValidationError("Invalid direction '\(direction)'. Valid: \(Self.catalogAllowedValuesDescription(for: FenceParameters.scrollDirection))")
        }

        let scrollSelection = try selection.scrollSelection()
        return Self.fenceArguments(
            target: scrollSelection.cliTarget,
            CommandArgumentFields.value(FenceParameters.scrollDirection, scrollDirection),
            CommandArgumentFields.value(.timeout, timeoutOption.timeout),
            CommandArgumentFields.optional(.containerName, scrollSelection.cliContainerName?.rawValue)
        )
    }
}
