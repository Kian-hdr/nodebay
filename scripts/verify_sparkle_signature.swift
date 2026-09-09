// Public-key-only Ed25519 verification for release tooling. No Keychain access.
import CryptoKit
import Foundation

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 4,
          let publicKeyData = Data(base64Encoded: args[1]), publicKeyData.count == 32,
          let signature = Data(base64Encoded: args[2]), signature.count == 64,
          let expectedLength = Int(args[3]), expectedLength > 0 else {
        throw NSError(domain: "NodebaySignature", code: 1)
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: args[0]), options: .mappedIfSafe)
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    guard data.count == expectedLength, key.isValidSignature(signature, for: data) else {
        throw NSError(domain: "NodebaySignature", code: 2)
    }
    print("Ed25519 signature and length verified")
} catch {
    // Never echo arguments or file contents.
    fputs("Ed25519 signature or length validation failed\n", stderr)
    exit(1)
}
