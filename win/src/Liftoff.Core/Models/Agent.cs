namespace Liftoff.Core.Models;

/// <summary>Known agentic CLIs, detected from a terminal's foreground command line.
/// Port of the macOS <c>Agent</c> enum — the same detection rules and labels so
/// the companion/web clients show identical badges.</summary>
public enum Agent
{
    Claude,
    Codex,
    Gemini,
    Opencode,
    Aider,
    Grok,
    Cursor,
}

public static class AgentDetection
{
    /// <summary>Match the foreground command line to an agent. Mirrors
    /// <c>Agent.detect(in:)</c> on macOS, including the bare-`agent` → Cursor case
    /// while excluding ssh-agent.</summary>
    public static Agent? Detect(string commandLine)
    {
        var cmd = commandLine.ToLowerInvariant();
        if (cmd.Contains("claude")) return Agent.Claude;
        if (cmd.Contains("codex")) return Agent.Codex;
        if (cmd.Contains("gemini") || cmd.Contains("antigravity")) return Agent.Gemini;
        if (cmd.Contains("opencode")) return Agent.Opencode;
        if (cmd.Contains("aider")) return Agent.Aider;
        if (cmd.Contains("grok")) return Agent.Grok;
        if (cmd.Contains("cursor")) return Agent.Cursor;

        if (!cmd.Contains("ssh-agent"))
        {
            foreach (var part in cmd.Split(' ', StringSplitOptions.RemoveEmptyEntries))
            {
                if (part == "agent" || part.EndsWith("/agent") || part.EndsWith("\\agent")
                    || part.EndsWith("\\agent.exe") || part.EndsWith("/agent.exe"))
                    return Agent.Cursor;
            }
        }
        return null;
    }

    /// <summary>Short lowercase name sent to companions and shown as a tab badge.</summary>
    public static string Label(this Agent agent) => agent switch
    {
        Agent.Claude => "claude",
        Agent.Codex => "codex",
        Agent.Gemini => "gemini",
        Agent.Opencode => "opencode",
        Agent.Aider => "aider",
        Agent.Grok => "grok",
        Agent.Cursor => "cursor",
        _ => "",
    };
}
