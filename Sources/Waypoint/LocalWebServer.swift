import Foundation
import Network
import AppKit
import Combine

/// LocalWebServer is a zero-dependency, lightweight HTTP fallback server built on Network.framework.
/// It provides guest mode for Windows, Android, and iOS devices without requiring the native app.
@MainActor
public final class LocalWebServer: ObservableObject {
    public static let shared = LocalWebServer()
    
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var port: UInt16 = 8765
    @Published public private(set) var localIP: String = "127.0.0.1"
    @Published public private(set) var serverURLString: String = ""
    @Published public private(set) var qrCodeImage: NSImage?
    @Published public var stagedFiles: [URL] = []
    @Published public var stagedText: String = ""
    
    private var listener: NWListener?
    private let serverQueue = DispatchQueue(label: "com.waypoint.webserver", qos: .utility)
    
    public init() {
        refreshNetworkInfo()
    }
    
    public func refreshNetworkInfo() {
        self.localIP = NetworkUtilities.getLocalIPAddress() ?? "127.0.0.1"
        self.serverURLString = "http://\(self.localIP):\(self.port)"
        self.qrCodeImage = QRGenerator.generateQRCode(from: self.serverURLString)
    }
    
    public func start(preferredPort: UInt16 = 8765) {
        guard !isRunning else { return }
        self.port = preferredPort
        refreshNetworkInfo()
        
        do {
            let tcpOptions = NWProtocolTCP.Options()
            let parameters = NWParameters(tls: nil, tcp: tcpOptions)
            parameters.allowLocalEndpointReuse = true
            
            let nwPort = NWEndpoint.Port(rawValue: preferredPort) ?? .any
            let listener = try NWListener(using: parameters, on: nwPort)
            
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    switch state {
                    case .ready:
                        if let assignedPort = listener.port?.rawValue {
                            self.port = assignedPort
                            self.refreshNetworkInfo()
                        }
                        self.isRunning = true
                        print("[Waypoint Web] Fallback server live at \(self.serverURLString)")
                    case .failed(let error):
                        print("[Waypoint Web] Server failed: \(error.localizedDescription)")
                        self.isRunning = false
                    case .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleHTTPConnection(connection)
                }
            }
            
            listener.start(queue: serverQueue)
            self.listener = listener
        } catch {
            print("[Waypoint Web] Failed to start listener: \(error)")
        }
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }
    
    public func stageFile(url: URL) {
        if !stagedFiles.contains(url) {
            stagedFiles.append(url)
        }
    }
    
    public func removeStagedFile(url: URL) {
        stagedFiles.removeAll { $0 == url }
    }
    
    // MARK: - HTTP Connection Handling
    
    private func handleHTTPConnection(_ connection: NWConnection) {
        connection.start(queue: serverQueue)
        
        // Read raw HTTP request
        connection.receive(minimumIncompleteLength: 4, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let data = data, error == nil else {
                connection.cancel()
                return
            }
            
            Task { @MainActor [weak self] in
                self?.processHTTPRequest(data: data, connection: connection)
            }
        }
    }
    
    private func processHTTPRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendHTTPResponse(status: 400, contentType: "text/plain", body: Data("Bad Request".utf8), connection: connection)
            return
        }
        
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendHTTPResponse(status: 400, contentType: "text/plain", body: Data("Bad Request".utf8), connection: connection)
            return
        }
        
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendHTTPResponse(status: 400, contentType: "text/plain", body: Data("Bad Request".utf8), connection: connection)
            return
        }
        
        let method = String(parts[0])
        let pathWithQuery = String(parts[1])
        let path = pathWithQuery.components(separatedBy: "?").first ?? "/"
        
        if method == "GET" {
            handleGET(path: path, pathWithQuery: pathWithQuery, connection: connection)
        } else if method == "POST" {
            handlePOST(path: path, fullData: data, connection: connection)
        } else {
            sendHTTPResponse(status: 405, contentType: "text/plain", body: Data("Method Not Allowed".utf8), connection: connection)
        }
    }
    
    private func handleGET(path: String, pathWithQuery: String, connection: NWConnection) {
        if path == "/" || path == "/index.html" {
            let html = self.renderLandingPageHTML()
            let responseData = Data(html.utf8)
            self.sendHTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: responseData, connection: connection)
        } else if path.hasPrefix("/download/") {
            let fileName = path.replacingOccurrences(of: "/download/", with: "").removingPercentEncoding ?? ""
            if let targetURL = self.stagedFiles.first(where: { $0.lastPathComponent == fileName }),
               let fileData = try? Data(contentsOf: targetURL) {
                self.sendHTTPFileResponse(filename: fileName, data: fileData, connection: connection)
            } else {
                self.sendHTTPResponse(status: 404, contentType: "text/plain", body: Data("File Not Found".utf8), connection: connection)
            }
        } else if path == "/api/status" {
            let json: [String: Any] = [
                "deviceName": Host.current().localizedName ?? "Mac",
                "stagedFiles": self.stagedFiles.map { $0.lastPathComponent },
                "stagedText": self.stagedText
            ]
            let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
            self.sendHTTPResponse(status: 200, contentType: "application/json", body: data, connection: connection)
        } else {
            sendHTTPResponse(status: 404, contentType: "text/plain", body: Data("Not Found".utf8), connection: connection)
        }
    }
    
    private func handlePOST(path: String, fullData: Data, connection: NWConnection) {
        if path == "/api/clipboard" {
            // Parse incoming clipboard beam from guest browser
            if let bodyString = String(data: fullData, encoding: .utf8)?.components(separatedBy: "\r\n\r\n").last,
               let decodedText = bodyString.removingPercentEncoding {
                let cleanText = decodedText.replacingOccurrences(of: "text=", with: "").replacingOccurrences(of: "+", with: " ")
                Task { @MainActor in
                    ContinuityManager.shared.updateClipboardFromExternal(cleanText)
                    let response = Data("{\"success\":true}".utf8)
                    self.sendHTTPResponse(status: 200, contentType: "application/json", body: response, connection: connection)
                }
                return
            }
        }
        
        sendHTTPResponse(status: 200, contentType: "application/json", body: Data("{\"status\":\"ok\"}".utf8), connection: connection)
    }
    
    // MARK: - HTTP Helpers
    
    private func sendHTTPResponse(status: Int, contentType: String, body: Data, connection: NWConnection) {
        let statusText = status == 200 ? "OK" : (status == 404 ? "Not Found" : "Error")
        var header = "HTTP/1.1 \(status) \(statusText)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n"
        header += "Access-Control-Allow-Origin: *\r\n\r\n"
        
        var fullData = Data(header.utf8)
        fullData.append(body)
        
        connection.send(content: fullData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func sendHTTPFileResponse(filename: String, data: Data, connection: NWConnection) {
        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: application/octet-stream\r\n"
        header += "Content-Disposition: attachment; filename=\"\(filename)\"\r\n"
        header += "Content-Length: \(data.count)\r\n"
        header += "Connection: close\r\n\r\n"
        
        var fullData = Data(header.utf8)
        fullData.append(data)
        
        connection.send(content: fullData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    // MARK: - Modern Responsive Guest Dashboard HTML
    
    private func renderLandingPageHTML() -> String {
        let macName = Host.current().localizedName ?? "Mac"
        
        var filesListHtml = ""
        if stagedFiles.isEmpty {
            filesListHtml = "<div class='empty-state'>No shared files currently available for download. Drop files in Waypoint on macOS to share instantly.</div>"
        } else {
            filesListHtml = "<div class='file-grid'>"
            for file in stagedFiles {
                let name = file.lastPathComponent
                let sizeText: String
                if let attr = try? FileManager.default.attributesOfItem(atPath: file.path),
                   let size = attr[.size] as? Int64 {
                    sizeText = String(format: "%.1f MB", Double(size) / (1024 * 1024))
                } else {
                    sizeText = "File"
                }
                
                filesListHtml += """
                <div class='file-card'>
                    <div class='file-icon'>📦</div>
                    <div class='file-info'>
                        <div class='file-name' title='\(name)'>\(name)</div>
                        <div class='file-size'>\(sizeText)</div>
                    </div>
                    <a href='/download/\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)' class='btn-download' download>Download</a>
                </div>
                """
            }
            filesListHtml += "</div>"
        }
        
        return """
        <!DOCTYPE html>
        <html lang='en'>
        <head>
            <meta charset='UTF-8'>
            <meta name='viewport' content='width=device-width, initial-scale=1.0'>
            <title>Waypoint — \(macName)</title>
            <style>
                :root {
                    --bg-gradient: linear-gradient(135deg, #0f172a 0%, #1e1b4b 50%, #090d16 100%);
                    --card-bg: rgba(30, 41, 59, 0.7);
                    --card-border: rgba(255, 255, 255, 0.1);
                    --accent: #38bdf8;
                    --accent-hover: #0284c7;
                    --text-primary: #f8fafc;
                    --text-secondary: #94a3b8;
                }
                * { box-sizing: border-box; margin: 0; padding: 0; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', Roboto, sans-serif;
                    background: var(--bg-gradient);
                    color: var(--text-primary);
                    min-height: 100vh;
                    padding: 24px;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                }
                .container { max-width: 680px; width: 100%; }
                header {
                    text-align: center;
                    margin-bottom: 32px;
                    padding-top: 16px;
                }
                .logo-badge {
                    display: inline-flex;
                    align-items: center;
                    gap: 8px;
                    background: rgba(56, 189, 248, 0.15);
                    color: var(--accent);
                    padding: 6px 14px;
                    border-radius: 999px;
                    font-size: 13px;
                    font-weight: 600;
                    margin-bottom: 12px;
                    border: 1px solid rgba(56, 189, 248, 0.3);
                }
                h1 { font-size: 28px; font-weight: 700; margin-bottom: 6px; }
                p.sub { color: var(--text-secondary); font-size: 15px; }
                
                .glass-card {
                    background: var(--card-bg);
                    backdrop-filter: blur(16px);
                    -webkit-backdrop-filter: blur(16px);
                    border: 1px solid var(--card-border);
                    border-radius: 18px;
                    padding: 22px;
                    margin-bottom: 20px;
                    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.3);
                }
                .section-title {
                    font-size: 16px;
                    font-weight: 600;
                    margin-bottom: 14px;
                    display: flex;
                    align-items: center;
                    gap: 8px;
                }
                
                .file-grid { display: flex; flex-direction: column; gap: 10px; }
                .file-card {
                    display: flex;
                    align-items: center;
                    background: rgba(15, 23, 42, 0.6);
                    border: 1px solid var(--card-border);
                    border-radius: 12px;
                    padding: 12px 16px;
                    gap: 12px;
                }
                .file-icon { font-size: 24px; }
                .file-info { flex: 1; min-width: 0; }
                .file-name { font-weight: 500; font-size: 14px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
                .file-size { font-size: 12px; color: var(--text-secondary); }
                .btn-download {
                    background: var(--accent);
                    color: #0f172a;
                    padding: 7px 14px;
                    border-radius: 8px;
                    text-decoration: none;
                    font-weight: 600;
                    font-size: 13px;
                    transition: all 0.15s ease;
                }
                .btn-download:hover { background: var(--accent-hover); color: white; }
                
                .empty-state {
                    text-align: center;
                    color: var(--text-secondary);
                    font-size: 14px;
                    padding: 24px;
                    border: 1px dashed var(--card-border);
                    border-radius: 12px;
                }
                
                .clipboard-box textarea {
                    width: 100%;
                    height: 90px;
                    background: rgba(15, 23, 42, 0.6);
                    border: 1px solid var(--card-border);
                    border-radius: 10px;
                    color: #fff;
                    padding: 12px;
                    font-size: 14px;
                    resize: vertical;
                    outline: none;
                    margin-bottom: 10px;
                }
                .clipboard-box textarea:focus { border-color: var(--accent); }
                .btn-primary {
                    background: var(--accent);
                    color: #0f172a;
                    border: none;
                    border-radius: 8px;
                    padding: 9px 18px;
                    font-size: 14px;
                    font-weight: 600;
                    cursor: pointer;
                    transition: background 0.15s;
                }
                .btn-primary:hover { background: var(--accent-hover); color: white; }
                
                footer {
                    margin-top: auto;
                    font-size: 12px;
                    color: var(--text-secondary);
                    text-align: center;
                    padding-top: 20px;
                }
            </style>
        </head>
        <body>
            <div class='container'>
                <header>
                    <div class='logo-badge'>⚡ Local-First Ecosystem Bridge</div>
                    <h1>Connected to \(macName)</h1>
                    <p class='sub'>Direct peer transfer over Wi-Fi • No Internet Required</p>
                </header>
                
                <div class='glass-card'>
                    <div class='section-title'>📥 Shared Files for Download</div>
                    \(filesListHtml)
                </div>
                
                <div class='glass-card clipboard-box'>
                    <div class='section-title'>📋 Beam Text to Mac Clipboard</div>
                    <form action='/api/clipboard' method='POST' onsubmit='sendText(event)'>
                        <textarea id='beamTextInput' placeholder='Type or paste text to beam directly to Mac clipboard...'>\(stagedText)</textarea>
                        <button type='submit' class='btn-primary' id='beamBtn'>Beam to Mac</button>
                        <span id='beamStatus' style='margin-left: 12px; font-size: 13px; color: #38bdf8;'></span>
                    </form>
                </div>
                
                <footer>
                    Waypoint Local Web Bridge • Dynamic IP: \(localIP):\(port)
                </footer>
            </div>
            
            <script>
                async function sendText(e) {
                    e.preventDefault();
                    const text = document.getElementById('beamTextInput').value;
                    const status = document.getElementById('beamStatus');
                    status.innerText = 'Beaming...';
                    try {
                        const resp = await fetch('/api/clipboard', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                            body: 'text=' + encodeURIComponent(text)
                        });
                        if (resp.ok) {
                            status.innerText = '✓ Copied to Mac!';
                            setTimeout(() => { status.innerText = ''; }, 3000);
                        } else {
                            status.innerText = 'Failed to beam';
                        }
                    } catch(err) {
                        status.innerText = 'Error: ' + err.message;
                    }
                }
            </script>
        </body>
        </html>
        """
    }
}
