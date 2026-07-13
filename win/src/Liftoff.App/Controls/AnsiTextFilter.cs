using System.Text;

namespace Liftoff.App.Controls;

/// <summary>
/// Stopgap VT stripper: turns a raw ConPTY byte stream into readable plain text
/// by dropping CSI/OSC/escape sequences and honoring only CR/LF/BS. Decodes UTF-8
/// incrementally so multi-byte runes split across reads aren't mangled.
///
/// This exists purely so the terminal is legible before a real VT emulator lands.
/// It intentionally discards colors, cursor moves, and screen clears.
/// </summary>
internal sealed class AnsiTextFilter
{
    private readonly Decoder _utf8 = Encoding.UTF8.GetDecoder();
    private State _state = State.Text;

    private enum State { Text, Escape, Csi, Osc, OscEsc }

    public string Feed(ReadOnlySpan<byte> bytes)
    {
        // Decode to chars first (handles partial runes across calls).
        var chars = new char[bytes.Length + 1];
        int count = _utf8.GetChars(bytes.ToArray(), 0, bytes.Length, chars, 0, flush: false);

        var sb = new StringBuilder(count);
        for (int i = 0; i < count; i++)
        {
            char c = chars[i];
            switch (_state)
            {
                case State.Text:
                    if (c == '\x1b') _state = State.Escape;
                    else if (c == '\b') { if (sb.Length > 0) sb.Remove(sb.Length - 1, 1); }
                    else if (c == '\r') { /* handled with \n by the wrapping TextBlock */ }
                    else if (c == '\n') sb.Append('\n');
                    else if (c >= ' ') sb.Append(c);
                    break;

                case State.Escape:
                    if (c == '[') _state = State.Csi;
                    else if (c == ']') _state = State.Osc;
                    else _state = State.Text; // other 2-char escapes: skip the final byte
                    break;

                case State.Csi:
                    // CSI ends on a final byte in @..~ range.
                    if (c >= '@' && c <= '~') _state = State.Text;
                    break;

                case State.Osc:
                    if (c == '\x07') _state = State.Text;       // BEL terminator
                    else if (c == '\x1b') _state = State.OscEsc; // ST = ESC \
                    break;

                case State.OscEsc:
                    _state = State.Text; // consume the '\' of ST
                    break;
            }
        }
        return sb.ToString();
    }
}
