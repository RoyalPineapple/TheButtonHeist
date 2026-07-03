import Foundation
import ButtonHeistSupport

struct HandoffKeepalive {
    let interval: Duration = .seconds(5)
    let maxMissedPongs = 36

    func makeTask(
        tick: @escaping @ButtonHeistActor () -> Int,
        forceDisconnect: @escaping @ButtonHeistActor (Int) -> Void
    ) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                guard await Task.cancellableSleep(for: interval) else { break }
                guard !Task.isCancelled else { break }
                let count = await tick()
                if count >= maxMissedPongs {
                    await forceDisconnect(count)
                    break
                }
            }
        }
    }
}
