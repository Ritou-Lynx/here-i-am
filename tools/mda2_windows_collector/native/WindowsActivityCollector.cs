using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace Mda2WindowsCollector
{
    internal static class NativeMethods
    {
        internal const int WM_WTSSESSION_CHANGE = 0x02B1;
        internal const int WM_POWERBROADCAST = 0x0218;
        internal const int WTS_SESSION_LOCK = 0x7;
        internal const int WTS_SESSION_UNLOCK = 0x8;
        internal const int PBT_APMSUSPEND = 0x4;
        internal const int PBT_APMRESUMEAUTOMATIC = 0x12;
        internal const int PBT_APMRESUMESUSPEND = 0x7;
        internal const int NOTIFY_FOR_THIS_SESSION = 0;

        [StructLayout(LayoutKind.Sequential)]
        internal struct LASTINPUTINFO { internal uint cbSize; internal uint dwTime; }

        [DllImport("kernel32.dll")]
        internal static extern ulong GetTickCount64();

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetLastInputInfo(ref LASTINPUTINFO value);

        [DllImport("wtsapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool WTSRegisterSessionNotification(IntPtr window, int flags);

        [DllImport("wtsapi32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool WTSUnRegisterSessionNotification(IntPtr window);
    }

    internal sealed class FrameWriter : IDisposable
    {
        private readonly BlockingCollection<string> queue = new BlockingCollection<string>(64);
        private readonly Thread thread;
        private bool overflowed;
        private long sequence;
        internal readonly string Nonce;
        internal readonly string Epoch;
        internal readonly int SessionId;
        internal int QualityEpoch;

        internal FrameWriter(string nonce, string epoch, int sessionId)
        {
            Nonce = nonce; Epoch = epoch; SessionId = sessionId;
            thread = new Thread(WriteLoop); thread.IsBackground = true; thread.Name = "mda2-private-frame-writer"; thread.Start();
        }

        private static long WallNow()
        {
            return (long)(DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalMilliseconds;
        }

        private string Frame(long current, string source, string kind, ulong age, long wall, int session, int quality, string value)
        {
            return string.Join("|", new string[] { "MDA2V1", Nonce, Epoch,
                session.ToString(CultureInfo.InvariantCulture), source, kind,
                age.ToString(CultureInfo.InvariantCulture), wall.ToString(CultureInfo.InvariantCulture),
                current.ToString(CultureInfo.InvariantCulture), quality.ToString(CultureInfo.InvariantCulture), value });
        }

        internal void Emit(string source, string kind, ulong age, long wall, int session, int quality, string value)
        {
            if (overflowed)
            {
                long gapSequence = sequence + 1;
                string gap = Frame(gapSequence, source == "quality" ? "windows_wts" : source, "source.gap", age, wall, session, quality, "native_overflow");
                if (queue.TryAdd(gap)) { sequence = gapSequence; overflowed = false; }
            }
            long eventSequence = sequence + 1;
            if (queue.TryAdd(Frame(eventSequence, source, kind, age, wall, session, quality, value))) sequence = eventSequence;
            else overflowed = true;
        }

        internal void EmitNow(string source, string kind, string value)
        {
            Emit(source, kind, NativeMethods.GetTickCount64(), WallNow(), SessionId, QualityEpoch, value);
        }

        private void WriteLoop()
        {
            foreach (string frame in queue.GetConsumingEnumerable())
            {
                Console.Out.WriteLine(frame); Console.Out.Flush();
            }
        }

        public void Dispose()
        {
            queue.CompleteAdding(); thread.Join(5000); queue.Dispose();
        }
    }

    internal sealed class CollectorWindow : NativeWindow, IDisposable
    {
        private readonly FrameWriter writer;
        private readonly System.Windows.Forms.Timer timer;
        private bool registered;

        internal CollectorWindow(FrameWriter writer, int intervalMs)
        {
            this.writer = writer;
            CreateHandle(new CreateParams { Caption = "MDA2 private collector" });
            registered = NativeMethods.WTSRegisterSessionNotification(Handle, NativeMethods.NOTIFY_FOR_THIS_SESSION);
            if (!registered) throw new InvalidOperationException("wts_registration_failed");
            timer = new System.Windows.Forms.Timer(); timer.Interval = intervalMs; timer.Tick += delegate { PollInput(); }; timer.Start();
        }

        private void PollInput()
        {
            NativeMethods.LASTINPUTINFO value = new NativeMethods.LASTINPUTINFO();
            value.cbSize = (uint)Marshal.SizeOf(typeof(NativeMethods.LASTINPUTINFO));
            if (!NativeMethods.GetLastInputInfo(ref value))
            {
                writer.EmitNow("windows_last_input", "source.gap", "permission_lost"); return;
            }
            writer.EmitNow("windows_last_input", "input.sample", value.dwTime.ToString(CultureInfo.InvariantCulture));
        }

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == NativeMethods.WM_WTSSESSION_CHANGE)
            {
                int targetSession = message.LParam.ToInt32();
                if (targetSession == writer.SessionId && message.WParam.ToInt32() == NativeMethods.WTS_SESSION_LOCK)
                    writer.EmitNow("windows_wts", "session.locked", "");
                else if (targetSession == writer.SessionId && message.WParam.ToInt32() == NativeMethods.WTS_SESSION_UNLOCK)
                    writer.EmitNow("windows_wts", "session.unlocked", "");
            }
            else if (message.Msg == NativeMethods.WM_POWERBROADCAST)
            {
                int code = message.WParam.ToInt32();
                if (code == NativeMethods.PBT_APMSUSPEND)
                {
                    writer.QualityEpoch++; writer.EmitNow("quality", "power.suspended", "");
                }
                else if (code == NativeMethods.PBT_APMRESUMEAUTOMATIC || code == NativeMethods.PBT_APMRESUMESUSPEND)
                {
                    writer.QualityEpoch++; writer.EmitNow("quality", "power.resumed", "");
                }
            }
            base.WndProc(ref message);
        }

        public void Dispose()
        {
            timer.Stop(); timer.Dispose();
            if (registered) { NativeMethods.WTSUnRegisterSessionNotification(Handle); registered = false; }
            DestroyHandle();
        }
    }

    internal static class Program
    {
        private static string[] Handshake()
        {
            string line = Console.In.ReadLine();
            string[] parts = line == null ? new string[0] : line.Split('|');
            if (parts.Length != 4 || parts[0] != "HELLO" || parts[1].Length < 32 || parts[2].Length != 36) throw new InvalidOperationException("handshake_rejected");
            return parts;
        }

        private static int Synthetic()
        {
            string[] hello = Handshake(); int session = int.Parse(hello[3], CultureInfo.InvariantCulture);
            using (FrameWriter writer = new FrameWriter(hello[1], hello[2], session))
            {
                Console.Out.WriteLine("READY|" + hello[1] + "|" + hello[2] + "|" + session.ToString(CultureInfo.InvariantCulture)); Console.Out.Flush();
                string line;
                while ((line = Console.In.ReadLine()) != null)
                {
                    if (line == "CLOSE") break;
                    string[] p = line.Split('|');
                    if (p.Length == 2 && p[0] == "RAW")
                    {
                        int count = int.Parse(p[1], CultureInfo.InvariantCulture);
                        if (count < 1 || count > 65536) throw new InvalidOperationException("synthetic_command_rejected");
                        Console.Out.Write(new string('X', count)); Console.Out.Flush(); continue;
                    }
                    if (p.Length != 8 || p[0] != "EMIT") throw new InvalidOperationException("synthetic_command_rejected");
                    writer.QualityEpoch = int.Parse(p[6], CultureInfo.InvariantCulture);
                    writer.Emit(p[1], p[2], ulong.Parse(p[3], CultureInfo.InvariantCulture),
                        long.Parse(p[4], CultureInfo.InvariantCulture), int.Parse(p[5], CultureInfo.InvariantCulture),
                        writer.QualityEpoch, p[7]);
                }
            }
            return 0;
        }

        [STAThread]
        private static int Main(string[] args)
        {
            try
            {
                if (args.Length == 1 && args[0] == "--synthetic") return Synthetic();
                if (args.Length != 1 || args[0] != "--production-explicit") return 64;
                string[] hello = Handshake(); int requestedSession = int.Parse(hello[3], CultureInfo.InvariantCulture);
                int actualSession = Process.GetCurrentProcess().SessionId;
                if (requestedSession != actualSession) throw new InvalidOperationException("session_rejected");
                using (FrameWriter writer = new FrameWriter(hello[1], hello[2], actualSession))
                using (CollectorWindow window = new CollectorWindow(writer, 30000))
                {
                    Console.Out.WriteLine("READY|" + hello[1] + "|" + hello[2] + "|" + actualSession.ToString(CultureInfo.InvariantCulture)); Console.Out.Flush();
                    Thread input = new Thread(new ThreadStart(delegate { while (Console.In.ReadLine() != "CLOSE") { } Application.Exit(); }));
                    input.IsBackground = true; input.Start(); Application.Run();
                }
                return 0;
            }
            catch (Exception error)
            {
                Console.Error.WriteLine(error is InvalidOperationException ? error.Message : "native_collector_failed");
                return 70;
            }
        }
    }
}
