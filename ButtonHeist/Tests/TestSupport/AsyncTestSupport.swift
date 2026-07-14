import Foundation

package func eventually(
    within timeout: Duration = .seconds(1),
    isolation _: isolated (any Actor)? = #isolation,
    _ condition: () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() {
            return true
        }
        await Task.yield()
    }
    return await condition()
}
