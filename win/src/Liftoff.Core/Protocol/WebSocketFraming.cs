using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;

namespace Liftoff.Core.Protocol;

/// <summary>
/// Minimal RFC 6455 server framing over a raw TCP socket. We roll our own rather
/// than use HttpListener so no http.sys URL reservation (admin) is needed — the
/// browser client just opens <c>ws://host:48625</c>. Text frames only; that is all
/// the Liftoff protocol uses.
/// </summary>
internal static class WebSocketFraming
{
    private const string GuidMagic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

    /// <summary>Complete the opening handshake. Returns false if the request
    /// isn't a valid WebSocket upgrade.</summary>
    public static bool TryHandshake(NetworkStream stream, out string? key)
    {
        key = null;
        var request = ReadHttpHeaders(stream);
        if (request is null) return false;

        string? wsKey = null;
        foreach (var line in request.Split("\r\n"))
        {
            int colon = line.IndexOf(':');
            if (colon <= 0) continue;
            var name = line[..colon].Trim();
            if (name.Equals("Sec-WebSocket-Key", StringComparison.OrdinalIgnoreCase))
                wsKey = line[(colon + 1)..].Trim();
        }
        if (wsKey is null) return false;

        var accept = Convert.ToBase64String(
            SHA1.HashData(Encoding.ASCII.GetBytes(wsKey + GuidMagic)));
        var response =
            "HTTP/1.1 101 Switching Protocols\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            $"Sec-WebSocket-Accept: {accept}\r\n\r\n";
        var bytes = Encoding.ASCII.GetBytes(response);
        stream.Write(bytes, 0, bytes.Length);
        key = wsKey;
        return true;
    }

    private static string? ReadHttpHeaders(NetworkStream stream)
    {
        var sb = new StringBuilder();
        var one = new byte[1];
        while (sb.Length < 16 * 1024)
        {
            int n = stream.Read(one, 0, 1);
            if (n == 0) return null;
            sb.Append((char)one[0]);
            if (sb.Length >= 4 && sb[^1] == '\n' && sb[^2] == '\r' && sb[^3] == '\n' && sb[^4] == '\r')
                return sb.ToString();
        }
        return null;
    }

    /// <summary>Read one text message, unmasking client payload. Returns null on
    /// close/EOF. Control frames (ping/close) are handled minimally.</summary>
    public static string? ReadTextMessage(NetworkStream stream)
    {
        while (true)
        {
            var header = ReadExact(stream, 2);
            if (header is null) return null;

            bool fin = (header[0] & 0x80) != 0;
            int opcode = header[0] & 0x0F;
            bool masked = (header[1] & 0x80) != 0;
            long len = header[1] & 0x7F;

            if (len == 126)
            {
                var ext = ReadExact(stream, 2);
                if (ext is null) return null;
                len = (ext[0] << 8) | ext[1];
            }
            else if (len == 127)
            {
                var ext = ReadExact(stream, 8);
                if (ext is null) return null;
                len = 0;
                for (int i = 0; i < 8; i++) len = (len << 8) | ext[i];
            }

            byte[] mask = masked ? ReadExact(stream, 4) ?? Array.Empty<byte>() : Array.Empty<byte>();
            var payload = ReadExact(stream, (int)len) ?? Array.Empty<byte>();
            if (masked)
                for (int i = 0; i < payload.Length; i++) payload[i] ^= mask[i % 4];

            switch (opcode)
            {
                case 0x8: return null;                  // close
                case 0x9: continue;                     // ping — ignore (client rarely pings)
                case 0xA: continue;                     // pong
                case 0x1:                               // text
                    if (fin) return Encoding.UTF8.GetString(payload);
                    continue;                           // fragmentation not expected here
                default: continue;
            }
        }
    }

    /// <summary>Send a single unfragmented, unmasked text frame (server->client).</summary>
    public static void WriteTextMessage(NetworkStream stream, string text)
    {
        var payload = Encoding.UTF8.GetBytes(text);
        var header = new List<byte> { 0x81 }; // FIN + text
        if (payload.Length < 126)
            header.Add((byte)payload.Length);
        else if (payload.Length <= ushort.MaxValue)
        {
            header.Add(126);
            header.Add((byte)(payload.Length >> 8));
            header.Add((byte)(payload.Length & 0xFF));
        }
        else
        {
            header.Add(127);
            for (int i = 7; i >= 0; i--) header.Add((byte)((long)payload.Length >> (i * 8)));
        }
        lock (stream)
        {
            stream.Write(header.ToArray(), 0, header.Count);
            stream.Write(payload, 0, payload.Length);
        }
    }

    private static byte[]? ReadExact(NetworkStream stream, int count)
    {
        if (count == 0) return Array.Empty<byte>();
        var buf = new byte[count];
        int off = 0;
        while (off < count)
        {
            int n = stream.Read(buf, off, count - off);
            if (n == 0) return null;
            off += n;
        }
        return buf;
    }
}
