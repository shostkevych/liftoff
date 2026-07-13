namespace Liftoff.Core.Protocol;

/// <summary>Snapshot of one terminal for the `sessions` list message.</summary>
public readonly record struct SessionInfo(
    Guid TerminalId,
    string Title,
    Guid ProjectId,
    string ProjectName,
    string? ColorHex,
    string? Agent,
    bool Busy);

/// <summary>
/// The bridge between the transport-only <see cref="CompanionServer"/> and the
/// app's live state + terminals. The app implements this and marshals every call
/// onto the UI thread (the macOS server runs on <c>@MainActor</c>; we mirror that
/// by making the host responsible for thread affinity).
/// </summary>
public interface ISessionHost
{
    IReadOnlyList<SessionInfo> ListSessions();

    /// <summary>Register interest in a terminal's output. Returns false if unknown.
    /// <paramref name="snapshot"/> is the recent screen bytes to replay to a new
    /// client; <paramref name="cols"/>/<paramref name="rows"/> are its size.</summary>
    bool TryAttach(Guid terminalId, out byte[] snapshot, out int cols, out int rows);

    /// <summary>Set (or clear, with null) the single output sink for a terminal.
    /// The server fans this out to every subscriber — matching the macOS model
    /// where a terminal has one <c>onOutput</c> closure.</summary>
    void SetOutputHandler(Guid terminalId, Action<ReadOnlyMemory<byte>>? handler);

    void SendInput(Guid terminalId, byte[] bytes);
    void Resize(Guid terminalId, int cols, int rows);
    void Close(Guid terminalId);
}
