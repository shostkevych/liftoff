using System.Collections.ObjectModel;

namespace Liftoff.Core.Models;

/// <summary>Top-level app state: the open projects and which one is active.
/// Rough port of the macOS <c>AppStore</c> (minus multi-window). The companion
/// server reads this to enumerate sessions.</summary>
public sealed class AppStore
{
    public static AppStore Shared { get; } = new();

    public ObservableCollection<Project> Projects { get; } = new();
    public Guid? ActiveProjectId { get; set; }

    /// <summary>Bumped whenever the project/terminal structure changes, so the
    /// companion server can cheaply invalidate its lookup indexes.</summary>
    public int StructureRevision { get; private set; }

    public Project? ActiveProject =>
        Projects.FirstOrDefault(p => p.Id == ActiveProjectId) ?? Projects.FirstOrDefault();

    public Project AddProject(string folder)
    {
        var existing = Projects.FirstOrDefault(p =>
            string.Equals(p.Folder, folder, StringComparison.OrdinalIgnoreCase));
        if (existing != null)
        {
            ActiveProjectId = existing.Id;
            return existing;
        }

        var project = new Project(folder);
        Projects.Add(project);
        ActiveProjectId = project.Id;
        StructureRevision++;
        return project;
    }

    public void Touch() => StructureRevision++;

    public TerminalSession? FindTerminal(Guid id)
    {
        foreach (var p in Projects)
        {
            var t = p.Terminals.FirstOrDefault(t => t.Id == id);
            if (t != null) return t;
        }
        return null;
    }

    public Project? FindProject(Guid id) => Projects.FirstOrDefault(p => p.Id == id);
}
