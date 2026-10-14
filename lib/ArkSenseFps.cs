// ArkSense - lib\ArkSenseFps.cs
// Counts ARK's frames per second for the stats card's graph.
//
// How: Windows logs every frame a program hands to the screen as a "Present" event
// of its DXGI graphics layer (the Microsoft-Windows-DXGI event provider). This
// program opens a real-time Event Tracing for Windows (ETW) session for that one
// provider - the same source PresentMon, CapFrameX and Windows' own tools read - and
// counts the events that come from ARK's process id. Nothing is injected into ARK,
// no memory of it is read and nothing of it is hooked: Windows reports the events.
// Needs administrator rights (ArkSense already runs as admin).
//
// Args: <ArkSense pid> <ARK pid> <output file>
// Output, rewritten every second (temp file + rename):
//   line 1:  ok              or   error <reason>
//   line 2:  the last 60 FPS values, comma separated (-1 = no frames seen yet)
// Ends by itself when ArkSense or ARK close, or when <TEMP>\ArkSense-fps.stop
// appears, and always stops its trace session on the way out.
//
// Compiled on the user's PC by ArkSense (lib\Ovl.ahk CsBuild) with Windows' own C#
// compiler: csc /target:winexe /platform:x64. 64-bit only (fixed struct offsets).

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

static class Program
{
    const string Session = "ArkSenseFps";
    static readonly Guid Dxgi = new Guid("CA11C036-0102-4A2D-A6AD-F03CFED5D3C9");

    const uint EVENT_TRACE_REAL_TIME_MODE = 0x00000100;
    const uint WNODE_FLAG_TRACED_GUID = 0x00020000;
    const uint PROCESS_TRACE_MODE_REAL_TIME = 0x00000100;
    const uint PROCESS_TRACE_MODE_EVENT_RECORD = 0x10000000;
    const uint EVENT_TRACE_CONTROL_STOP = 1;
    const uint EVENT_CONTROL_CODE_ENABLE_PROVIDER = 1;
    const uint ERROR_ALREADY_EXISTS = 183;
    const uint ERROR_ACCESS_DENIED = 5;
    const ulong INVALID_TRACE = 0xFFFFFFFFFFFFFFFFUL;

    // EVENT_TRACE_PROPERTIES (x64): 120 bytes, then room for the names
    const int PropsSize = 120 + 1024;

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
    static extern uint StartTraceW(out ulong handle, string name, IntPtr props);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
    static extern uint ControlTraceW(ulong handle, string name, IntPtr props, uint code);
    [DllImport("advapi32.dll")]
    static extern uint EnableTraceEx2(ulong handle, ref Guid provider, uint code, byte level,
                                      ulong anyKeyword, ulong allKeyword, uint timeout, IntPtr parms);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern ulong OpenTraceW(IntPtr logfile);
    [DllImport("advapi32.dll")]
    static extern uint ProcessTrace(ulong[] handles, uint count, IntPtr start, IntPtr end);
    [DllImport("advapi32.dll")]
    static extern uint CloseTrace(ulong handle);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate void RecordCallback(IntPtr record);

    static readonly RecordCallback Callback = OnEvent;   // kept alive for the whole run
    static int game;
    static readonly object Gate = new object();
    static readonly Queue<long> Stamps = new Queue<long>();
    static long newest;
    static int arrivedAt;                                 // Environment.TickCount of the last frame
    static bool seen;

    static string outPath, tmpPath, stopPath;

    static void Write(string head, string body)
    {
        try
        {
            File.WriteAllText(tmpPath, head + "\r\n" + body, Encoding.ASCII);
            if (File.Exists(outPath)) File.Delete(outPath);
            File.Move(tmpPath, outPath);
        }
        catch { }   // ArkSense may be reading it right now; next second retries
    }

    static IntPtr NewProps()
    {
        IntPtr p = Marshal.AllocHGlobal(PropsSize);
        for (int i = 0; i < PropsSize; i++) Marshal.WriteByte(p, i, 0);
        Marshal.WriteInt32(p, 0, PropsSize);                          // Wnode.BufferSize
        Marshal.WriteInt32(p, 40, 1);                                 // Wnode.ClientContext: QPC time stamps
        Marshal.WriteInt32(p, 44, (int)WNODE_FLAG_TRACED_GUID);       // Wnode.Flags
        Marshal.WriteInt32(p, 48, 64);                                // BufferSize (KB)
        Marshal.WriteInt32(p, 52, 4);                                 // MinimumBuffers
        Marshal.WriteInt32(p, 56, 16);                                // MaximumBuffers
        Marshal.WriteInt32(p, 64, (int)EVENT_TRACE_REAL_TIME_MODE);   // LogFileMode
        Marshal.WriteInt32(p, 68, 1);                                 // FlushTimer: 1 s
        Marshal.WriteInt32(p, 116, 120);                              // LoggerNameOffset
        return p;
    }

    static void StopSession()
    {
        IntPtr p = NewProps();
        try { ControlTraceW(0, Session, p, EVENT_TRACE_CONTROL_STOP); }
        catch { }
        finally { Marshal.FreeHGlobal(p); }
    }

    // EVENT_RECORD (x64): EventHeader.ProcessId at 12, TimeStamp at 16, ProviderId at 24,
    // EventDescriptor.Id at 40
    static void OnEvent(IntPtr rec)
    {
        try
        {
            if (Marshal.ReadInt32(rec, 12) != game) return;
            int id = (ushort)Marshal.ReadInt16(rec, 40);
            if (id != 42 && id != 55) return;                         // Present_Start, PresentMultiplaneOverlay_Start
            byte[] b = new byte[16];
            Marshal.Copy(new IntPtr(rec.ToInt64() + 24), b, 0, 16);
            if (new Guid(b) != Dxgi) return;
            long ts = Marshal.ReadInt64(rec, 16);
            lock (Gate)
            {
                Stamps.Enqueue(ts);
                if (ts > newest) newest = ts;
                arrivedAt = Environment.TickCount;
                seen = true;
            }
        }
        catch { }
    }

    static bool Alive(int pid)
    {
        try { Process p = Process.GetProcessById(pid); return !p.HasExited; }
        catch { return false; }
    }

    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length < 3) return 2;
        int parent;
        if (!int.TryParse(args[0], out parent) || !int.TryParse(args[1], out game)) return 2;
        outPath = args[2];
        tmpPath = outPath + ".tmp";
        stopPath = Path.Combine(Path.GetTempPath(), "ArkSense-fps.stop");
        if (IntPtr.Size != 8) { Write("error needs 64-bit Windows", ""); return 1; }

        ulong session = 0, trace = INVALID_TRACE;
        IntPtr props = IntPtr.Zero, logfile = IntPtr.Zero, name = IntPtr.Zero;
        try
        {
            StopSession();                                            // one left from an earlier run
            props = NewProps();
            uint r = StartTraceW(out session, Session, props);
            if (r == ERROR_ALREADY_EXISTS)
            {
                StopSession();
                Marshal.FreeHGlobal(props);
                props = NewProps();
                r = StartTraceW(out session, Session, props);
            }
            if (r == ERROR_ACCESS_DENIED) { Write("error needs administrator rights", ""); return 1; }
            if (r != 0) { Write("error could not start the event trace (" + r + ")", ""); return 1; }

            Guid prov = Dxgi;
            r = EnableTraceEx2(session, ref prov, EVENT_CONTROL_CODE_ENABLE_PROVIDER, 4,
                               0xFFFFFFFFFFFFFFFFUL, 0, 0, IntPtr.Zero);
            if (r != 0) { Write("error could not listen to DXGI frames (" + r + ")", ""); return 1; }

            // EVENT_TRACE_LOGFILEW (x64, 448 bytes): LoggerName at 8, ProcessTraceMode at 28,
            // EventRecordCallback at 424
            logfile = Marshal.AllocHGlobal(448);
            for (int i = 0; i < 448; i++) Marshal.WriteByte(logfile, i, 0);
            name = Marshal.StringToHGlobalUni(Session);
            Marshal.WriteIntPtr(logfile, 8, name);
            Marshal.WriteInt32(logfile, 28, unchecked((int)(PROCESS_TRACE_MODE_REAL_TIME | PROCESS_TRACE_MODE_EVENT_RECORD)));
            Marshal.WriteIntPtr(logfile, 424, Marshal.GetFunctionPointerForDelegate(Callback));
            trace = OpenTraceW(logfile);
            if (trace == INVALID_TRACE)
            {
                Write("error could not open the event trace (" + Marshal.GetLastWin32Error() + ")", "");
                return 1;
            }
            ulong[] handles = new ulong[] { trace };
            Thread pump = new Thread(() => { try { ProcessTrace(handles, 1, IntPtr.Zero, IntPtr.Zero); } catch { } });
            pump.IsBackground = true;
            pump.Start();

            // ProcessTrace hands real-time events over with their TimeStamp converted to
            // system time (100 ns units) - not QPC ticks. Step 25: this used Stopwatch.Frequency,
            // which only matched on PCs whose QPC runs at 10 MHz (wrong FPS / none elsewhere).
            const long freq = 10000000;                               // 100 ns units per second
            List<int> hist = new List<int>();
            int startedAt = Environment.TickCount;
            while (true)
            {
                Thread.Sleep(1000);
                if (!Alive(parent) || !Alive(game) || File.Exists(stopPath)) break;
                int fps;
                lock (Gate)
                {
                    // frames in the newest full second the trace has delivered
                    while (Stamps.Count > 0 && Stamps.Peek() < newest - 2 * freq) Stamps.Dequeue();
                    int cnt = 0;
                    foreach (long t in Stamps) if (t > newest - freq) cnt++;
                    if (!seen) fps = -1;
                    else if (Environment.TickCount - arrivedAt > 2500) fps = 0;   // nothing drawn lately
                    else fps = cnt;
                }
                hist.Add(fps);
                while (hist.Count > 60) hist.RemoveAt(0);
                StringBuilder sb = new StringBuilder();
                for (int i = 0; i < hist.Count; i++) { if (i > 0) sb.Append(','); sb.Append(hist[i]); }
                string head = "ok";
                if (!seen && Environment.TickCount - startedAt > 8000) head = "ok no frames from ARK yet";
                Write(head, sb.ToString());
            }
            return 0;
        }
        catch (Exception e)
        {
            Write("error " + e.Message.Replace('\r', ' ').Replace('\n', ' '), "");
            return 1;
        }
        finally
        {
            if (session != 0)
            {
                IntPtr p = NewProps();
                try { ControlTraceW(session, null, p, EVENT_TRACE_CONTROL_STOP); } catch { }
                Marshal.FreeHGlobal(p);
            }
            if (trace != INVALID_TRACE) try { CloseTrace(trace); } catch { }
            if (props != IntPtr.Zero) Marshal.FreeHGlobal(props);
            if (name != IntPtr.Zero) Marshal.FreeHGlobal(name);
            // logfile stays allocated: ProcessTrace may still be returning on its thread
            try { File.Delete(stopPath); } catch { }
        }
    }
}
