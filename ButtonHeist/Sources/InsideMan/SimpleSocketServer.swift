#if canImport(UIKit)
import Foundation
import UIKit

/// Simple TCP socket server using CFSocket - more reliable than NWListener on iOS Simulator
final class SimpleSocketServer {
    typealias DataHandler = (Data, @escaping (Data) -> Void) -> Void

    private var serverSocket: CFSocket?
    private var listeningPort: UInt16 = 0
    private var clientSockets: [CFSocket] = []
    private var socketSources: [CFRunLoopSource] = []

    var onClientConnected: ((Int) -> Void)?
    var onClientDisconnected: ((Int) -> Void)?
    var onDataReceived: DataHandler?

    private var clientCounter = 0
    private var clientFileDescriptors: [Int: Int32] = [:]

    deinit {
        stop()
    }

    /// Start the server on the specified port (0 = any available port)
    /// Uses IPv6 dual-stack socket to accept both IPv4 and IPv6 connections
    func start(port: UInt16 = 0) throws -> UInt16 {
        NSLog("[SimpleSocketServer] Starting server (IPv6 dual-stack)...")

        // Ignore SIGPIPE globally - prevents crash when writing to closed socket
        signal(SIGPIPE, SIG_IGN)

        // Create IPv6 socket (dual-stack will handle IPv4 too)
        let fd = socket(AF_INET6, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "SimpleSocketServer", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Failed to create socket: \(String(cString: strerror(errno)))"
            ])
        }

        // Set socket options
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        // Prevent SIGPIPE on this socket
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        // Enable dual-stack: accept both IPv4 and IPv6 connections
        var no: Int32 = 0
        setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &no, socklen_t(MemoryLayout<Int32>.size))

        // Bind to port on all interfaces (IPv6 any = ::)
        var addr = sockaddr_in6()
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = port.bigEndian
        addr.sin6_addr = in6addr_any

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }

        guard bindResult >= 0 else {
            close(fd)
            throw NSError(domain: "SimpleSocketServer", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Failed to bind: \(String(cString: strerror(errno)))"
            ])
        }

        // Listen
        guard listen(fd, 5) >= 0 else {
            close(fd)
            throw NSError(domain: "SimpleSocketServer", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Failed to listen: \(String(cString: strerror(errno)))"
            ])
        }

        // Get actual port
        var boundAddr = sockaddr_in6()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in6>.size)
        withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                getsockname(fd, sockaddrPtr, &addrLen)
            }
        }
        listeningPort = UInt16(bigEndian: boundAddr.sin6_port)

        NSLog("[SimpleSocketServer] Listening on port \(listeningPort)")

        // Use GCD to handle incoming connections
        let acceptQueue = DispatchQueue(label: "com.buttonheist.insideman.accept")
        let serverFD = fd

        acceptQueue.async { [weak self] in
            while true {
                guard let self = self else { break }

                var clientAddr = sockaddr_in6()
                var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in6>.size)

                let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        accept(serverFD, sockaddrPtr, &clientAddrLen)
                    }
                }

                if clientFD < 0 {
                    if errno == EINTR { continue }
                    NSLog("[SimpleSocketServer] Accept error: \(String(cString: strerror(errno)))")
                    break
                }

                // Log the client address for debugging
                var addrString = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                inet_ntop(AF_INET6, &clientAddr.sin6_addr, &addrString, socklen_t(INET6_ADDRSTRLEN))
                let addrStr = String(cString: addrString)
                NSLog("[SimpleSocketServer] Accepted connection from \(addrStr) on fd \(clientFD)")
                self.handleNewClient(clientFD)
            }
        }

        return listeningPort
    }

    func stop() {
        // Close all client sockets
        for (_, fd) in clientFileDescriptors {
            close(fd)
        }
        clientFileDescriptors.removeAll()

        // Note: Would need to track and close server FD
        NSLog("[SimpleSocketServer] Server stopped")
    }

    private func handleNewClient(_ fd: Int32) {
        // Prevent SIGPIPE on client socket
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        clientCounter += 1
        let clientId = clientCounter
        clientFileDescriptors[clientId] = fd

        DispatchQueue.main.async { [weak self] in
            self?.onClientConnected?(clientId)
        }

        // Start reading from client
        let readQueue = DispatchQueue(label: "com.buttonheist.insideman.\(clientId)")
        readQueue.async { [weak self] in
            self?.readLoop(clientId: clientId, fd: fd)
        }
    }

    private func readLoop(clientId: Int, fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        var messageBuffer = Data()

        while true {
            let bytesRead = recv(fd, &buffer, buffer.count, 0)

            if bytesRead <= 0 {
                if bytesRead < 0 && errno == EINTR { continue }
                NSLog("[SimpleSocketServer] Client \(clientId) disconnected (bytesRead=\(bytesRead))")
                close(fd)
                clientFileDescriptors.removeValue(forKey: clientId)
                DispatchQueue.main.async { [weak self] in
                    self?.onClientDisconnected?(clientId)
                }
                break
            }

            NSLog("[SimpleSocketServer] Received \(bytesRead) bytes from client \(clientId)")

            messageBuffer.append(contentsOf: buffer.prefix(bytesRead))

            // Process newline-delimited messages
            while let newlineIndex = messageBuffer.firstIndex(of: 0x0A) {
                let messageData = Data(messageBuffer.prefix(upTo: newlineIndex))
                messageBuffer = Data(messageBuffer.suffix(from: messageBuffer.index(after: newlineIndex)))

                if !messageData.isEmpty {
                    let clientFD = fd
                    DispatchQueue.main.async { [weak self] in
                        self?.onDataReceived?(messageData) { response in
                            self?.send(response, to: clientFD)
                        }
                    }
                }
            }
        }
    }

    func send(_ data: Data, to fd: Int32) {
        var dataToSend = data
        if !dataToSend.hasSuffix(Data([0x0A])) {
            dataToSend.append(0x0A)
        }

        dataToSend.withUnsafeBytes { buffer in
            var sent = 0
            while sent < dataToSend.count {
                let n = Darwin.send(fd, buffer.baseAddress!.advanced(by: sent), dataToSend.count - sent, 0)
                if n < 0 {
                    NSLog("[SimpleSocketServer] Send error: \(String(cString: strerror(errno)))")
                    break
                }
                sent += n
            }
        }
    }

    func broadcastToAll(_ data: Data) {
        for (_, fd) in clientFileDescriptors {
            send(data, to: fd)
        }
    }
}

extension Data {
    func hasSuffix(_ suffixData: Data) -> Bool {
        guard count >= suffixData.count else { return false }
        return self.suffix(suffixData.count) == suffixData
    }
}
#endif
