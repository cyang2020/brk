import CommonCrypto
import Foundation

/// How Chromium on macOS encrypts passwords and cookies at rest ("v10"): the AES-128 key is
/// PBKDF2-HMAC-SHA1(<the "<Browser> Safe Storage" keychain password>, "saltysalt", 1003 rounds, 16 bytes), the cipher
/// AES-128-CBC with PKCS#7 padding and an IV of 16 spaces, and the stored value is "v10" + ciphertext. Read from
/// Chromium 154: components/os_crypt/async/browser/keychain_key_provider.mm and os_crypt/async/common/encryptor.cc.
/// The same key and format serve the source browser (decrypting) and Brk's own profile (encrypting Login Data rows).
public struct ChromiumKey: Sendable, Equatable {
    let bytes: Data

    public init(password: String) {
        var key = Data(count: 16)
        let salt = Array("saltysalt".utf8)
        _ = key.withUnsafeMutableBytes { out in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count, salt, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                                 out.bindMemory(to: UInt8.self).baseAddress, 16)
        }
        bytes = key
    }

    static let prefix = Data("v10".utf8)
    private static let iv = Data(repeating: 0x20, count: 16)

    /// Nil when the value is not "v10" data this key opens. A value without the prefix is returned as it is: very old
    /// Chromium stored some values in the clear.
    public func decrypt(_ value: Data) -> Data? {
        guard value.starts(with: Self.prefix) else { return value.isEmpty ? nil : value }
        return crypt(CCOperation(kCCDecrypt), Data(value.dropFirst(3)))
    }

    public func encrypt(_ plain: Data) -> Data? {
        crypt(CCOperation(kCCEncrypt), plain).map { Self.prefix + $0 }
    }

    private func crypt(_ operation: CCOperation, _ input: Data) -> Data? {
        var output = Data(count: input.count + kCCBlockSizeAES128)
        var written = 0
        let status = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { inBytes in
                bytes.withUnsafeBytes { key in
                    Self.iv.withUnsafeBytes { iv in
                        CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding),
                                key.baseAddress, 16, iv.baseAddress, inBytes.baseAddress, input.count,
                                out.baseAddress, out.count, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return output.prefix(written)
    }
}
