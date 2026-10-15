import Foundation
import WebbyCore

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
enum EntryVerifier {
    static func verify(listeners: [Listener], identities: [Int: ProcessIdentity], adapters: [AppAdapter]) async -> Set<String> {
        var probes: [String: String] = [:]
        for row in listeners {
            for adapter in adapters where adapter.processNames.contains(row.name) || identities[row.pid]?.bundleID.map(adapter.bundleIDs.contains) == true {
                for rule in adapter.entries where rule.kind != "api" && rule.port == row.port {
                    if let base = ApplicationResolver.localBase(row), let marker = rule.titleMarker { probes[base] = marker }
                }
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2; configuration.timeoutIntervalForResource = 3
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var verified = Set<String>()
        for (base, marker) in probes.prefix(8) {
            guard let url = URL(string: base + "/") else { continue }
            do {
                var request = URLRequest(url: url); request.httpMethod = "GET"
                request.setValue("text/html", forHTTPHeaderField: "Accept")
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.mimeType == "text/html" else { continue }
                var prefix: [UInt8] = []
                for try await byte in bytes {
                    prefix.append(byte)
                    if prefix.count >= 16384 { break }
                    if byte == 62, String(decoding: prefix, as: UTF8.self).lowercased().contains("</title>") { break }
                }
                let html = String(decoding: prefix, as: UTF8.self)
                if let expression = try? NSRegularExpression(pattern: "<title[^>]*>\\s*" + NSRegularExpression.escapedPattern(for: marker) + "\\s*</title>", options: [.caseInsensitive]), expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) != nil { verified.insert(base) }
            } catch { /* An unavailable page remains unconfirmed; never promote API fallback to management. */ }
        }
        return verified
    }
}
