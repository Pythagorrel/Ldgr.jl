// LDGR.exe - the window launcher for LDGR 6.0 (see packaging\DESIGN.md sections 1-4).
// C# 5 only (in-box csc.exe): no string interpolation, no ?., no expression-bodied members, no nameof.
// Non-ASCII characters are written as \u escapes so the file compiles the same under any code page.
//
// Test-only environment variables (never needed in normal use):
//   LDGR_TEST_NOACTIVATE=1       window starts minimized without taking focus; message boxes are replaced by
//                                log lines "[launcher] MESSAGE: <text>" and "[launcher] ACTION: <what OK does>"
//   LDGR_TEST_READY_TIMEOUT_S=n  the "taking too long" message appears after n seconds (default 180)

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

// ---------------------------------------------------------------------------------------
// Entry point. Main must not mention any WebView2 type: the resolver is registered first.
// ---------------------------------------------------------------------------------------
static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        AppDomain.CurrentDomain.AssemblyResolve += Resolver.OnResolve;
        return Launcher.Run(args);
    }
}

static class Resolver
{
    public static Assembly OnResolve(object sender, ResolveEventArgs e)
    {
        try
        {
            string name = new AssemblyName(e.Name).Name;
            if (name == "Microsoft.Web.WebView2.Core" || name == "Microsoft.Web.WebView2.WinForms")
            {
                string p = Path.Combine(Launcher.Home, "runtime", "webview2", name + ".dll");
                if (File.Exists(p)) return Assembly.LoadFrom(p);
            }
        }
        catch { }
        return null;
    }
}

// ---------------------------------------------------------------------------------------
// Native helpers
// ---------------------------------------------------------------------------------------
static class Native
{
    public const int SW_RESTORE = 9;
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("kernel32.dll")] public static extern bool AllocConsole();
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr a, string name);
    [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int cls, IntPtr info, int len);
    [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr proc);

    [StructLayout(LayoutKind.Sequential)]
    struct BASIC
    {
        public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinWS, MaxWS;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass, SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)] struct IOC { public ulong a, b, c, d, e, f; }
    [StructLayout(LayoutKind.Sequential)]
    struct EXT { public BASIC Basic; public IOC Io; public UIntPtr ProcMem, JobMem, PeakProc, PeakJob; }

    // The handle is kept for the launcher's whole life: when LDGR.exe dies, Windows closes it and
    // kills everything in the job (JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE).
    static IntPtr job = IntPtr.Zero;

    public static bool AddToJob(Process p)
    {
        try
        {
            if (job == IntPtr.Zero)
            {
                IntPtr j = CreateJobObject(IntPtr.Zero, null);
                if (j == IntPtr.Zero) return false;
                EXT x = new EXT();
                x.Basic.LimitFlags = 0x2000;
                int len = Marshal.SizeOf(typeof(EXT));
                IntPtr buf = Marshal.AllocHGlobal(len);
                Marshal.StructureToPtr(x, buf, false);
                bool ok = SetInformationJobObject(j, 9, buf, len);
                Marshal.FreeHGlobal(buf);
                if (!ok) return false;
                job = j;
            }
            return AssignProcessToJobObject(job, p.Handle);
        }
        catch { return false; }
    }
}

// ---------------------------------------------------------------------------------------
// Log: HOME\logs\LDGR yyyy-MM-dd.log, UTF-8 without BOM, append, flushed per line.
// ---------------------------------------------------------------------------------------
static class Logger
{
    static object lk = new object();
    static FileStream fs;
    static string curDay;
    static string dir;
    static bool mirror;
    static UTF8Encoding utf8 = new UTF8Encoding(false);

    public static void Init(string home, bool mirrorToConsole)
    {
        dir = Path.Combine(home, "logs");
        mirror = mirrorToConsole;
        try { Directory.CreateDirectory(dir); } catch { }
        try
        {
            foreach (string f in Directory.GetFiles(dir, "LDGR *.log"))
            {
                try { if (File.GetLastWriteTime(f) < DateTime.Now.AddDays(-60)) File.Delete(f); } catch { }
            }
        }
        catch { }
    }

    public static string PathFor(DateTime d)
    {
        return Path.Combine(dir, "LDGR " + d.ToString("yyyy-MM-dd") + ".log");
    }

    public static string PathToday() { return PathFor(DateTime.Now); }

    // Never throws: the readers must keep draining Julia's pipes.
    public static void Write(string text)
    {
        try
        {
            lock (lk)
            {
                DateTime now = DateTime.Now;
                string line = now.ToString("HH:mm:ss") + " " + text;
                if (mirror) { try { Console.WriteLine(line); } catch { } }
                try
                {
                    string day = now.ToString("yyyy-MM-dd");
                    if (fs == null || day != curDay)
                    {
                        if (fs != null) { try { fs.Dispose(); } catch { } fs = null; }
                        fs = new FileStream(PathFor(now), FileMode.Append, FileAccess.Write,
                                            FileShare.ReadWrite | FileShare.Delete);
                        curDay = day;
                    }
                    byte[] b = utf8.GetBytes(line + "\r\n");
                    fs.Write(b, 0, b.Length);
                    fs.Flush();
                }
                catch
                {
                    try { if (fs != null) fs.Dispose(); } catch { }
                    fs = null;
                }
            }
        }
        catch { }
    }

    public static void L(string text) { Write("[launcher] " + text); }
}

// ---------------------------------------------------------------------------------------
// Launcher: modes, single instance, message boxes
// ---------------------------------------------------------------------------------------
static class Launcher
{
    public static string Home;
    public static string ExePath;
    public static bool Test;
    public static bool Debug;
    public static int ExitCode;

    static Mutex mutex;
    static EventWaitHandle closingEvent;
    static string hash;

    public static string MutexName { get { return "Global\\LDGR-6-" + hash; } }
    public static string ClosingName { get { return MutexName + "-closing"; } }

    public static string Flat(string s)
    {
        return s.Replace("\r\n", " | ").Replace("\n", " | ").Replace("\r", " | ");
    }

    public static DialogResult Msg(IWin32Window owner, string text, MessageBoxButtons buttons,
                                   MessageBoxIcon icon, string okAction)
    {
        if (Test)
        {
            Logger.L("MESSAGE: " + Flat(text));
            Logger.L("ACTION: " + okAction);
            return DialogResult.OK;
        }
        try { return MessageBox.Show(owner, text, "LDGR", buttons, icon); }
        catch (Exception ex) { Logger.L("message box failed: " + ex.Message); return DialogResult.OK; }
    }

    // Standard Windows command-line quoting; a trailing backslash is doubled so it cannot eat the quote.
    public static string Q(string s)
    {
        StringBuilder sb = new StringBuilder("\"");
        int bs = 0;
        foreach (char c in s)
        {
            if (c == '\\') { bs++; }
            else if (c == '"') { sb.Append('\\', bs * 2 + 1); sb.Append('"'); bs = 0; }
            else { sb.Append('\\', bs); bs = 0; sb.Append(c); }
        }
        sb.Append('\\', bs * 2);
        sb.Append('"');
        return sb.ToString();
    }

    static bool Starts(string name, string prefix)
    {
        return name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase);
    }

    // The one place that knows how Julia is started.
    public static ProcessStartInfo JuliaInfo(bool console, bool redirect)
    {
        string julia = Path.Combine(Home, "runtime", "julia", "bin", "julia.exe");
        string env = Path.Combine(Home, "runtime", "env");
        string img = Path.Combine(Home, "runtime", "ldgr.dll");
        string a = "--startup-file=no --history-file=no " + Q("--project=" + env) + " -J " + Q(img) + " ";
        a += console ? "-i -e \"using LDGR\"" : "-e \"LDGR.app_main()\"";
        ProcessStartInfo psi = new ProcessStartInfo(julia, a);
        psi.WorkingDirectory = Home;
        psi.UseShellExecute = false;
        psi.CreateNoWindow = !console || Test;
        List<string> drop = new List<string>();
        foreach (string k in psi.EnvironmentVariables.Keys)
        {
            if (Starts(k, "JULIA_") || Starts(k, "SSL_CERT_") || Starts(k, "WEBVIEW2_")
                || string.Equals(k, "LEDGER_ROOT", StringComparison.OrdinalIgnoreCase)
                || string.Equals(k, "LDGR_NO_DIGEST", StringComparison.OrdinalIgnoreCase)
                || string.Equals(k, "LDGR_DIGEST_NOW", StringComparison.OrdinalIgnoreCase)
                || string.Equals(k, "LDGR_NO_WARMUP", StringComparison.OrdinalIgnoreCase)
                || string.Equals(k, "LDGR_NOTIFY_CONFIG", StringComparison.OrdinalIgnoreCase))
                drop.Add(k);
        }
        foreach (string k in drop) psi.EnvironmentVariables.Remove(k);
        psi.EnvironmentVariables["JULIA_DEPOT_PATH"] = Path.Combine(Home, "runtime", "depot");
        psi.EnvironmentVariables["LEDGER_ROOT"] = Path.Combine(Home, "Records");
        psi.EnvironmentVariables["LDGR_NOTIFY_CONFIG"] = Path.Combine(Home, "settings", "notify.toml");
        psi.EnvironmentVariables["LDGR_NO_BROWSER"] = "1";
        if (redirect)
        {
            psi.RedirectStandardInput = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            UTF8Encoding u = new UTF8Encoding(false);
            psi.StandardOutputEncoding = u;
            psi.StandardErrorEncoding = u;
            // Nothing is ever written to Julia's input; closing it is the stop signal.
        }
        return psi;
    }

    static string HashOf(string home)
    {
        string key = Path.GetFullPath(home).TrimEnd('\\').ToLowerInvariant();
        using (SHA256 sha = SHA256.Create())
        {
            byte[] h = sha.ComputeHash(Encoding.UTF8.GetBytes(key));
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < 8; i++) sb.Append(h[i].ToString("x2"));
            return sb.ToString();
        }
    }

    enum Got { Yes, Held, Denied }

    static Got TryGetMutex(int waitMs)
    {
        try
        {
            bool created;
            MutexSecurity sec = new MutexSecurity();
            sec.AddAccessRule(new MutexAccessRule(new SecurityIdentifier(WellKnownSidType.WorldSid, null),
                                                  MutexRights.FullControl, AccessControlType.Allow));
            mutex = new Mutex(false, MutexName, out created, sec);
        }
        catch (UnauthorizedAccessException) { return Got.Denied; }
        return WaitMutex(waitMs) ? Got.Yes : Got.Held;
    }

    static bool WaitMutex(int ms)
    {
        try { return mutex.WaitOne(ms); }
        catch (AbandonedMutexException) { return true; }
    }

    static void ReleaseMutex()
    {
        try { if (mutex != null) mutex.ReleaseMutex(); } catch { }
    }

    static bool ClosingEventSet()
    {
        try
        {
            EventWaitHandle ev;
            if (EventWaitHandle.TryOpenExisting(ClosingName, EventWaitHandleRights.Synchronize, out ev))
            {
                bool set = ev.WaitOne(0);
                ev.Close();
                return set;
            }
        }
        catch { }
        return false;
    }

    static void MakeClosingEvent()
    {
        try
        {
            bool created;
            EventWaitHandleSecurity sec = new EventWaitHandleSecurity();
            sec.AddAccessRule(new EventWaitHandleAccessRule(new SecurityIdentifier(WellKnownSidType.WorldSid, null),
                              EventWaitHandleRights.FullControl, AccessControlType.Allow));
            closingEvent = new EventWaitHandle(false, EventResetMode.ManualReset, ClosingName, out created, sec);
        }
        catch (Exception ex) { Logger.L("could not create the closing event: " + ex.Message); }
    }

    public static void SignalClosing()
    {
        try { if (closingEvent != null) closingEvent.Set(); } catch { }
    }

    // Find the first instance's window: same exe, same Windows session.
    static bool FocusExisting()
    {
        Process me = Process.GetCurrentProcess();
        string name = Path.GetFileNameWithoutExtension(ExePath);
        for (int attempt = 0; attempt < 12; attempt++)
        {
            foreach (Process p in Process.GetProcessesByName(name))
            {
                try
                {
                    if (p.Id == me.Id) continue;
                    if (p.SessionId != me.SessionId) continue;
                    string path = p.MainModule.FileName;
                    if (!string.Equals(path, ExePath, StringComparison.OrdinalIgnoreCase)) continue;
                    p.Refresh();
                    IntPtr h = p.MainWindowHandle;
                    if (h == IntPtr.Zero) continue;
                    if (Test)
                    {
                        Logger.L("second start: LDGR is already open (pid " + p.Id + "); would bring its window to the front");
                    }
                    else
                    {
                        if (Native.IsIconic(h)) Native.ShowWindow(h, Native.SW_RESTORE);
                        Native.SetForegroundWindow(h);
                        Logger.L("second start: brought the open LDGR (pid " + p.Id + ") to the front");
                    }
                    return true;
                }
                catch { }
                finally { p.Dispose(); }
            }
            Thread.Sleep(250);
        }
        return false;
    }

    public static int Run(string[] args)
    {
        Test = Environment.GetEnvironmentVariable("LDGR_TEST_NOACTIVATE") == "1";
        ExePath = Process.GetCurrentProcess().MainModule.FileName;
        Home = Path.GetDirectoryName(ExePath);
        hash = HashOf(Home);

        bool console = false, install = false;
        string updateZip = null;
        for (int i = 0; i < args.Length; i++)
        {
            string a = args[i];
            if (a == "--debug") Debug = true;
            else if (a == "--console") console = true;
            else if (a == "--install") install = true;
            else if (a == "--update") { updateZip = (i + 1 < args.Length) ? args[++i] : ""; }
        }

        Logger.Init(Home, false);
        if (Debug)
        {
            try { Native.AllocConsole(); } catch { }
            Logger.Init(Home, true);
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += delegate(object s, ThreadExceptionEventArgs e)
        {
            Logger.L("unexpected error: " + Flat(e.Exception.ToString()));
        };
        AppDomain.CurrentDomain.UnhandledException += delegate(object s, UnhandledExceptionEventArgs e)
        {
            Logger.L("unexpected error: " + Flat(Convert.ToString(e.ExceptionObject)));
        };

        string mode = install ? "install" : updateZip != null ? "update" : console ? "console" : "window";
        Logger.L("LDGR.exe started (mode " + mode + (Debug ? ", debug" : "") + ") from " + Home);

        if (install) return Install();

        // One instance per computer; --console and --update take the same mutex.
        Got g = TryGetMutex(0);
        if (g != Got.Yes && g == Got.Held && ClosingEventSet())
        {
            Logger.L("the first instance is still closing; waiting up to 25 s");
            if (WaitMutex(25000)) g = Got.Yes;
        }
        if (g != Got.Yes)
        {
            if (mode == "window")
            {
                if (FocusExisting()) return 0;
                Logger.L("the mutex is held but no LDGR window was found in this session");
                Msg(null, "LDGR is already open under another Windows account on this computer. Ask the person using it to close LDGR or sign out.",
                    MessageBoxButtons.OK, MessageBoxIcon.Information, "exit");
                return 2;
            }
            Msg(null, "Close LDGR first.", MessageBoxButtons.OK, MessageBoxIcon.Information, "exit");
            return mode == "update" ? 3 : 1;
        }

        int code;
        try
        {
            if (mode == "update") code = Update(updateZip);
            else if (mode == "console") code = RunConsole();
            else code = RunWindow();
        }
        finally { ReleaseMutex(); }
        Logger.L("LDGR.exe exits with code " + code);
        return code;
    }

    static int RunWindow()
    {
        MakeClosingEvent();
        AppForm f = new AppForm();
        Application.Run(f);
        return ExitCode;
    }

    static int RunConsole()
    {
        try
        {
            ProcessStartInfo psi = JuliaInfo(true, false);
            Logger.L("starting Julia console: " + psi.FileName + " " + psi.Arguments);
            Process p = Process.Start(psi);
            Native.AddToJob(p);
            p.WaitForExit();
            Logger.L("Julia console exited with code " + p.ExitCode);
            return p.ExitCode;
        }
        catch (Exception ex)
        {
            Logger.L("could not start Julia: " + Flat(ex.Message));
            Msg(null, "LDGR could not start. Please contact the technician.\n" + Logger.PathToday(),
                MessageBoxButtons.OK, MessageBoxIcon.Error, "exit");
            return 1;
        }
    }

    // ----- --install -----
    static int Install()
    {
        try
        {
            Type t = Type.GetTypeFromProgID("WScript.Shell");
            if (t == null) throw new InvalidOperationException("WScript.Shell is not available");
            object sh = Activator.CreateInstance(t);
            string[] places = new string[] {
                Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                Environment.GetFolderPath(Environment.SpecialFolder.Programs) };
            foreach (string place in places)
            {
                string path = Path.Combine(place, "LDGR.lnk");
                object lnk = t.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, sh, new object[] { path });
                Type lt = lnk.GetType();
                lt.InvokeMember("TargetPath", BindingFlags.SetProperty, null, lnk, new object[] { ExePath });
                lt.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, lnk, new object[] { Home });
                lt.InvokeMember("IconLocation", BindingFlags.SetProperty, null, lnk, new object[] { ExePath + ",0" });
                lt.InvokeMember("Description", BindingFlags.SetProperty, null, lnk, new object[] { "LDGR" });
                lt.InvokeMember("Save", BindingFlags.InvokeMethod, null, lnk, null);
                Marshal.FinalReleaseComObject(lnk);
                Logger.L("created shortcut " + path);
            }
            Marshal.FinalReleaseComObject(sh);
            Msg(null, "LDGR shortcuts were created on the Desktop and in the Start Menu.",
                MessageBoxButtons.OK, MessageBoxIcon.Information, "exit");
            return 0;
        }
        catch (Exception ex)
        {
            Logger.L("--install failed: " + Flat(ex.Message));
            Msg(null, "The shortcuts could not be created.\n" + ex.Message,
                MessageBoxButtons.OK, MessageBoxIcon.Error, "exit");
            return 1;
        }
    }

    // ----- --update <zip> -----
    static void CopyEntry(ZipArchiveEntry e, string dest)
    {
        using (Stream s = e.Open())
        using (FileStream o = new FileStream(dest, FileMode.Create, FileAccess.Write))
        {
            byte[] buf = new byte[81920];
            int n;
            while ((n = s.Read(buf, 0, buf.Length)) > 0) o.Write(buf, 0, n);
        }
    }

    static bool SameBytes(string a, string b)
    {
        try
        {
            byte[] x = File.ReadAllBytes(a), y = File.ReadAllBytes(b);
            if (x.Length != y.Length) return false;
            for (int i = 0; i < x.Length; i++) if (x[i] != y[i]) return false;
            return true;
        }
        catch { return false; }
    }

    static int Update(string zip)
    {
        string runtime = Path.Combine(Home, "runtime");
        string dll = Path.Combine(runtime, "ldgr.dll");
        string ver = Path.Combine(runtime, "VERSION.txt");
        string tmp = Path.Combine(Home, "update-temp-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        string backup = null;
        bool replacing = false;
        try
        {
            if (string.IsNullOrEmpty(zip) || !File.Exists(zip))
                throw new InvalidOperationException("The update file was not found: " + zip);
            Directory.CreateDirectory(tmp);
            string newDll = null, newVer = null;
            using (ZipArchive za = ZipFile.OpenRead(zip))
            {
                foreach (ZipArchiveEntry e in za.Entries)
                {
                    string leaf = e.Name;
                    if (string.Equals(leaf, "ldgr.dll", StringComparison.OrdinalIgnoreCase) && newDll == null)
                    { newDll = Path.Combine(tmp, "ldgr.dll"); CopyEntry(e, newDll); }
                    else if (string.Equals(leaf, "VERSION.txt", StringComparison.OrdinalIgnoreCase) && newVer == null)
                    { newVer = Path.Combine(tmp, "VERSION.txt"); CopyEntry(e, newVer); }
                }
            }
            if (newDll == null || new FileInfo(newDll).Length == 0)
                throw new InvalidOperationException("The update file does not contain ldgr.dll.");
            if (newVer == null)
                throw new InvalidOperationException("The update file does not contain VERSION.txt.");

            backup = Path.Combine(Home, "backups", DateTime.Now.ToString("yyyy-MM-dd HHmm"));
            if (Directory.Exists(backup)) backup = backup + DateTime.Now.ToString("ss");
            Directory.CreateDirectory(backup);
            if (File.Exists(dll)) File.Copy(dll, Path.Combine(backup, "ldgr.dll"), true);
            if (File.Exists(ver)) File.Copy(ver, Path.Combine(backup, "VERSION.txt"), true);
            Logger.L("update: previous files copied to " + backup);

            replacing = true;
            File.Copy(newDll, dll, true);
            File.Copy(newVer, ver, true);
            replacing = false;

            string v = File.ReadAllText(ver).Trim();
            int nl = v.IndexOfAny(new char[] { '\r', '\n' });
            if (nl > 0) v = v.Substring(0, nl);
            Logger.L("update: installed " + v);
            Msg(null, "LDGR was updated to " + v + ".", MessageBoxButtons.OK, MessageBoxIcon.Information, "exit");
            return 0;
        }
        catch (Exception ex)
        {
            Logger.L("update failed: " + Flat(ex.Message));
            string extra = "";
            if (replacing && backup != null)
            {
                // Only a file that was actually replaced needs putting back; each is tried on its own.
                string bd = Path.Combine(backup, "ldgr.dll");
                string problem = null;
                if (File.Exists(bd) && !(File.Exists(dll) && SameBytes(bd, dll)))
                {
                    try { File.Copy(bd, dll, true); Logger.L("update: ldgr.dll put back"); }
                    catch (Exception ex2) { problem = ex2.Message; Logger.L("update: restoring ldgr.dll failed: " + Flat(ex2.Message)); }
                }
                string bv = Path.Combine(backup, "VERSION.txt");
                if (File.Exists(bv) && !(File.Exists(ver) && SameBytes(bv, ver)))
                {
                    try { File.Copy(bv, ver, true); }
                    catch (Exception ex3) { if (problem == null) problem = ex3.Message; Logger.L("update: restoring VERSION.txt failed: " + Flat(ex3.Message)); }
                }
                extra = problem == null ? "\nThe previous version was put back." : "\nThe previous version could not be put back: " + problem;
                if (problem == null) Logger.L("update: the previous files were put back");
            }
            Msg(null, "The update failed.\n" + ex.Message + extra, MessageBoxButtons.OK, MessageBoxIcon.Error, "exit");
            return 3;
        }
        finally
        {
            try { if (Directory.Exists(tmp)) Directory.Delete(tmp, true); } catch { }
        }
    }
}

// ---------------------------------------------------------------------------------------
// The window
// ---------------------------------------------------------------------------------------
sealed class AppForm : Form
{
    static readonly Color PageColour = Color.FromArgb(0xFA, 0xF9, 0xF6);

    Splash splash = new Splash();
    FloatingBanner banner;
    Wv wv;
    Process julia;
    volatile bool juliaDone;
    bool sawReady, closing, allowClose, terminal, stdinClosed, shuttingDown, pageShown, revealed, begun;
    string failReason;
    DateTime startedAt;
    System.Windows.Forms.Timer stillTimer = new System.Windows.Forms.Timer();
    System.Windows.Forms.Timer longTimer = new System.Windows.Forms.Timer();
    System.Windows.Forms.Timer closeTimer = new System.Windows.Forms.Timer();
    DateTime closeStarted;

    public AppForm()
    {
        Text = "LDGR";
        BackColor = PageColour;
        try { Icon = Icon.ExtractAssociatedIcon(Launcher.ExePath); } catch { }
        // What the window shows when it appears before the form: a sentence under the banner, or
        // (if the floating banner could not be shown) the banner alone.
        splash.Dock = DockStyle.Fill;
        Controls.Add(splash);
        if (Launcher.Test) { WindowState = FormWindowState.Minimized; }
        else { WindowState = FormWindowState.Maximized; }

        int secs = 0;
        try { int.TryParse(Environment.GetEnvironmentVariable("LDGR_TEST_READY_TIMEOUT_S"), out secs); } catch { }
        stillTimer.Interval = secs > 0 ? Math.Max(200, secs * 500) : 60000;
        longTimer.Interval = secs > 0 ? secs * 1000 : 180000;
        stillTimer.Tick += delegate
        {
            stillTimer.Stop();
            if (!sawReady && !terminal) ShowStatus("Still starting. Please wait.", true);
        };
        longTimer.Tick += delegate
        {
            longTimer.Stop();
            if (!pageShown && !terminal && !closing)
            {
                string m = "LDGR is taking too long to start. Close this window and open LDGR again. If it happens again, contact the technician.";
                Logger.L(m);
                ShowStatus(m, true);
            }
        };
        closeTimer.Interval = 100;
        closeTimer.Tick += OnCloseTick;
    }

    // While LDGR starts, the window stays hidden and the banner floats on the desktop (owner,
    // 2026-10-09). The window appears, maximised, when the form has loaded, or earlier when a
    // sentence has to show (still starting, could not start, ...); the banner then closes.
    protected override void SetVisibleCore(bool value)
    {
        if (value && !revealed)
        {
            if (!IsHandleCreated) CreateHandle();
            if (!begun) { begun = true; BeginInvoke(new Action(BeginStart)); }
            base.SetVisibleCore(false);
            return;
        }
        base.SetVisibleCore(value);
    }

    void BeginStart()
    {
        BeginInvoke(new Action(StartJulia)); // first, so nothing about the banner can hold Julia up
        try
        {
            banner = new FloatingBanner(this);
            if (!banner.Open()) { banner.Dispose(); banner = null; }
        }
        catch (Exception ex)
        {
            Logger.L("the start-up banner could not be shown: " + Launcher.Flat(ex.Message));
            try { if (banner != null) banner.Dispose(); } catch { }
            banner = null;
        }
        if (banner == null) Reveal("no start-up banner"); // the window shows the start itself
    }

    void Reveal(string why)
    {
        if (revealed) return;
        revealed = true;
        Logger.L("window shown (" + why + ")");
        Visible = true;
        if (!Launcher.Test) { try { Activate(); } catch { } }
        CloseBanner("the window took over");
    }

    void CloseBanner(string why)
    {
        if (banner == null) return;
        FloatingBanner b = banner;
        banner = null;
        try { b.CloseQuietly(why); } catch { }
    }

    // The floating banner was closed by staff (taskbar or Alt+F4) while LDGR was starting.
    public void BannerClosedByUser()
    {
        banner = null;
        Logger.L("the start-up banner was closed; closing LDGR");
        BeginInvoke(new Action(Close));
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        CloseBanner("LDGR closed");
        base.OnFormClosed(e);
    }

    protected override bool ShowWithoutActivation { get { return Launcher.Test; } }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            if (Launcher.Test) cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE, tests only
            return cp;
        }
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == 0x0011) // WM_QUERYENDSESSION: Windows is shutting down or the user is signing out
        {
            Logger.L("Windows is ending the session; telling Julia to stop");
            shuttingDown = true;
            allowClose = true;
            if (sawReady) CloseStdin();
        }
        base.WndProc(ref m);
        if (m.Msg == 0x02E0) splash.Invalidate(); // WM_DPICHANGED: the window moved to a screen with other scaling
    }

    public void LogL(string s) { Logger.L(s); }

    public bool Ask(string text, bool cancelable)
    {
        DialogResult r = Launcher.Msg(this, text,
            cancelable ? MessageBoxButtons.OKCancel : MessageBoxButtons.OK,
            cancelable ? MessageBoxIcon.Question : MessageBoxIcon.Information,
            cancelable ? "OK accepts the page's dialog (confirm returns true)" : "OK closes the page's alert");
        return r == DialogResult.OK;
    }

    // The one way to put a sentence on the window: under the banner, in place of the page.
    // quiet: the slow states (14 px, soft grey); otherwise a failure (15 px, ink).
    void ShowStatus(string text) { ShowStatus(text, false); }

    void ShowStatus(string text, bool quiet)
    {
        splash.ShowText(text, quiet);
        splash.Visible = true;
        if (wv != null) wv.Control.Visible = false;
        Reveal("a sentence to show");
    }

    void ShowClosing()
    {
        splash.ShowClosing();
        splash.Visible = true;
        if (wv != null) wv.Control.Visible = false;
    }

    // ----- starting Julia -----
    void StartJulia()
    {
        startedAt = DateTime.Now;
        stillTimer.Start();
        longTimer.Start();
        try
        {
            ProcessStartInfo psi = Launcher.JuliaInfo(false, true);
            Logger.L("starting Julia: " + psi.FileName + " " + psi.Arguments);
            Process p = Process.Start(psi);
            julia = p;
            bool inJob = Native.AddToJob(p);
            if (!inJob) Logger.L("warning: Julia could not be put in the job object");
            p.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { OnLine(e.Data); };
            p.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { OnLine(e.Data); };
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            Thread t = new Thread(delegate()
            {
                int code = -1;
                try { p.WaitForExit(); code = p.ExitCode; } catch { }
                juliaDone = true;
                try { BeginInvoke(new Action(delegate { OnJuliaExited(code); })); } catch { }
            });
            t.IsBackground = true;
            t.Start();
        }
        catch (Exception ex)
        {
            Logger.L("Julia could not be started: " + Launcher.Flat(ex.Message));
            juliaDone = true;
            ShowCouldNotStart();
        }
    }

    // Reader thread: never throws.
    void OnLine(string line)
    {
        if (line == null) return;
        try
        {
            Logger.Write(line);
            if (line.StartsWith("LDGR-READY "))
            {
                string url = line.Substring(11).Trim();
                BeginInvoke(new Action(delegate { OnReady(url); }));
            }
            else if (line.StartsWith("LDGR-FAIL"))
            {
                string reason = line.Length > 9 ? line.Substring(9).Trim() : "";
                BeginInvoke(new Action(delegate { OnFailLine(reason); }));
            }
        }
        catch { }
    }

    void OnFailLine(string reason)
    {
        failReason = reason;
        if (!sawReady) ShowCouldNotStart();
    }

    void OnReady(string url)
    {
        if (sawReady || terminal || closing) return;
        sawReady = true;
        stillTimer.Stop();
        Logger.L("READY " + url + " after " + (int)(DateTime.Now - startedAt).TotalSeconds + " s");
        wv = new Wv(this, Launcher.Debug);
        wv.Control.Visible = false;
        Controls.Add(wv.Control);
        wv.Start(url);
    }

    public void WvMissing(string detail)
    {
        Logger.L("WebView2 is missing or unusable: " + detail);
        terminal = true;
        Launcher.ExitCode = 1;
        ShowStatus("LDGR needs a Windows component that is missing on this computer (Microsoft Edge WebView2). Please contact the technician.");
        KillJulia();
    }

    public void WvFailed(string detail)
    {
        Logger.L("the window could not show the form: " + detail);
        KillJulia();
        ShowCouldNotStart();
    }

    public void WvPageShown()
    {
        pageShown = true;
        longTimer.Stop();
        splash.Visible = false;
        wv.Control.Visible = true;
        wv.Control.BringToFront();
        Reveal("the form has loaded");
        try { wv.Control.Focus(); } catch { }
        Logger.L("navigation succeeded; the form is showing");
    }

    void ShowCouldNotStart()
    {
        if (terminal) return;
        terminal = true;
        Launcher.ExitCode = 1;
        stillTimer.Stop();
        longTimer.Stop();
        string path = Logger.PathToday();
        Logger.L("LDGR could not start. Please contact the technician. Log: " + path
                 + (failReason != null ? " (LDGR-FAIL " + failReason + ")" : ""));
        ShowStatus("LDGR could not start. Please contact the technician.\n" + path);
    }

    // ----- Julia stopped -----
    void OnJuliaExited(int code)
    {
        Logger.L("Julia exited with code " + code);
        if (shuttingDown) { allowClose = true; return; }
        if (closing) { FinishClose(); return; }
        if (terminal) return;
        if (!sawReady)
        {
            ShowCouldNotStart();
            return;
        }
        terminal = true;
        Launcher.ExitCode = 1;
        Reveal("Julia stopped"); // the box needs its window behind it, even before the form loaded
        Launcher.Msg(this, "LDGR has stopped. Unsaved figures will need to be re-entered. Press OK, then open LDGR again.",
                     MessageBoxButtons.OK, MessageBoxIcon.Warning, "exit LDGR");
        allowClose = true;
        Close();
    }

    // ----- closing -----
    void CloseStdin()
    {
        if (stdinClosed) return;
        stdinClosed = true;
        try { if (julia != null) julia.StandardInput.Close(); }
        catch (Exception ex) { Logger.L("closing Julia's input failed: " + Launcher.Flat(ex.Message)); }
        Logger.L("Julia's standard input closed");
    }

    void KillJulia()
    {
        try { if (julia != null && !julia.HasExited) { julia.Kill(); Logger.L("Julia killed"); } } catch { }
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        base.OnFormClosing(e);
        if (allowClose || e.Cancel) return;
        if (e.CloseReason == CloseReason.WindowsShutDown)
        {
            Logger.L("Windows is shutting down");
            shuttingDown = true;
            if (julia != null && !juliaDone)
            {
                CloseStdin();
                try { julia.WaitForExit(3000); } catch { }
                KillJulia();
            }
            return;
        }
        if (julia == null || juliaDone || terminal)
        {
            KillJulia();
            return;
        }
        if (!sawReady)
        {
            Logger.L("closed before Julia was ready; killing it");
            KillJulia();
            return;
        }
        e.Cancel = true;
        if (!closing) BeginClose();
    }

    void BeginClose()
    {
        closing = true;
        closeStarted = DateTime.Now;
        Logger.L("closing: asking Julia to stop");
        ShowClosing();
        Launcher.SignalClosing();
        CloseStdin();
        closeTimer.Start();
    }

    void OnCloseTick(object s, EventArgs e)
    {
        if (juliaDone) { FinishClose(); return; }
        if ((DateTime.Now - closeStarted).TotalSeconds >= 20)
        {
            Logger.L("Julia did not stop within 20 s; killing it");
            KillJulia();
            if ((DateTime.Now - closeStarted).TotalSeconds >= 22) FinishClose();
        }
    }

    bool finishing;
    void FinishClose()
    {
        if (finishing) return;
        finishing = true;
        closeTimer.Stop();
        allowClose = true;
        Close();
    }
}

// ---------------------------------------------------------------------------------------
// The brand pictures (packaging\brand\README.md), embedded in LDGR.exe by build.jl as
// startup-banner@<k>.png and closing@<k>.png, k = 1x, 1.25x, 1.5x, 2x. Sizes are CSS px
// at 96 dpi, multiplied by s = dpi / 96.
// ---------------------------------------------------------------------------------------
static class Art
{
    // The scaling each file was drawn for (as dpi), and its name's suffix.
    static readonly int[] FileDpi = { 96, 120, 144, 192 };
    static readonly string[] FileKey = { "1x", "1.25x", "1.5x", "2x" };

    // The paper patch's centre (and the closing image's) is at 42 % of the height. The banner has
    // 24 px of transparent padding round a patch 237.74 px high, so its top is 24 + 118.87 px above.
    public const double CentreAt = 0.42;
    public const double BannerAbove = 24 + 118.87;

    static Dictionary<string, Bitmap> cache = new Dictionary<string, Bitmap>();
    static float screenDpi;

    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr hwnd);

    // A window's dpi (Windows 10 1607 and later), else the screen's. Control.DeviceDpi is not used:
    // it needs .NET 4.7, and the launcher needs only 4.6.2.
    public static int WindowDpi(IntPtr h)
    {
        try
        {
            uint d = GetDpiForWindow(h);
            if (d > 0) return (int)d;
        }
        catch { }
        return (int)Math.Round(ScreenDpi());
    }

    public static float ScreenDpi()
    {
        if (screenDpi <= 0)
        {
            try { using (Graphics sg = Graphics.FromHwnd(IntPtr.Zero)) screenDpi = sg.DpiY; } catch { }
            if (screenDpi <= 0) screenDpi = 96;
        }
        return screenDpi;
    }

    // The file made for this scaling, else the next larger one drawn smaller. Above 200 % there is
    // no larger file, so the 2x one is drawn larger.
    static int Pick(int dpi)
    {
        for (int i = 0; i < FileDpi.Length; i++) if (FileDpi[i] >= dpi) return i;
        return FileDpi.Length - 1;
    }

    // null when the picture is missing; the caller then shows text.
    public static Bitmap Picture(string baseName, int dpi)
    {
        string name = baseName + "@" + FileKey[Pick(dpi)] + ".png";
        Bitmap b;
        if (cache.TryGetValue(name, out b)) return b;
        string why = "is missing from LDGR.exe";
        try
        {
            Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(name);
            if (s != null)
            {
                MemoryStream ms = new MemoryStream();
                using (s) s.CopyTo(ms);
                ms.Position = 0;
                b = new Bitmap(ms); // GDI+ reads ms for the bitmap's whole life, so it is never closed
            }
        }
        catch (Exception ex) { b = null; why = "could not be read (" + Launcher.Flat(ex.Message) + ")"; }
        string screen = baseName == "closing" ? "closing screen: " : "start screen: ";
        if (b != null) Logger.L(screen + name + " for " + dpi + " dpi");
        else Logger.L(screen + name + " " + why + "; showing text instead");
        cache[name] = b;
        return b;
    }

    // The size to draw a picture at: the file's own for the scaling it was made for, else scaled.
    public static Size SizeFor(Bitmap b, int dpi)
    {
        int made = FileDpi[Pick(dpi)];
        if (made == dpi) return b.Size;
        return new Size((int)Math.Round(b.Width * (double)dpi / made), (int)Math.Round(b.Height * (double)dpi / made));
    }

    public static void Draw(Graphics g, Bitmap b, Rectangle r)
    {
        if (r.Width == b.Width && r.Height == b.Height)
        {
            // Pixel for pixel.
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = PixelOffsetMode.Half;
            g.DrawImage(b, r, 0, 0, b.Width, b.Height, GraphicsUnit.Pixel);
        }
        else
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            using (ImageAttributes ia = new ImageAttributes())
            {
                ia.SetWrapMode(WrapMode.TileFlipXY); // no faint frame round the edges
                g.DrawImage(b, r, 0, 0, b.Width, b.Height, GraphicsUnit.Pixel, ia);
            }
        }
    }
}

// ---------------------------------------------------------------------------------------
// The start-up banner (owner, 2026-10-09): a borderless window holding only the banner, floating
// on the desktop while Julia starts. Per-pixel alpha (UpdateLayeredWindow), so the paper's
// rounded corners and soft shadow sit on whatever is behind it. It has a taskbar button, is not
// kept on top, and closes when the LDGR window appears. Closing it closes LDGR.
// ---------------------------------------------------------------------------------------
sealed class FloatingBanner : Form
{
    AppForm app;
    bool quietly;

    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("user32.dll", SetLastError = true)]
    static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr dst, ref Pt at, ref Sz size, IntPtr src, ref Pt from,
                                           int key, ref Blend blend, int flags);
    [StructLayout(LayoutKind.Sequential)] struct Pt { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct Sz { public int W, H; }
    [StructLayout(LayoutKind.Sequential, Pack = 1)] struct Blend { public byte Op, Flags, Alpha, Format; }

    public FloatingBanner(AppForm app)
    {
        this.app = app;
        Text = "LDGR";
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = true;
        StartPosition = FormStartPosition.Manual;
        try { Icon = Icon.ExtractAssociatedIcon(Launcher.ExePath); } catch { }
    }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x00080000;                    // WS_EX_LAYERED
            if (Launcher.Test) cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE, tests only
            return cp;
        }
    }

    protected override bool ShowWithoutActivation { get { return Launcher.Test; } }

    // Shows the banner centred on the main screen's desktop (above the taskbar). Its transparent
    // padding is even all round, so the paper patch is centred too. Returns false, showing nothing,
    // when there is no picture.
    public bool Open()
    {
        Rectangle wa = Screen.PrimaryScreen.WorkingArea;
        Bounds = new Rectangle(wa.X + wa.Width / 2, wa.Y + wa.Height / 2, 1, 1);
        int dpi = Art.WindowDpi(Handle); // the handle is made here, on the main screen, to learn its dpi
        Bitmap b = Art.Picture("startup-banner", dpi);
        if (b == null) return false;
        Size size = Art.SizeFor(b, dpi);
        int x = wa.X + (int)Math.Floor((wa.Width - size.Width) / 2.0);
        int y = wa.Y + (int)Math.Floor((wa.Height - size.Height) / 2.0);
        using (Bitmap frame = new Bitmap(size.Width, size.Height, PixelFormat.Format32bppArgb))
        {
            using (Graphics g = Graphics.FromImage(frame))
            {
                g.CompositingMode = CompositingMode.SourceCopy;
                Art.Draw(g, b, new Rectangle(Point.Empty, size));
            }
            Bounds = new Rectangle(x, y, size.Width, size.Height);
            Present(frame, x, y);
        }
        Show();
        Logger.L("start-up banner shown at " + x + "," + y + " (" + size.Width + " x " + size.Height + ", " + dpi + " dpi)");
        return true;
    }

    void Present(Bitmap frame, int x, int y)
    {
        IntPtr screen = GetDC(IntPtr.Zero);
        IntPtr mem = CreateCompatibleDC(screen);
        IntPtr hb = IntPtr.Zero, old = IntPtr.Zero;
        try
        {
            hb = frame.GetHbitmap(Color.FromArgb(0)); // 32 bpp, premultiplied, as UpdateLayeredWindow needs
            old = SelectObject(mem, hb);
            Pt at = new Pt(); at.X = x; at.Y = y;
            Sz sz = new Sz(); sz.W = frame.Width; sz.H = frame.Height;
            Pt from = new Pt();
            Blend bl = new Blend(); bl.Op = 0; bl.Flags = 0; bl.Alpha = 255; bl.Format = 1; // AC_SRC_OVER, AC_SRC_ALPHA
            if (!UpdateLayeredWindow(Handle, screen, ref at, ref sz, mem, ref from, 0, ref bl, 2)) // ULW_ALPHA
                throw new InvalidOperationException("UpdateLayeredWindow failed (error " + Marshal.GetLastWin32Error() + ")");
        }
        finally
        {
            if (old != IntPtr.Zero) SelectObject(mem, old);
            if (hb != IntPtr.Zero) DeleteObject(hb);
            DeleteDC(mem);
            ReleaseDC(IntPtr.Zero, screen);
        }
    }

    public void CloseQuietly(string why)
    {
        quietly = true;
        Logger.L("start-up banner closed: " + why);
        if (Visible) Close();
        Dispose();
    }

    // Closed by staff (taskbar, Alt+F4) or Task Manager while LDGR starts: that closes LDGR.
    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        base.OnFormClosing(e);
        if (quietly || e.Cancel || e.CloseReason == CloseReason.WindowsShutDown) return;
        quietly = true;
        app.BannerClosedByUser();
    }
}

// ---------------------------------------------------------------------------------------
// The window's own start and closing screens: the closing image, and the sentence under the
// banner when LDGR is slow to start or cannot start (the window then appears in place of the
// floating banner). If a picture is missing, or the window is too small, the old centred text
// is shown instead, so the window is never blank.
// ---------------------------------------------------------------------------------------
sealed class Splash : Control
{
    static readonly Color PageColour = Color.FromArgb(0xFA, 0xF9, 0xF6);
    static readonly Color Accent = Color.FromArgb(0x1F, 0x6F, 0x5C);
    static readonly Color Ink = Color.FromArgb(0x1C, 0x25, 0x21);
    static readonly Color Soft = Color.FromArgb(0x5B, 0x66, 0x60);

    // Status lines: the first baseline 58.25 px below the patch (y 540 in an 864-high window),
    // each further line 24 px lower, wrapped at 640 px.
    const double FirstBaseline = 118.87 + 58.25;
    const double LinePitch = 24;
    const double WrapWidth = 640;

    bool closingScreen;
    string text;
    bool quiet;

    public Splash()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                 | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
        SetStyle(ControlStyles.Selectable, false);
        TabStop = false;
        BackColor = PageColour;
        AccessibleRole = AccessibleRole.StaticText;
        AccessibleName = "LDGR";
    }

    // A sentence under the banner; text after a line break (the log's path) is the smaller grey line.
    public void ShowText(string t, bool q)
    {
        closingScreen = false;
        text = t;
        quiet = q;
        AccessibleName = t;
        Invalidate();
    }

    public void ShowClosing()
    {
        closingScreen = true;
        text = null;
        AccessibleName = "Closing LDGR\u2026";
        Art.Picture("closing", Dpi());
        Invalidate();
    }

    public int Dpi() { return IsHandleCreated ? Art.WindowDpi(Handle) : (int)Math.Round(Art.ScreenDpi()); }

    bool paintFailed;

    // An exception here would make WinForms draw a red cross for good: log it once and fall back
    // to the plain text screen.
    protected override void OnPaint(PaintEventArgs e)
    {
        try { Render(e.Graphics, ClientSize, Dpi()); }
        catch (Exception ex)
        {
            if (!paintFailed) Logger.L("the window's start or closing screen could not be drawn: " + Launcher.Flat(ex.Message));
            paintFailed = true;
            try { e.Graphics.Clear(PageColour); OldText(e.Graphics, ClientSize, Dpi() / 96.0); } catch { }
        }
    }

    // The whole screen for a client area of the given size at the given dpi.
    public void Render(Graphics g, Size client, int dpi)
    {
        g.Clear(PageColour);
        if (client.Width <= 0 || client.Height <= 0) return;
        double s = dpi / 96.0;
        Bitmap b = Art.Picture(closingScreen ? "closing" : "startup-banner", dpi);
        if (b == null) { OldText(g, client, s); return; }

        Size size = Art.SizeFor(b, dpi);
        int w = size.Width, h = size.Height;
        double centre = Art.CentreAt * client.Height;
        int x = (int)Math.Floor((client.Width - w) / 2.0);
        int y = (int)Math.Round(closingScreen ? centre - h / 2.0 : centre - Art.BannerAbove * s);
        List<Line> lines = null;
        if (!closingScreen && !string.IsNullOrEmpty(text))
        {
            lines = StatusLines(g, client, s);
            // A window too small for the banner and the sentence (restored, not maximised) shows the
            // sentence alone, as before the banner, so it can always be read.
            double last = centre + (FirstBaseline + LinePitch * (lines.Count - 1)) * s;
            if (w > client.Width || y < 0 || last + 8 * s > client.Height) { OldText(g, client, s); return; }
        }
        Art.Draw(g, b, new Rectangle(x, y, w, h));
        if (lines == null) return;

        // The status lines, centred, the first baseline FirstBaseline below the patch centre.
        double baseline = centre + FirstBaseline * s;
        foreach (Line l in lines)
        {
            using (Font f = PixelFont(l.Px))
            {
                FontFamily ff = f.FontFamily;
                double ascent = Whole(l.Px) * (double)ff.GetCellAscent(FontStyle.Regular) / ff.GetEmHeight(FontStyle.Regular);
                int top = (int)Math.Round(baseline - ascent);
                TextRenderer.DrawText(g, l.Text, f, new Rectangle(0, top, client.Width, (int)Math.Ceiling(l.Px * 2)),
                                      l.Colour, OneLine | TextFormatFlags.HorizontalCenter | TextFormatFlags.Top);
            }
            baseline += LinePitch * s;
        }
    }

    const TextFormatFlags OneLine = TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine;

    sealed class Line { public string Text; public double Px; public Color Colour; }

    // The status sentence as lines. The first part is 15 px ink (a failure) or 14 px soft grey (still
    // starting); a part after a line break (the log's path) is 13 px soft grey. Wrapped at 640 px,
    // or narrower in a narrower window.
    List<Line> StatusLines(Graphics g, Size client, double s)
    {
        List<Line> lines = new List<Line>();
        string[] parts = text.Replace("\r\n", "\n").Split('\n');
        int wrap = (int)Math.Round(Math.Min(WrapWidth * s, client.Width - 32 * s));
        for (int p = 0; p < parts.Length; p++)
        {
            double px = (p > 0 ? 13 : quiet ? 14 : 15) * s;
            Color colour = p == 0 && !quiet ? Ink : Soft;
            using (Font f = PixelFont(px))
            {
                foreach (string t in Wrap(g, parts[p], f, wrap))
                {
                    Line l = new Line();
                    l.Text = t;
                    l.Px = px;
                    l.Colour = colour;
                    lines.Add(l);
                }
            }
        }
        return lines;
    }

    static List<string> Wrap(Graphics g, string s, Font f, int width)
    {
        List<string> lines = new List<string>();
        string line = "";
        foreach (string word in s.Split(' '))
        {
            string longer = line.Length == 0 ? word : line + " " + word;
            if (line.Length > 0 && TextRenderer.MeasureText(g, longer, f, new Size(int.MaxValue, int.MaxValue), OneLine).Width > width)
            {
                lines.Add(line);
                line = word;
            }
            else line = longer;
        }
        lines.Add(line);
        return lines;
    }

    // Without the pictures: the old screen, the sentence centred in Segoe UI 16 pt in the accent green.
    void OldText(Graphics g, Size client, double s)
    {
        string t = !string.IsNullOrEmpty(text) ? text : closingScreen ? "Closing LDGR\u2026" : "Starting LDGR\u2026";
        using (Font f = PixelFont(16 * 96 / 72.0 * s))
            TextRenderer.DrawText(g, t, f, new Rectangle(Point.Empty, client), Accent,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
    }

    static int Whole(double px) { return (int)Math.Round(px, MidpointRounding.AwayFromZero); }

    // Segoe UI exactly Whole(px) pixels high. TextRenderer turns a size in points into pixels with
    // Math.Ceiling at the screen's dpi, so it is asked for half a pixel less than the size wanted.
    Font PixelFont(double px)
    {
        return new Font("Segoe UI", (float)((Whole(px) - 0.5) * 72.0 / Art.ScreenDpi()), FontStyle.Regular, GraphicsUnit.Point);
    }
}

// ---------------------------------------------------------------------------------------
// Everything that names a WebView2 type lives here.
// ---------------------------------------------------------------------------------------
sealed class Wv
{
    WebView2 view;
    AppForm owner;
    bool debug;
    bool shown;
    int tries;
    string origin;

    public Control Control { get { return view; } }

    public Wv(AppForm owner, bool debug)
    {
        this.owner = owner;
        this.debug = debug;
        view = new WebView2();
        view.Dock = DockStyle.Fill;
        try { view.AllowExternalDrop = false; } catch { }
    }

    public async void Start(string readyUrl)
    {
        origin = readyUrl.Trim().TrimEnd('/');
        try
        {
            string loader = Path.Combine(Launcher.Home, "runtime", "webview2");
            CoreWebView2Environment.SetLoaderDllFolderPath(loader);
            string version = null;
            try { version = CoreWebView2Environment.GetAvailableBrowserVersionString(); }
            catch (Exception ex)
            {
                owner.WvMissing("GetAvailableBrowserVersionString threw " + ex.GetType().Name + ": " + ex.Message);
                return;
            }
            if (string.IsNullOrEmpty(version)) { owner.WvMissing("no WebView2 runtime is installed"); return; }
            owner.LogL("WebView2 runtime " + version);

            string local = Environment.GetEnvironmentVariable("LOCALAPPDATA");
            if (string.IsNullOrEmpty(local)) local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string userData = Path.Combine(Path.Combine(local, "LDGR"), "WebView2");
            CoreWebView2Environment env = await CoreWebView2Environment.CreateAsync(null, userData, null);
            await view.EnsureCoreWebView2Async(env);

            CoreWebView2 c = view.CoreWebView2;
            CoreWebView2Settings st = c.Settings;
            st.AreBrowserAcceleratorKeysEnabled = debug;
            st.AreDefaultContextMenusEnabled = debug;
            st.AreDevToolsEnabled = debug;
            st.IsZoomControlEnabled = false;
            st.IsStatusBarEnabled = false;
            st.IsSwipeNavigationEnabled = false;
            st.IsGeneralAutofillEnabled = false;
            st.IsPasswordAutosaveEnabled = false;
            st.AreDefaultScriptDialogsEnabled = false;
            view.ZoomFactor = 1.0;

            c.NewWindowRequested += delegate(object o, CoreWebView2NewWindowRequestedEventArgs a)
            {
                owner.LogL("new window refused: " + a.Uri);
                a.Handled = true;
            };
            c.NavigationStarting += delegate(object o, CoreWebView2NavigationStartingEventArgs a)
            {
                if (!a.Uri.StartsWith(origin + "/", StringComparison.OrdinalIgnoreCase))
                {
                    owner.LogL("navigation away refused: " + a.Uri);
                    a.Cancel = true;
                }
            };
            c.ScriptDialogOpening += delegate(object o, CoreWebView2ScriptDialogOpeningEventArgs a)
            {
                CoreWebView2Deferral d = a.GetDeferral();
                string msg = a.Message;
                CoreWebView2ScriptDialogKind kind = a.Kind;
                view.BeginInvoke(new Action(delegate
                {
                    try
                    {
                        bool ok;
                        if (kind == CoreWebView2ScriptDialogKind.Alert) { owner.Ask(msg, false); ok = true; }
                        else if (kind == CoreWebView2ScriptDialogKind.Confirm) { ok = owner.Ask(msg, true); }
                        else if (kind == CoreWebView2ScriptDialogKind.Beforeunload) { ok = true; }
                        else { ok = false; }
                        if (ok) a.Accept();
                    }
                    catch (Exception ex) { owner.LogL("dialog failed: " + ex.Message); }
                    finally { try { d.Complete(); } catch { } }
                }));
            };
            c.ProcessFailed += delegate(object o, CoreWebView2ProcessFailedEventArgs a)
            {
                owner.LogL("WebView2 process failed: " + a.ProcessFailedKind + " (" + a.Reason + ")");
            };
            c.NavigationCompleted += delegate(object o, CoreWebView2NavigationCompletedEventArgs a)
            {
                if (a.IsSuccess)
                {
                    if (!shown) { shown = true; owner.WvPageShown(); }
                    return;
                }
                owner.LogL("navigation failed: " + a.WebErrorStatus);
                if (!shown && a.WebErrorStatus != CoreWebView2WebErrorStatus.OperationCanceled)
                {
                    tries++;
                    if (tries < 5) RetryLater();
                    else owner.WvFailed("the form could not be loaded from " + origin);
                }
            };
            c.Navigate(origin + "/");
        }
        catch (WebView2RuntimeNotFoundException ex) { owner.WvMissing(ex.GetType().Name + ": " + ex.Message); }
        catch (DllNotFoundException ex) { owner.WvMissing("WebView2Loader.dll: " + ex.Message); }
        catch (BadImageFormatException ex) { owner.WvMissing("WebView2Loader.dll: " + ex.Message); }
        catch (Exception ex) { owner.WvFailed(ex.GetType().Name + ": " + ex.Message); }
    }

    async void RetryLater()
    {
        try
        {
            await System.Threading.Tasks.Task.Delay(1000);
            if (!shown && view.CoreWebView2 != null) view.CoreWebView2.Navigate(origin + "/");
        }
        catch { }
    }
}
