import CryptoKit
import Foundation
import Security

enum LiftoffCrypto {
    static func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        try ChaChaPoly.seal(data, using: key).combined
    }

    static func decrypt(_ combined: Data, using key: SymmetricKey) throws -> Data {
        try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: combined), using: key)
    }

    static func tokenToKey(_ token: String) -> SymmetricKey {
        let digest = SHA256.hash(data: Data(token.utf8))
        return SymmetricKey(data: digest)
    }

    static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
}
