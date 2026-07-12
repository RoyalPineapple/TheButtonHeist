import Foundation

extension TheFence {

    struct ConnectRequest {
        let targetName: TargetName?
        let device: String?
        let token: String?
    }

    func decodeConnectRequest(_ arguments: CommandArgumentEnvelope) throws -> ConnectRequest {
        ConnectRequest(
            targetName: try arguments.value(FenceParameters.connectionTarget).map(TargetName.init(rawValue:)),
            device: try arguments.value(FenceParameters.device),
            token: try arguments.value(FenceParameters.token)
        )
    }

}
