using Liftoff.App.Controls;
using Liftoff.Core.Models;
using Liftoff.Core.Protocol;
using Microsoft.UI.Dispatching;

namespace Liftoff.App.Services;

/// <summary>
/// Bridges the transport-only <see cref="CompanionServer"/> to the app's live
/// <see cref="AppStore"/> and <see cref="TerminalView"/> instances. Every call is
/// marshaled onto the UI thread, since it touches XAML-owned state — the macOS
/// server gets this for free by running on <c>@MainActor</c>.
/// </summary>
public sealed class AppSessionHost : ISessionHost
{
    private readonly AppStore _store;
    private readonly DispatcherQueue _ui;

    public AppSessionHost(AppStore store, DispatcherQueue ui)
    {
        _store = store;
        _ui = ui;
    }

    public IReadOnlyList<SessionInfo> ListSessions() => OnUi(() =>
    {
        var list = new List<SessionInfo>();
        foreach (var project in _store.Projects)
            foreach (var term in project.Terminals)
                list.Add(new SessionInfo(
                    term.Id, term.DisplayTitle, project.Id, project.Name,
                    project.ColorHex,
                    term.RunningAgent is Agent a ? a.Label() : null,
                    term.IsBusy));
        return list;
    });

    public bool TryAttach(Guid terminalId, out byte[] snapshot, out int cols, out int rows)
    {
        byte[] snap = Array.Empty<byte>();
        int c = 80, r = 24;
        bool ok = OnUi(() =>
        {
            if (!TerminalView.Live.TryGetValue(terminalId, out var view)) return false;
            snap = view.SnapshotBytes();
            var term = _store.FindTerminal(terminalId);
            if (term != null) { c = term.Pty.Cols; r = term.Pty.Rows; }
            return true;
        });
        snapshot = snap; cols = c; rows = r;
        return ok;
    }

    public void SetOutputHandler(Guid terminalId, Action<ReadOnlyMemory<byte>>? handler) =>
        OnUi(() =>
        {
            if (TerminalView.Live.TryGetValue(terminalId, out var view))
                view.SetRemoteSink(handler);
        });

    public void SendInput(Guid terminalId, byte[] bytes) =>
        OnUi(() => _store.FindTerminal(terminalId)?.Pty.Write(bytes));

    public void Resize(Guid terminalId, int cols, int rows) =>
        OnUi(() => _store.FindTerminal(terminalId)?.Pty.Resize((short)cols, (short)rows));

    public void Close(Guid terminalId) => OnUi(() =>
    {
        foreach (var project in _store.Projects)
        {
            var term = project.Terminals.FirstOrDefault(t => t.Id == terminalId);
            if (term != null) { project.CloseTerminal(term); _store.Touch(); return; }
        }
    });

    // MARK: UI-thread marshaling

    private void OnUi(Action action)
    {
        if (_ui.HasThreadAccess) { action(); return; }
        var done = new ManualResetEventSlim();
        _ui.TryEnqueue(() => { try { action(); } finally { done.Set(); } });
        done.Wait();
    }

    private T OnUi<T>(Func<T> func)
    {
        if (_ui.HasThreadAccess) return func();
        T result = default!;
        var done = new ManualResetEventSlim();
        _ui.TryEnqueue(() => { try { result = func(); } finally { done.Set(); } });
        done.Wait();
        return result;
    }
}
