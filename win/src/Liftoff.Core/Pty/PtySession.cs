using System.Runtime.InteropServices;
using static Liftoff.Core.Pty.NativeMethods;

namespace Liftoff.Core.Pty;

/// <summary>
/// One shell running inside a ConPTY. The Windows counterpart of the macOS
/// build's <c>LocalProcess</c>/SwiftTerm PTY: it spawns the shell, pumps bytes
/// out of the read pipe on a background thread, and writes user input into the
/// write pipe. Bytes are raw UTF-8 VT streams — a terminal renderer parses them.
/// </summary>
public sealed class PtySession : IDisposable
{
    /// <summary>Raw output bytes from the shell (already VT-encoded by ConPTY).</summary>
    public event Action<ReadOnlyMemory<byte>>? Output;

    /// <summary>Fires once when the shell process exits.</summary>
    public event Action? Exited;

    private nint _pseudoConsole = nint.Zero;
    private nint _inputWrite = nint.Zero;   // we write here -> shell stdin
    private nint _outputRead = nint.Zero;   // shell stdout -> we read here
    private nint _process = nint.Zero;
    private nint _thread = nint.Zero;
    private nint _attrList = nint.Zero;
    private FileStream? _writeStream;
    private Thread? _reader;
    private volatile bool _disposed;

    public short Cols { get; private set; }
    public short Rows { get; private set; }

    /// <summary>Default login shell. Mirrors the Mac build's `$SHELL -l` intent:
    /// prefer PowerShell 7 if present, else Windows PowerShell, else cmd.</summary>
    public static string DefaultShell()
    {
        var pwsh = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            "PowerShell", "7", "pwsh.exe");
        if (File.Exists(pwsh)) return pwsh;
        return Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
    }

    public void Start(string commandLine, string workingDirectory, short cols = 80, short rows = 24)
    {
        Cols = cols;
        Rows = rows;

        // Two anonymous pipes: one for each direction. ConPTY owns the ends we
        // don't touch; we keep the other end of each.
        if (!CreatePipe(out var inputRead, out _inputWrite, nint.Zero, 0) ||
            !CreatePipe(out _outputRead, out var outputWrite, nint.Zero, 0))
            throw new InvalidOperationException("CreatePipe failed");

        var size = new COORD { X = cols, Y = rows };
        var hr = CreatePseudoConsole(size, inputRead, outputWrite, 0, out _pseudoConsole);
        if (hr != 0) throw new InvalidOperationException($"CreatePseudoConsole failed (0x{hr:X})");

        // ConPTY duplicated the pipe ends it needs; close our copies of those.
        CloseHandle(inputRead);
        CloseHandle(outputWrite);

        StartProcess(commandLine, workingDirectory);

        _writeStream = new FileStream(new Microsoft.Win32.SafeHandles.SafeFileHandle(_inputWrite, ownsHandle: false), FileAccess.Write);
        _reader = new Thread(ReadLoop) { IsBackground = true, Name = "pty-reader" };
        _reader.Start();
    }

    private void StartProcess(string commandLine, string workingDirectory)
    {
        // Build the PROC_THREAD attribute list carrying the pseudoconsole handle.
        nint size = nint.Zero;
        InitializeProcThreadAttributeList(nint.Zero, 1, 0, ref size);
        _attrList = Marshal.AllocHGlobal(size);
        if (!InitializeProcThreadAttributeList(_attrList, 1, 0, ref size))
            throw new InvalidOperationException("InitializeProcThreadAttributeList failed");

        if (!UpdateProcThreadAttribute(_attrList, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                _pseudoConsole, nint.Size, nint.Zero, nint.Zero))
            throw new InvalidOperationException("UpdateProcThreadAttribute failed");

        var si = new STARTUPINFOEX();
        si.StartupInfo.cb = Marshal.SizeOf<STARTUPINFOEX>();
        si.lpAttributeList = _attrList;

        var dir = Directory.Exists(workingDirectory)
            ? workingDirectory
            : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

        if (!CreateProcess(null, commandLine, nint.Zero, nint.Zero, false,
                EXTENDED_STARTUPINFO_PRESENT, nint.Zero, dir, ref si, out var pi))
            throw new InvalidOperationException($"CreateProcess failed ({Marshal.GetLastWin32Error()})");

        _process = pi.hProcess;
        _thread = pi.hThread;

        // Watch for exit on a throwaway thread so consumers get an Exited signal.
        new Thread(() =>
        {
            WaitForSingleObject(_process, 0xFFFFFFFF);
            if (!_disposed) Exited?.Invoke();
        })
        { IsBackground = true, Name = "pty-wait" }.Start();
    }

    private void ReadLoop()
    {
        using var stream = new FileStream(new Microsoft.Win32.SafeHandles.SafeFileHandle(_outputRead, ownsHandle: false), FileAccess.Read);
        var buffer = new byte[16 * 1024];
        try
        {
            while (!_disposed)
            {
                int n = stream.Read(buffer, 0, buffer.Length);
                if (n <= 0) break; // pipe closed -> shell gone
                Output?.Invoke(new ReadOnlyMemory<byte>(buffer, 0, n).ToArray());
            }
        }
        catch (IOException) { /* pipe torn down during dispose */ }
    }

    public void Write(ReadOnlySpan<byte> data)
    {
        if (_disposed || _writeStream is null) return;
        try
        {
            _writeStream.Write(data);
            _writeStream.Flush();
        }
        catch (IOException) { /* shell exited between check and write */ }
    }

    public void Resize(short cols, short rows)
    {
        if (_disposed || _pseudoConsole == nint.Zero) return;
        Cols = cols;
        Rows = rows;
        ResizePseudoConsole(_pseudoConsole, new COORD { X = cols, Y = rows });
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        if (_pseudoConsole != nint.Zero) ClosePseudoConsole(_pseudoConsole);
        if (_process != nint.Zero) TerminateProcess(_process, 0);

        _writeStream?.Dispose();
        if (_inputWrite != nint.Zero) CloseHandle(_inputWrite);
        if (_outputRead != nint.Zero) CloseHandle(_outputRead);
        if (_thread != nint.Zero) CloseHandle(_thread);
        if (_process != nint.Zero) CloseHandle(_process);
        if (_attrList != nint.Zero)
        {
            DeleteProcThreadAttributeList(_attrList);
            Marshal.FreeHGlobal(_attrList);
        }
    }
}
