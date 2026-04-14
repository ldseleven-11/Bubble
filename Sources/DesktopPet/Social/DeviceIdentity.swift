import Foundation
import CryptoKit

/// 管理设备 Ed25519 密钥对，用于 OpenClaw 设备配对认证
class DeviceIdentity {
    static let shared = DeviceIdentity()

    let deviceId: String
    let publicKeyBase64Url: String
    private let privateKey: Curve25519.Signing.PrivateKey

    /// 持久化存储的 deviceToken（配对成功后由 Gateway 颁发）
    var deviceToken: String? {
        get { UserDefaults.standard.string(forKey: "openclaw.deviceToken") }
        set { UserDefaults.standard.set(newValue, forKey: "openclaw.deviceToken") }
    }

    private init() {
        let fileURL = DeviceIdentity.identityFileURL()

        if let loaded = DeviceIdentity.loadFromFile(fileURL) {
            self.privateKey = loaded.privateKey
            self.deviceId = loaded.deviceId
            self.publicKeyBase64Url = loaded.publicKeyBase64Url
            NSLog("[DeviceIdentity] Loaded existing identity: %@", deviceId.prefix(16) + "...")
        } else {
            let key = Curve25519.Signing.PrivateKey()
            self.privateKey = key
            let rawPublicKey = key.publicKey.rawRepresentation
            self.publicKeyBase64Url = rawPublicKey.base64UrlEncoded()
            self.deviceId = SHA256.hash(data: rawPublicKey).hexString()
            DeviceIdentity.saveToFile(fileURL, privateKey: key, deviceId: deviceId, publicKeyBase64Url: publicKeyBase64Url)
            NSLog("[DeviceIdentity] Generated new identity: %@", deviceId.prefix(16) + "...")
        }
    }

    /// 构造 v3 签名 payload 并签名
    func signConnectChallenge(
        clientId: String,
        clientMode: String,
        role: String,
        scopes: [String],
        token: String,
        nonce: String,
        platform: String = "darwin",
        deviceFamily: String = ""
    ) -> (signature: String, signedAt: Int64) {
        let signedAt = Int64(Date().timeIntervalSince1970 * 1000)
        let payload = [
            "v3",
            deviceId,
            clientId,
            clientMode,
            role,
            scopes.joined(separator: ","),
            String(signedAt),
            token,
            nonce,
            platform,
            deviceFamily
        ].joined(separator: "|")

        let payloadData = Data(payload.utf8)
        let signatureData = try! privateKey.signature(for: payloadData)
        let signatureBase64Url = Data(signatureData).base64UrlEncoded()

        NSLog("[DeviceIdentity] Signed v3 payload (nonce=%@)", String(nonce.prefix(16)))
        return (signatureBase64Url, signedAt)
    }

    // MARK: - 持久化

    private static func identityFileURL() -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bubblePet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("device-identity.json")
    }

    private static func loadFromFile(_ url: URL) -> (privateKey: Curve25519.Signing.PrivateKey, deviceId: String, publicKeyBase64Url: String)? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let privateKeyB64 = json["privateKey"] as? String,
              let privateKeyData = Data(base64UrlDecoded: privateKeyB64),
              privateKeyData.count == 32 else {
            return nil
        }
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData) else {
            return nil
        }
        let rawPublicKey = key.publicKey.rawRepresentation
        let publicKeyBase64Url = rawPublicKey.base64UrlEncoded()
        let deviceId = SHA256.hash(data: rawPublicKey).hexString()
        return (key, deviceId, publicKeyBase64Url)
    }

    private static func saveToFile(_ url: URL, privateKey: Curve25519.Signing.PrivateKey, deviceId: String, publicKeyBase64Url: String) {
        let json: [String: Any] = [
            "version": 1,
            "deviceId": deviceId,
            "publicKey": publicKeyBase64Url,
            "privateKey": privateKey.rawRepresentation.base64UrlEncoded()
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            try? data.write(to: url, options: .atomic)
            // 设置文件权限为 600（仅所有者可读写）
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}

// MARK: - Base64URL 编解码

extension Data {
    func base64UrlEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64UrlDecoded string: String) {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder > 0 { s += String(repeating: "=", count: 4 - remainder) }
        self.init(base64Encoded: s)
    }
}

// MARK: - SHA256 Hex

extension SHA256.Digest {
    func hexString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
