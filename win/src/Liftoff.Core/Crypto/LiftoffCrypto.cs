using System.Security.Cryptography;
using System.Text;

namespace Liftoff.Core.Crypto;

/// <summary>
/// Wire-compatible port of the macOS <c>LiftoffCrypto</c> (CryptoKit).
///
/// The companion (iOS) and web clients frame encrypted payloads exactly the way
/// Swift's <c>ChaChaPoly.seal(...).combined</c> lays them out:
///
///     combined = nonce (12 bytes) ‖ ciphertext ‖ tag (16 bytes)
///
/// .NET's <see cref="ChaCha20Poly1305"/> takes those three parts separately, so
/// <see cref="Encrypt"/>/<see cref="Decrypt"/> concatenate and split them to keep
/// the on-the-wire bytes identical. Do NOT change the layout — it would break
/// every already-paired phone.
/// </summary>
public static class LiftoffCrypto
{
    private const int NonceSize = 12; // ChaChaPoly nonce
    private const int TagSize = 16;   // Poly1305 tag

    public static byte[] Encrypt(ReadOnlySpan<byte> data, byte[] key)
    {
        Span<byte> nonce = stackalloc byte[NonceSize];
        RandomNumberGenerator.Fill(nonce);

        var cipher = new byte[data.Length];
        Span<byte> tag = stackalloc byte[TagSize];

        using var aead = new ChaCha20Poly1305(key);
        aead.Encrypt(nonce, data, cipher, tag);

        var combined = new byte[NonceSize + cipher.Length + TagSize];
        nonce.CopyTo(combined);
        cipher.CopyTo(combined.AsSpan(NonceSize));
        tag.CopyTo(combined.AsSpan(NonceSize + cipher.Length));
        return combined;
    }

    public static bool TryDecrypt(ReadOnlySpan<byte> combined, byte[] key, out byte[] plaintext)
    {
        plaintext = Array.Empty<byte>();
        if (combined.Length < NonceSize + TagSize) return false;

        var nonce = combined[..NonceSize];
        var cipher = combined[NonceSize..^TagSize];
        var tag = combined[^TagSize..];

        var output = new byte[cipher.Length];
        try
        {
            using var aead = new ChaCha20Poly1305(key);
            aead.Decrypt(nonce, cipher, tag, output);
            plaintext = output;
            return true;
        }
        catch (CryptographicException)
        {
            // Authentication failed — caller must fail closed (drop the frame),
            // never feed undecryptable bytes into a real terminal.
            return false;
        }
    }

    /// <summary>SHA-256 of the UTF-8 token bytes — a 32-byte ChaChaPoly key.</summary>
    public static byte[] TokenToKey(string token) =>
        SHA256.HashData(Encoding.UTF8.GetBytes(token));

    /// <summary>32 random bytes, base64-encoded — the pairing token shown in the QR.</summary>
    public static string GenerateToken() =>
        Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
}
