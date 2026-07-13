using System.Collections.ObjectModel;

namespace Liftoff.Core.Models;

/// <summary>A project folder and its terminals — a top-level tab. Port of the
/// macOS <c>Project</c>.</summary>
public sealed class Project
{
    public Guid Id { get; } = Guid.NewGuid();
    public string Folder { get; }
    public string Name => Path.GetFileName(Folder.TrimEnd('\\', '/'));

    /// <summary>Optional per-project palette color, hex "#RRGGBB".</summary>
    public string? ColorHex { get; set; }

    public ObservableCollection<TerminalSession> Terminals { get; } = new();
    public Guid? ActiveTerminalId { get; set; }

    public Project(string folder)
    {
        Folder = folder;
    }

    public TerminalSession AddTerminal(string shellCommandLine)
    {
        var session = new TerminalSession(Name, Folder);
        session.Pty.Start(shellCommandLine, Folder);
        Terminals.Add(session);
        ActiveTerminalId = session.Id;
        return session;
    }

    public void CloseTerminal(TerminalSession session)
    {
        session.Dispose();
        Terminals.Remove(session);
        if (ActiveTerminalId == session.Id)
            ActiveTerminalId = Terminals.Count > 0 ? Terminals[^1].Id : null;
    }
}
