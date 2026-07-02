import Foundation
import Network

/// Serves the bundled browser client (web/index.html + icon.png) over HTTP so a
/// phone or laptop on the LAN/VPN can open `http://<mac-ip>:48626` directly —
/// no external hosting needed. The page then talks to the WebSocket on 48625.
@MainActor
final class WebServer {
    static let shared = WebServer()
    static let port: UInt16 = 48626

    private var listener: NWListener?

    private init() {}

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: Self.port),
              let listener = try? NWListener(using: params, on: port) else { return }
        listener.newConnectionHandler = { conn in
            conn.start(queue: .main)
            Self.serve(conn)
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    nonisolated private static func serve(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8),
                  let firstLine = request.components(separatedBy: "\r\n").first else {
                conn.cancel(); return
            }
            let parts = firstLine.split(separator: " ")
            let path = parts.count >= 2 ? String(parts[1]) : "/"
            let response = body(for: path)
            conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    /// Build a complete HTTP response (headers + body) for a request path.
    nonisolated private static func body(for path: String) -> Data {
        let route = path.split(separator: "?").first.map(String.init) ?? path
        switch route {
        case "/", "/index.html":
            if let indexResponse { return indexResponse }
        case "/icon.png":
            if let iconResponse { return iconResponse }
        default:
            break
        }
        return http(status: "404 Not Found", contentType: "text/plain", body: Data("Not found".utf8))
    }

    /// Bundled assets are immutable for the process lifetime, so load them once
    /// at first access instead of hitting the bundle + disk on every request.
    nonisolated private static let indexResponse: Data? = {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web"),
              let data = try? Data(contentsOf: url) else { return nil }
        return http(status: "200 OK", contentType: "text/html; charset=utf-8", body: data)
    }()

    nonisolated private static let iconResponse: Data? = {
        guard let url = Bundle.main.url(forResource: "icon", withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return http(status: "200 OK", contentType: "image/png", body: data)
    }()

    nonisolated private static func http(status: String, contentType: String, body: Data) -> Data {
        let headers = "HTTP/1.1 \(status)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n\r\n"
        var data = Data(headers.utf8)
        data.append(body)
        return data
    }
}
