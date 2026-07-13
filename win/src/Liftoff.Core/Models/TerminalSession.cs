using Liftoff.Core.Pty;

namespace Liftoff.Core.Models;

/// <summary>One terminal tab: a PTY session plus the metadata the UI and the
/// companion protocol report (title, running agent, busy state). Port of the
/// macOS <c>TerminalSession</c>.</summary>
public sealed class TerminalSession : IDisposable
{
    public Guid Id { get; } = Guid.NewGuid();
    public string WorkingDirectory { get; }

    /// <summary>Automatic title (from OSC sequences / cwd). See <see cref="DisplayTitle"/>.</summary>
    public string Title { get; set; }

    /// <summary>User-set tab name; while non-null it wins over <see cref="Title"/>.</summary>
    public string? CustomTitle { get; set; }

    public string DisplayTitle => CustomTitle ?? Title;

    /// <summary>Agentic CLI currently in the foreground, if any.</summary>
    public Agent? RunningAgent { get; set; }

    /// <summary>True while the PTY is actively producing output (recent activity).</summary>
    public bool IsBusy { get; set; }

    public PtySession Pty { get; } = new();

    public TerminalSession(string title, string workingDirectory)
    {
        Title = title;
        WorkingDirectory = workingDirectory;
    }

    public void Dispose() => Pty.Dispose();
}
