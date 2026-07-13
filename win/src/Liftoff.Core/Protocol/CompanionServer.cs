using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using Liftoff.Core.Crypto;

namespace Liftoff.Core.Protocol;

/// <summary>
/// LAN/VPN server letting the iOS companion and browser clients list projects,
/// attach to a terminal, stream its PTY output, and send input. Transport-only
/// port of the macOS <c>CompanionServer</c> — identical wire protocol so existing
/// Liftoff Air builds and the bundled web client work unchanged.
///
/// Protocol: newline-delimited JSON, one message per line (TCP) or one text frame
/// (WebSocket). After auth, data payloads (<c>d</c>) are ChaChaPoly-encrypted for
/// TCP clients and plaintext for WebSocket clients.
/// </summary>
public sealed class CompanionServer
{
    public const int TcpPort = 48624;
    public const int WsPort = 48625;

    private readonly ISessionHost _host;
    private readonly Func<string> _token;       // pairing token (companion)
    private readonly Func<string> _webPassword; // web client password

    private TcpListener? _tcp;
    private TcpListener? _ws;
    private volatile bool _running;

    private readonly ConcurrentDictionary<Client, byte> _clients = new();
    // terminalId -> set of subscribed clients
    private readonly Dictionary<Guid, HashSet<Client>> _subscribers = new();
    private readonly object _subLock = new();

    public CompanionServer(ISessionHost host, Func<string> token, Func<string> webPassword)
    {
        _host = host;
        _token = token;
        _webPassword = webPassword;
    }

    public void Start()
    {
        if (_running) return;
        _running = true;

        _tcp = new TcpListener(IPAddress.Any, TcpPort);
        _tcp.Start();
        Accept(_tcp, isWs: false);

        _ws = new TcpListener(IPAddress.Any, WsPort);
        _ws.Start();
        Accept(_ws, isWs: true);
    }

    public void Stop()
    {
        _running = false;
        _tcp?.Stop();
        _ws?.Stop();
        foreach (var c in _clients.Keys) c.Close();
        _clients.Clear();
    }

    private void Accept(TcpListener listener, bool isWs)
    {
        Task.Run(async () =>
        {
            while (_running)
            {
                TcpClient socket;
                try { socket = await listener.AcceptTcpClientAsync(); }
                catch { break; } // listener stopped
                _ = Task.Run(() => ServeClient(socket, isWs));
            }
        });
    }

    private void ServeClient(TcpClient socket, bool isWs)
    {
        var stream = socket.GetStream();
        var client = new Client(socket, stream, isWs);

        if (isWs && !WebSocketFraming.TryHandshake(stream, out _))
        {
            socket.Close();
            return;
        }

        _clients[client] = 0;
        try
        {
            if (isWs) ServeWs(client);
            else ServeTcp(client);
        }
        catch { /* connection error */ }
        finally { Disconnect(client); }
    }

    private void ServeWs(Client client)
    {
        while (_running)
        {
            var line = WebSocketFraming.ReadTextMessage(client.Stream);
            if (line is null) break;
            Handle(line, client);
        }
    }

    private void ServeTcp(Client client)
    {
        var buffer = new byte[64 * 1024];
        var inbox = new List<byte>();
        while (_running)
        {
            int n = client.Stream.Read(buffer, 0, buffer.Length);
            if (n <= 0) break;
            inbox.AddRange(buffer.AsSpan(0, n).ToArray());

            int nl;
            while ((nl = inbox.IndexOf(0x0A)) >= 0)
            {
                var lineBytes = inbox.GetRange(0, nl).ToArray();
                inbox.RemoveRange(0, nl + 1);
                if (lineBytes.Length > 0)
                    Handle(System.Text.Encoding.UTF8.GetString(lineBytes), client);
            }
            if (inbox.Count > 1_000_000) break; // runaway line — drop client
        }
    }

    // MARK: message handling

    private void Handle(string line, Client client)
    {
        JsonElement msg;
        try { msg = JsonDocument.Parse(line).RootElement; }
        catch { return; }
        if (!msg.TryGetProperty("t", out var tEl) || tEl.ValueKind != JsonValueKind.String) return;
        var t = tEl.GetString()!;

        // --- Auth: TCP clients present the pairing token; WS clients a password.
        if (!client.Authed)
        {
            if (!client.IsWs)
            {
                var expected = _token();
                if (string.IsNullOrEmpty(expected)) { Send(client, new { t = "authfail" }); return; }
                if (t == "auth" && Str(msg, "token") == expected)
                {
                    client.Authed = true;
                    Send(client, new { t = "authok" });
                }
                else Send(client, new { t = t == "auth" ? "authfail" : "needauth" });
                return;
            }
            else
            {
                var password = _webPassword();
                if (string.IsNullOrEmpty(password)) { Send(client, new { t = "blocked" }); return; }
                if (t == "auth" && Str(msg, "pass") == password)
                {
                    client.Authed = true;
                    Send(client, new { t = "authok" });
                }
                else Send(client, new { t = t == "auth" ? "authfail" : "needauth" });
                return;
            }
        }

        switch (t)
        {
            case "list":
                SendSessions(client);
                break;
            case "attach":
                if (TryGuid(msg, "id", out var aid)) Attach(client, aid);
                break;
            case "input":
                if (client.Attached is Guid iid && Str(msg, "d") is string b64in)
                {
                    var payload = SafeBase64(b64in);
                    if (payload is null) break;
                    byte[]? raw = client.IsWs ? payload : Decrypt(payload);
                    if (raw != null) _host.SendInput(iid, raw);
                }
                break;
            case "resize":
                if (client.Attached is Guid rid &&
                    msg.TryGetProperty("cols", out var c) && msg.TryGetProperty("rows", out var r))
                    _host.Resize(rid, c.GetInt32(), r.GetInt32());
                break;
            case "detach":
                if (client.Attached is Guid did) Release(did, client);
                client.Attached = null;
                break;
            case "close":
                if (TryGuid(msg, "id", out var cid)) { _host.Close(cid); BroadcastSessions(); }
                break;
            // TODO(roadmap): open, openempty, newtab, recents, upload, greeting.
            default:
                break;
        }
    }

    private void SendSessions(Client client)
    {
        var items = _host.ListSessions().Select(s =>
        {
            var d = new Dictionary<string, object>
            {
                ["tid"] = s.TerminalId.ToString(),
                ["title"] = s.Title,
                ["pid"] = s.ProjectId.ToString(),
                ["pname"] = s.ProjectName,
            };
            if (s.ColorHex != null) d["color"] = s.ColorHex;
            if (s.Agent != null) d["agent"] = s.Agent;
            if (s.Busy) d["busy"] = true;
            return d;
        }).ToList();
        Send(client, new { t = "sessions", items });
    }

    private void BroadcastSessions()
    {
        foreach (var c in _clients.Keys)
            if (c.Authed) SendSessions(c);
    }

    /// <summary>Debounced session refresh — call when a terminal's activity or
    /// agent state changes. Mirrors <c>terminalActivityChanged()</c>.</summary>
    private int _broadcastScheduled;
    public void TerminalActivityChanged()
    {
        if (Interlocked.Exchange(ref _broadcastScheduled, 1) == 1) return;
        Task.Delay(100).ContinueWith(_ =>
        {
            Interlocked.Exchange(ref _broadcastScheduled, 0);
            BroadcastSessions();
        });
    }

    private void Attach(Client client, Guid id)
    {
        if (client.Attached is Guid prev) Release(prev, client);
        client.Attached = id;

        if (!_host.TryAttach(id, out var snapshot, out var cols, out var rows)) return;

        lock (_subLock)
        {
            if (!_subscribers.TryGetValue(id, out var set))
            {
                set = new HashSet<Client>();
                _subscribers[id] = set;
                // First subscriber: wire the terminal's output to our fanout.
                _host.SetOutputHandler(id, bytes => Fanout(id, bytes));
            }
            set.Add(client);
        }

        Send(client, new { t = "size", cols, rows });
        SendPayload(client, "snapshot", snapshot);
    }

    private void Release(Guid terminalId, Client client)
    {
        lock (_subLock)
        {
            if (_subscribers.TryGetValue(terminalId, out var set))
            {
                set.Remove(client);
                if (set.Count == 0)
                {
                    _subscribers.Remove(terminalId);
                    _host.SetOutputHandler(terminalId, null);
                }
            }
        }
    }

    private void Fanout(Guid terminalId, ReadOnlyMemory<byte> bytes)
    {
        List<Client> targets;
        lock (_subLock)
        {
            if (!_subscribers.TryGetValue(terminalId, out var set) || set.Count == 0) return;
            targets = set.ToList();
        }
        foreach (var client in targets)
            SendPayload(client, "output", bytes.ToArray());
    }

    // MARK: wire helpers

    /// <summary>Send a `d`-payload message, encrypting for TCP (fail closed — no
    /// plaintext fallback) and plaintext base64 for WebSocket.</summary>
    private void SendPayload(Client client, string type, byte[] data)
    {
        string payload;
        if (client.IsWs)
            payload = Convert.ToBase64String(data);
        else
        {
            var key = LiftoffCrypto.TokenToKey(_token());
            payload = Convert.ToBase64String(LiftoffCrypto.Encrypt(data, key));
        }
        Send(client, new { t = type, d = payload });
    }

    private byte[]? Decrypt(byte[] payload)
    {
        var key = LiftoffCrypto.TokenToKey(_token());
        return LiftoffCrypto.TryDecrypt(payload, key, out var raw) ? raw : null;
    }

    private void Send(Client client, object dict)
    {
        var json = JsonSerializer.Serialize(dict);
        try
        {
            if (client.IsWs)
                WebSocketFraming.WriteTextMessage(client.Stream, json);
            else
            {
                var bytes = System.Text.Encoding.UTF8.GetBytes(json + "\n");
                lock (client.WriteLock) client.Stream.Write(bytes, 0, bytes.Length);
            }
        }
        catch { Disconnect(client); }
    }

    private void Disconnect(Client client)
    {
        if (!_clients.TryRemove(client, out _)) return;
        if (client.Attached is Guid id) Release(id, client);
        client.Close();
    }

    private static string? Str(JsonElement msg, string name) =>
        msg.TryGetProperty(name, out var el) && el.ValueKind == JsonValueKind.String ? el.GetString() : null;

    private static bool TryGuid(JsonElement msg, string name, out Guid guid)
    {
        guid = default;
        return Str(msg, name) is string s && Guid.TryParse(s, out guid);
    }

    private static byte[]? SafeBase64(string s)
    {
        try { return Convert.FromBase64String(s); } catch { return null; }
    }

    private sealed class Client
    {
        public readonly TcpClient Socket;
        public readonly NetworkStream Stream;
        public readonly bool IsWs;
        public readonly object WriteLock = new();
        public bool Authed;
        public Guid? Attached;

        public Client(TcpClient socket, NetworkStream stream, bool isWs)
        {
            Socket = socket;
            Stream = stream;
            IsWs = isWs;
        }

        public void Close()
        {
            try { Socket.Close(); } catch { }
        }
    }
}
