// CryptoKit verifies Sparkle material against the configured public key. Private
// material is read from a protected file, never passed as an argument or logged.
import CryptoKit
import Foundation

enum VerificationError: Error {
    case invalidArguments, invalidKey, mismatchedKey, invalidSignature
}

func publicKey(_ encoded: String) throws -> Curve25519.Signing.PublicKey {
    guard let data = Data(base64Encoded: encoded), data.count == 32 else {
        throw VerificationError.invalidKey
    }
    return try Curve25519.Signing.PublicKey(rawRepresentation: data)
}

do {
    let arguments = CommandLine.arguments
    guard arguments.count >= 2 else { throw VerificationError.invalidArguments }
    switch arguments[1] {
    case "key":
        guard arguments.count == 4 else { throw VerificationError.invalidArguments }
        let encoded = try String(contentsOfFile: arguments[2], encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let secret = Data(base64Encoded: encoded), [32, 64, 96].contains(secret.count) else {
            throw VerificationError.invalidKey
        }
        let expected = try publicKey(arguments[3]).rawRepresentation
        let actual: Data
        if secret.count == 32 {
            actual = try Curve25519.Signing.PrivateKey(rawRepresentation: secret).publicKey.rawRepresentation
        } else {
            // Sparkle owns parsing the older formats (including expanded keys).
            // The final archive verification below proves the private half works.
            actual = Data(secret.suffix(32))
        }
        guard actual == expected else { throw VerificationError.mismatchedKey }
    case "archive":
        guard arguments.count == 5 else { throw VerificationError.invalidArguments }
        let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
        guard let signature = Data(base64Encoded: arguments[3]), signature.count == 64 else {
            throw VerificationError.invalidSignature
        }
        let key = try publicKey(arguments[4])
        guard key.isValidSignature(signature, for: archive) else {
            throw VerificationError.invalidSignature
        }
    default:
        throw VerificationError.invalidArguments
    }
    print("Sparkle key/signature verified against the configured public key.")
} catch {
    // Do not interpolate errors: parser and system diagnostics may contain
    // protected input. The caller can distinguish the requested operation.
    fputs("Sparkle verification failed: invalid material or public-key mismatch (values withheld).\n", stderr)
    exit(1)
}
