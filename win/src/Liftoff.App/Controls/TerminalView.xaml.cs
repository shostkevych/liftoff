using System.Collections.Concurrent;
using System.Text;
using Liftoff.Core.Models;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;
using DispatcherQueue = Microsoft.UI.Dispatching.DispatcherQueue;

namespace Liftoff.App.Controls;

/// <summary>
/// Hosts one <see cref="TerminalSession"/>'s PTY and forwards keystrokes to it.
///
/// NOTE: the display here is a STOPGAP. It strips VT/ANSI escape sequences and
/// shows the resulting text so the PTY plumbing is visibly working. It is NOT a
/// real terminal — no colors, cursor addressing, alt-screen, or reflow. The next
/// milestone is a proper VT renderer: either embed Windows Terminal's
/// <c>Microsoft.Terminal.Control</c>, or port SwiftTerm's parser/buffer to a
/// custom-drawn surface. See win/README.md.
/// </summary>
public sealed partial class TerminalView : UserControl
{
    /// <summary>All live views, keyed by terminal id — the companion host looks
    /// terminals up here to attach/snapshot/route input.</summary>
    public static readonly ConcurrentDictionary<Guid, TerminalView> Live = new();

    private readonly DispatcherQueue _dispatcher;
    private TerminalSession? _session;

    // Raw output ring buffer for companion snapshots (last ~256 KB of bytes).
    private readonly object _ringLock = new();
    private readonly byte[] _ring = new byte[256 * 1024];
    private int _ringLen;

    // Extra sink (companion server) fed the same raw bytes as the screen.
    private Action<ReadOnlyMemory<byte>>? _remoteSink;

    private readonly StringBuilder _text = new();
    private readonly AnsiTextFilter _filter = new();

    public TerminalView()
    {
        InitializeComponent();
        _dispatcher = DispatcherQueue.GetForCurrentThread();
        KeyDown += OnKeyDown;
        CharacterReceived += OnCharacterReceived;
        GettingFocus += (_, _) => { }; // focusable; PTY receives keys while focused
    }

    public void Attach(TerminalSession session)
    {
        _session = session;
        Live[session.Id] = this;
        session.Pty.Output += OnPtyOutput;
        session.Pty.Exited += () => _dispatcher.TryEnqueue(() => Append("\r\n[process exited]\r\n"));
    }

    public void Detach()
    {
        if (_session is null) return;
        _session.Pty.Output -= OnPtyOutput;
        Live.TryRemove(_session.Id, out _);
        _session = null;
    }

    private void OnPtyOutput(ReadOnlyMemory<byte> bytes)
    {
        // Runs on the PTY reader thread.
        var copy = bytes.ToArray();

        lock (_ringLock)
        {
            if (copy.Length >= _ring.Length)
            {
                Buffer.BlockCopy(copy, copy.Length - _ring.Length, _ring, 0, _ring.Length);
                _ringLen = _ring.Length;
            }
            else
            {
                int keep = Math.Min(_ringLen, _ring.Length - copy.Length);
                Buffer.BlockCopy(_ring, _ringLen - keep, _ring, 0, keep);
                Buffer.BlockCopy(copy, 0, _ring, keep, copy.Length);
                _ringLen = keep + copy.Length;
            }
        }

        _remoteSink?.Invoke(copy);

        var text = _filter.Feed(copy);
        if (text.Length > 0)
            _dispatcher.TryEnqueue(() => Append(text));
    }

    private void Append(string s)
    {
        _text.Append(s);
        // Cap the on-screen text so it doesn't grow unbounded (stopgap).
        if (_text.Length > 200_000) _text.Remove(0, _text.Length - 150_000);
        Screen.Text = _text.ToString();
        Scroll.ChangeView(null, Scroll.ScrollableHeight, null, disableAnimation: true);
    }

    // MARK: input

    private void OnCharacterReceived(UIElement sender, CharacterReceivedRoutedEventArgs e)
    {
        // Printable characters (respects the keyboard layout).
        var ch = e.Character;
        if (ch >= ' ' || ch == '\t')
            _session?.Pty.Write(Encoding.UTF8.GetBytes(ch.ToString()));
    }

    private void OnKeyDown(object sender, KeyRoutedEventArgs e)
    {
        var pty = _session?.Pty;
        if (pty is null) return;

        byte[]? seq = e.Key switch
        {
            VirtualKey.Enter => new byte[] { 0x0D },
            VirtualKey.Back => new byte[] { 0x7F },
            VirtualKey.Tab => new byte[] { 0x09 },
            VirtualKey.Escape => new byte[] { 0x1B },
            VirtualKey.Up => "\x1b[A"u8.ToArray(),
            VirtualKey.Down => "\x1b[B"u8.ToArray(),
            VirtualKey.Right => "\x1b[C"u8.ToArray(),
            VirtualKey.Left => "\x1b[D"u8.ToArray(),
            VirtualKey.Home => "\x1b[H"u8.ToArray(),
            VirtualKey.End => "\x1b[F"u8.ToArray(),
            VirtualKey.Delete => "\x1b[3~"u8.ToArray(),
            _ => null,
        };

        // Ctrl+letter -> control byte (Ctrl+C = 0x03, etc.).
        var ctrl = Microsoft.UI.Input.InputKeyboardSource
            .GetKeyStateForCurrentThread(VirtualKey.Control)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
        if (ctrl && e.Key >= VirtualKey.A && e.Key <= VirtualKey.Z)
            seq = new[] { (byte)(e.Key - VirtualKey.A + 1) };

        if (seq is not null)
        {
            pty.Write(seq);
            e.Handled = true;
        }
    }

    // MARK: companion server bridge

    public byte[] SnapshotBytes()
    {
        lock (_ringLock)
        {
            var outp = new byte[_ringLen];
            Buffer.BlockCopy(_ring, 0, outp, 0, _ringLen);
            return outp;
        }
    }

    public void SetRemoteSink(Action<ReadOnlyMemory<byte>>? sink) => _remoteSink = sink;
}
