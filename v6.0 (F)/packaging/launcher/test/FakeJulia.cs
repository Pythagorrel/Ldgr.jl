// FakeJulia: stands in for julia.exe when testing LDGR.exe. C# 5.
// Installed as <fakehome>\runtime\julia\bin\julia.exe. Behaviour comes from <fakehome>\fake-mode.txt:
//   normal | fail-before-ready | ldgr-fail | die-after-ready | never-ready | ignore-stdin
// Writes what it was given to <fakehome>\fake-run.txt (and page reports to <fakehome>\fake-page-reports.txt).
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

static class FakeJulia
{
    static string home;
    static StreamWriter outw;

    static void Out(string s) { outw.WriteLine(s); outw.Flush(); }

    static int Main(string[] args)
    {
        string exeDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
        home = Path.GetFullPath(Path.Combine(exeDir, "..\\..\\.."));
        outw = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false));
        outw.AutoFlush = true;
        StreamWriter errw = new StreamWriter(Console.OpenStandardError(), new UTF8Encoding(false));
        errw.AutoFlush = true;

        string mode = "normal";
        try { mode = File.ReadAllText(Path.Combine(home, "fake-mode.txt")).Trim(); } catch { }

        StringBuilder sb = new StringBuilder();
        sb.AppendLine("MODE=" + mode);
        sb.AppendLine("ARGC=" + args.Length);
        for (int i = 0; i < args.Length; i++) sb.AppendLine("ARG[" + i + "]=" + args[i]);
        sb.AppendLine("CWD=" + Directory.GetCurrentDirectory());
        string[] watch = { "JULIA_DEPOT_PATH", "LEDGER_ROOT", "LDGR_NOTIFY_CONFIG", "LDGR_NO_BROWSER",
                           "LDGR_NO_DIGEST", "LDGR_DIGEST_NOW", "LDGR_NO_WARMUP" };
        foreach (string w in watch) sb.AppendLine("ENV " + w + "=" + (Environment.GetEnvironmentVariable(w) ?? "<unset>"));
        List<string> others = new List<string>();
        foreach (System.Collections.DictionaryEntry de in Environment.GetEnvironmentVariables())
        {
            string k = (string)de.Key;
            string ku = k.ToUpperInvariant();
            if ((ku.StartsWith("JULIA_") && ku != "JULIA_DEPOT_PATH") || ku.StartsWith("SSL_CERT_") || ku.StartsWith("WEBVIEW2_"))
                others.Add(k);
        }
        sb.AppendLine("OTHER_SCRUBBED_VARS=" + string.Join(",", others.ToArray()));
        sb.AppendLine("PID=" + System.Diagnostics.Process.GetCurrentProcess().Id);
        File.WriteAllText(Path.Combine(home, "fake-run.txt"), sb.ToString(), new UTF8Encoding(false));

        bool consoleMode = Array.IndexOf(args, "-i") >= 0;
        if (consoleMode) { Out("fake console"); return 7; }

        Out("LDGR 6.0.0 (fake), Julia 1.10.12");
        Out("  Records folder : café — über");
        errw.WriteLine("  (a line on stderr)");

        if (mode == "fail-before-ready") { Thread.Sleep(1000); errw.WriteLine("fake: something broke"); return 3; }
        if (mode == "ldgr-fail") { Out("LDGR-FAIL test reason"); return 2; }
        if (mode == "never-ready") { Thread.Sleep(Timeout.Infinite); return 0; }

        string url = Serve();
        Out("LDGR-READY " + url);

        if (mode == "die-after-ready") { Thread.Sleep(2000); return 5; }
        if (mode == "ignore-stdin") { Thread.Sleep(Timeout.Infinite); return 0; }

        // normal: wait for stdin to reach EOF (the stop signal)
        try { Console.In.ReadToEnd(); } catch { }
        Out("  Closing...");
        Thread.Sleep(300);
        Out("  Stopped.");
        return 0;
    }

    static string Serve()
    {
        TcpListener l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int port = ((IPEndPoint)l.LocalEndpoint).Port;
        Thread t = new Thread(delegate()
        {
            while (true)
            {
                TcpClient c;
                try { c = l.AcceptTcpClient(); } catch { return; }
                ThreadPool.QueueUserWorkItem(delegate { Handle(c); });
            }
        });
        t.IsBackground = true;
        t.Start();
        return "http://127.0.0.1:" + port;
    }

    static string ReadLine(Stream s)
    {
        StringBuilder sb = new StringBuilder();
        int b;
        while ((b = s.ReadByte()) >= 0) { if (b == '\n') break; if (b != '\r') sb.Append((char)b); }
        return b < 0 && sb.Length == 0 ? null : sb.ToString();
    }

    static void Handle(TcpClient c)
    {
        try
        {
            using (c)
            {
                Stream s = c.GetStream();
                string req = ReadLine(s);
                if (req == null) return;
                int len = 0;
                string h;
                while ((h = ReadLine(s)) != null && h.Length > 0)
                    if (h.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase)) len = int.Parse(h.Substring(15).Trim());
                string body = "";
                if (len > 0)
                {
                    byte[] b = new byte[len]; int got = 0;
                    while (got < len) { int n = s.Read(b, got, len - got); if (n <= 0) break; got += n; }
                    body = Encoding.UTF8.GetString(b, 0, got);
                }
                string resp; string ctype = "text/html; charset=utf-8";
                if (req.StartsWith("POST /report"))
                {
                    lock (typeof(FakeJulia)) File.AppendAllText(Path.Combine(home, "fake-page-reports.txt"), body + "\r\n");
                    resp = "ok"; ctype = "text/plain";
                }
                else if (req.StartsWith("GET / ") || req.StartsWith("GET /?"))
                {
                    bool auto = File.Exists(Path.Combine(home, "fake-autoconfirm.txt"));
                    resp = Page.Replace("@AUTO@", auto ? "true" : "false");
                }
                else { resp = "not found"; }
                byte[] rb = Encoding.UTF8.GetBytes(resp);
                string head = "HTTP/1.1 " + (resp == "not found" ? "404 Not Found" : "200 OK") + "\r\nContent-Type: " + ctype
                    + "\r\nContent-Length: " + rb.Length + "\r\nConnection: close\r\n\r\n";
                byte[] hb = Encoding.ASCII.GetBytes(head);
                s.Write(hb, 0, hb.Length); s.Write(rb, 0, rb.Length); s.Flush();
            }
        }
        catch { }
    }

    const string Page = @"<!doctype html><html><head><meta charset=utf-8><title>Fake LDGR form</title></head><body>
<h3>Fake LDGR form</h3><button id=b onclick=""rep('confirm=' + confirm('Mark this day as an Off day?'))"">Off day</button>
<script>
function rep(x){ try{ fetch('/report',{method:'POST',body:x}); }catch(e){} }
window.addEventListener('load',function(){ rep('loaded');
  if (@AUTO@) setTimeout(function(){ rep('auto confirm=' + confirm('Mark this day as an Off day?')); }, 300); });
</script></body></html>";
}
