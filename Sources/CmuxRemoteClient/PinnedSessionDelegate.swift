import Foundation
import Security
import CryptoKit
import CmuxRemoteCore

/// Immutable configuration; trust is granted only to the paired endpoint's exact certificate.
final class PinnedSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, Sendable {
    let pairing: PairingConfiguration
    init(pairing: PairingConfiguration) { self.pairing = pairing }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.lowercased() == pairing.host.lowercased(), challenge.protectionSpace.port == pairing.port,
              let trust = challenge.protectionSpace.serverTrust, let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = certificates.first else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        let digest = SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined()
        guard digest == pairing.certificateSHA256 else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Never forward the bearer credential to a redirected endpoint.
        completionHandler(nil)
    }
}
