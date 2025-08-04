import Foundation
import Network

/// Processes command line args and yields which mode the app runs in.
struct Args {

    /// Possible modes: server or client.
    enum Mode {
        case server(port: UInt16)
        case client(host: String, port: UInt16)
    }

    /// The actual mode.
    let mode: Mode

    /// "Failable" initializer; sets the mode or nil if arguments are missing.
    init?() {
        var it = CommandLine.arguments.dropFirst().makeIterator()
        /// Get first command-line argument.
        guard let first_arg = it.next() else { return nil }

        switch first_arg {
        case "server":
            guard
                let p: String = it.next(),  // Unwrap optional.
                let port: UInt16 = UInt16(p)  // Convert to a number.
            else { return nil }
            mode = .server(port: port)  // Enum is a .server
        case "client":
            guard
                let host: String = it.next(),  // Unwrap optional
                let p: String = it.next(),  // Same
                let port: UInt16 = UInt16(p)  // Convert port to a number.
            else { return nil }
            mode = .client(host: host, port: port)  // Enum is a .client
        default: 
            print("Error: unknown mode!")
            return nil
        }
    }
}

@available(macOS 10.15, *)
func runServer(on port: UInt16) async throws {

    let params: NWParameters = NWParameters.tcp

    // Create a listener; assumes NWEndpoint.Port will not be nil.
    let listener: NWListener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

    print("🔊 Echo-server listening on \(port)")

    // Assign a closure to handle a new connection;
    // Our handler (handle) will be run asynchronously.
    listener.newConnectionHandler = { conn in
        conn.start(queue: .global())
        Task {
            do {
                let (data, complete) = try await handle(conn)
                print("Received data: \(data), complete: \(complete)")

                // Send a pong back
                var payload = data
                payload.append(contentsOf: "pong!".utf8)
                conn.send(
                    content: payload,
                    completion: .contentProcessed({ _ in })
                )
            } catch {
                print("Connection error: \(error)")
            }

        }
    }

    // Start listening. Use GCD queue.
    listener.start(queue: .global())

    try await withUnsafeThrowingContinuation { (_: UnsafeContinuation<Never, Error>) in 
    // This continuation is intentionally never resumed
    // This suspends the task indefinitely without blocking a thread
    }
}

@available(macOS 10.15, *)
extension NWConnection {

    // Extend NWConnection with a single-shot callback wrapper 
    func receiveOnce() async throws -> (Data, Bool) {
        try await withCheckedThrowingContinuation { cont in
            self.receive(minimumIncompleteLength: 1, maximumLength: 1024) {
                data, _, isComplete, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: (data ?? Data(), isComplete))
            }
        }
    }
}

@available(macOS 10.15, *)
func handle(_ conn: NWConnection) async throws -> (Data, Bool) {
    let (data, isComplete) = try await conn.receiveOnce()
    print("Handle new connection: \(data), \(isComplete)")

    return (data, isComplete)
}

@available(macOS 10.15, *)
func runClient(to host: String, port: UInt16) async throws {
    let start = DispatchTime.now()
    let conn = NWConnection(
        host: .init(host),
        port: .init(rawValue: port)!,
        using: .tcp)
    
    print("Connecting...")
    conn.start(queue: .global())

    print("Sending ping...")
    conn.send(
        content: "ping\n".data(using: .utf8)!,
        completion: .contentProcessed({ _ in }))

    print("Receiving pong...")
    let (data, complete) = try await conn.receiveOnce()
    
    if complete {
        print("Connection closed by server.")
        return
    }

    // Reply back with the approximate round trip time.
    if let reply = String(data: data, encoding: .utf8) {
        let rtt = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6
        print(
            "📨 reply = “\(reply.trimmingCharacters(in: .whitespacesAndNewlines))”, RTT = \(String(format: "%.2f", rtt)) ms"
        )
    }

    // Close the connection from the client side.
    conn.cancel()
}

@available(macOS 13.0, *)
func runMain() async {
    guard let args = Args() else {
        print(
            """
            Usage:
              NetEcho server <port>
              NetEcho client <host> <port>
            """)
        exit(1)
    }

    do {
        switch args.mode {
        case .server(let port): 
            try await runServer(on: port)
        case .client(let host, let port): 
            try await runClient(to: host, port: port)
        }
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}