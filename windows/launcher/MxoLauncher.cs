// The Matrix Online launcher for Windows, rebuilt from the original 2005 launcher's own skin (read out of launcher.exe
// in the game folder - nothing is shipped). Sits next to MatrixPrivate.exe; settings in launcher.conf (SERVER=, WORLD=).
// usage: "MxO Launcher.exe" [--extract]
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace Retro
{
    public class MxoLauncher
    {
        static string Dir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\', '/');
        static string ArtDir = Path.Combine(Dir, "launcher-art");
        static Dictionary<string, string> Conf = Art.ReadConf(Path.Combine(Dir, "launcher.conf"));
        static string World = Art.Get(Conf, "WORLD", "Reality"), Server = Art.Get(Conf, "SERVER", "");
        const string Version = "1.2.0";        // this launcher's release; signed updates come from UPDATES= (GitHub releases)
        static string Repo = Art.Get(Conf, "UPDATES", "hsmasteryoda/matrix-online-launcher");

        static readonly Dictionary<string, int> Bmp = new Dictionary<string, int> {
            {"frame",186},{"splash",185},{"min",195},{"min_p",192},{"close",193},{"close_p",194},
            {"tab_patch",216},{"tab_select",215},{"tab_done",247},{"lbl_blank",254},{"lbl_done",248},{"row_on",224},
            {"bar_done",220},{"play",212},{"play_hi",246},{"play_pr",213},{"play_off",214},{"quit",231},{"quit_hi",232},
            {"acct",203},{"acct_hi",204},{"comm",206},{"comm_hi",207},{"supp",209},{"supp_hi",210} };
        static readonly Dictionary<string, int> Wav = new Dictionary<string, int> { {"splash",189},{"click",142},{"done",243} };
        static readonly Dictionary<string, int> Str = new Dictionary<string, int> {
            {"os",102},{"ssh",103},{"check",131},{"scan",132},{"uptodate",163},{"access",154},{"select",155},
            {"name",148},{"status",185},{"open",135},{"down",138} };

        public static void Extract()
        {
            var res = Art.PeResources(Path.Combine(Dir, "launcher.exe"));
            Directory.CreateDirectory(ArtDir);
            foreach (var kv in Bmp) using (var b = Art.PeBitmap(res, kv.Value)) Art.SavePng(b, Path.Combine(ArtDir, kv.Key + ".png"));
            foreach (var kv in Wav) File.WriteAllBytes(Path.Combine(ArtDir, kv.Key + ".wav"), res["WAVE/" + kv.Value]);
            using (var ico = Art.PeIcon(res)) if (ico != null) { Art.SavePng(ico, Path.Combine(ArtDir, "icon.png")); Art.SaveIco(ico, Path.Combine(ArtDir, "icon.ico")); }
            var strings = new Dictionary<int, string>();
            foreach (var kv in res)
            {
                if (!kv.Key.StartsWith("6/")) continue;
                int block = int.Parse(kv.Key.Substring(2)); byte[] d = kv.Value; int p = 0;
                for (int i = 0; i < 16 && p + 2 <= d.Length; i++)
                {
                    int n = BitConverter.ToUInt16(d, p); p += 2;
                    strings[(block - 1) * 16 + i] = Encoding.Unicode.GetString(d, p, n * 2); p += n * 2;
                }
            }
            var lines = new List<string>();
            foreach (var kv in Str) { string s; lines.Add(kv.Key + "=" + (strings.TryGetValue(kv.Value, out s) ? s.Replace("\t", " ") : "")); }
            File.WriteAllLines(Path.Combine(ArtDir, "strings.txt"), lines.ToArray());
        }

        // ---------------------------------------------------------------- the window
        Skin f; Dictionary<string, Image> im = new Dictionary<string, Image>(); Dictionary<string, string> S;
        List<string> term = new List<string>(); string typing = ""; Queue<string> pending = new Queue<string>(); Action afterTyping;
        Skin.Sprite tab, lbl, play, bar1, bar2; System.Windows.Forms.Timer typer;
        Font mono = new Font("Consolas", 9.5f); Brush green = new SolidBrush(Color.FromArgb(56, 232, 72));
        static readonly Rectangle Panel = new Rectangle(14, 50, 472, 230);

        Image I(string k) { Image v; if (!im.TryGetValue(k, out v)) im[k] = v = Image.FromFile(Path.Combine(ArtDir, k + ".png")); return v; }
        void Sound(string k) { Art.Play(Path.Combine(ArtDir, k + ".wav")); }

        public void Run()
        {
            S = Art.ReadConf(Path.Combine(ArtDir, "strings.txt"));
            Image icon = File.Exists(Path.Combine(ArtDir, "icon.png")) ? I("icon") : null;
            f = new Skin("The Matrix Online", I("splash"), icon, 0);
            Sound("splash");
            var t = new System.Windows.Forms.Timer { Interval = 1600 };
            t.Tick += (s, e) => { t.Stop(); Build(); };
            t.Start();
            Application.Run(f);
        }

        void Build()
        {
            f.Background = I("frame");
            f.Button(440, 4, I("min"), I("min_p"), null, () => f.WindowState = FormWindowState.Minimized);
            f.Button(470, 4, I("close"), I("close_p"), null, () => f.Close());
            tab = f.Button(22, 13, I("tab_patch"), null, null, null);
            lbl = f.Button(327, 296, I("lbl_blank"), null, null, null);
            f.Button(9, 307, I("row_on"), null, null, null);
            bar1 = f.Button(75, 344, I("bar_done"), null, null, null); bar1.Visible = false;
            bar2 = f.Button(75, 360, I("bar_done"), null, null, null); bar2.Visible = false;
            play = f.Button(339, 324, I("play_off"), null, null, null);
            f.Button(339, 379, I("quit"), I("quit_hi"), null, () => f.Close());
            f.Button(9, 376, I("acct"), I("acct_hi"), null, Account);
            f.Button(114, 376, I("comm"), I("comm_hi"), null, Community);
            f.Button(219, 376, I("supp"), I("supp_hi"), null, Support);
            f.Painter = g =>
            {
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
                int y = Panel.Y + 4;
                var all = new List<string>(term); all.Add(typing);
                int first = Math.Max(0, all.Count + (link != null ? 1 : 0) - Panel.Height / 14);
                for (int i = first; i < all.Count; i++, y += 14) g.DrawString(all[i], mono, green, Panel.X + 2, y);
                if (link != null)
                {
                    y -= 14;     // the empty "typing" slot
                    using (var b = new SolidBrush(linkHot ? Color.White : Color.FromArgb(168, 255, 176))) g.DrawString(link, mono, b, Panel.X + 2, y);
                    linkSpot.Rect = new Rectangle(Panel.X + 2, y, (int)g.MeasureString(link, mono).Width, 14);
                }
            };
            linkSpot = f.Hotspot(Rectangle.Empty, () => { if (link != null) DisplaySettings(); },
                                 () => { linkHot = true; f.Invalidate(); }, () => { linkHot = false; f.Invalidate(); });
            typer = new System.Windows.Forms.Timer { Interval = 12 };
            typer.Tick += Type;
            Say(new[] { S["os"], "", S["ssh"], S["check"] }, Check);
            f.Invalidate();
        }

        // ---- the green terminal: type lines out one character at a time
        string current; int pos;
        void Say(IEnumerable<string> lines, Action then)
        {
            foreach (var l in lines) pending.Enqueue(l);
            afterTyping = then; if (!typer.Enabled) { NextLine(); typer.Start(); }
        }
        void NextLine() { current = pending.Count > 0 ? pending.Dequeue() : null; pos = 0; typing = ""; }
        void Type(object s, EventArgs e)
        {
            if (current == null) { typer.Stop(); var a = afterTyping; afterTyping = null; if (a != null) a(); return; }
            pos = Math.Min(current.Length, pos + 2);
            typing = current.Substring(0, pos) + (pos < current.Length ? "_" : "");
            if (pos >= current.Length) { term.Add(current); typing = ""; NextLine(); }
            f.Invalidate();
        }
        void Clear() { term.Clear(); pending.Clear(); typing = ""; current = null; link = null; linkSpot.Rect = Rectangle.Empty; }

        // ---- resolution: ScreenWidth / ScreenHeight / Windowed in useropts.cfg (it overrides autoexec.cfg)
        string link; bool linkHot; Skin.Spot linkSpot;

        static void ReadDisplay(out int w, out int h, out string mode)
        {
            var v = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase) { { "ScreenWidth", 1024 }, { "ScreenHeight", 768 }, { "Windowed", 0 } };
            foreach (var cfg in new[] { "autoexec.cfg", "useropts.cfg" })
            {
                string p = Path.Combine(Dir, cfg); if (!File.Exists(p)) continue;
                foreach (var line in File.ReadAllLines(p))
                {
                    var m = Regex.Match(line, @"^\s*(ScreenWidth|ScreenHeight|Windowed)\s*=\s*(\d+)", RegexOptions.IgnoreCase);
                    if (m.Success) v[m.Groups[1].Value] = int.Parse(m.Groups[2].Value);
                }
            }
            w = v["ScreenWidth"]; h = v["ScreenHeight"]; mode = v["Windowed"] != 0 ? "windowed" : "fullscreen";
        }

        static void WriteDisplay(int w, int h, string mode)
        {
            string p = Path.Combine(Dir, "useropts.cfg");
            var o = new List<string>();
            if (File.Exists(p))
                foreach (var line in File.ReadAllLines(p))
                    if (!Regex.IsMatch(line, @"^\s*(ScreenWidth|ScreenHeight|Windowed)\s*=", RegexOptions.IgnoreCase)) o.Add(line);
            o.Add("ScreenWidth = " + w); o.Add("ScreenHeight = " + h); o.Add("Windowed = " + (mode == "windowed" ? 1 : 0));
            File.WriteAllLines(p, o.ToArray());
        }

        static string DisplayLine() { int w, h; string m; ReadDisplay(out w, out h, out m); return "> Display: " + w + " x " + h + ", " + m + "  [change]"; }
        void ShowLink() { link = DisplayLine(); f.Invalidate(); }

        void DisplaySettings()
        {
            Sound("click");
            int w, h; string m; ReadDisplay(out w, out h, out m);
            Display.Show(f, Color.FromArgb(2, 12, 4), Color.FromArgb(159, 220, 166), Color.FromArgb(56, 232, 72), Color.FromArgb(11, 36, 16), "Consolas",
                         w, h, m, new[] { "fullscreen", "windowed" }, (nw, nh, nm) => { WriteDisplay(nw, nh, nm); ShowLink(); });
        }

        // first a signed launcher update from the GitHub releases (rebuilt on this PC, then restarted), then the file scan
        void Check()
        {
            string exe = Application.ExecutablePath; Updater.Cleanup(exe);
            new Thread(() =>
            {
                var u = Updater.Check(Repo, Version);
                f.BeginInvoke((Action)(() =>
                {
                    if (u == null) { Scan(); return; }
                    bar1.Img = I("bar_dl"); bar1.Visible = true; f.Invalidate();
                    Say(new[] { "launcher update v" + u.Version + " found (you have v" + Version + ")", "downloading..." }, () =>
                        new Thread(() =>
                        {
                            bool ok = Updater.Apply(Repo, u, Dir, exe);
                            f.BeginInvoke((Action)(() =>
                            {
                                if (ok) { bar2.Visible = true; Say(new[] { "signature and checksums OK.", "restarting the launcher..." }, () => { Art.Start(exe, "", Dir); f.Close(); }); }
                                else { bar1.Img = I("bar_done"); bar1.Visible = false; Say(new[] { "update failed - keeping this version." }, Scan); }
                            }));
                        }) { IsBackground = true }.Start());
                }));
            }) { IsBackground = true }.Start();
        }

        void Scan()
        {
            string[] need = { "client.dll", "launcher.exe", "MatrixPrivate.exe", "useropts.cfg", "resource" };
            var bad = new List<string>();
            foreach (var n in need) if (!File.Exists(Path.Combine(Dir, n)) && !Directory.Exists(Path.Combine(Dir, n))) bad.Add(n);
            bar1.Visible = true;
            var lines = new List<string>();
            foreach (var n in need) lines.Add(S["scan"].Replace("%s", n));
            Say(lines, () =>
            {
                bar2.Visible = true;
                if (bad.Count > 0) { Say(new[] { "", "MISSING: " + string.Join(", ", bad.ToArray()), "Run the installer again to repair." }, null); return; }
                lbl.Img = I("lbl_done"); Sound("done");
                Say(new[] { "", S["uptodate"], S["access"] }, Worlds);
            });
        }

        void Worlds()
        {
            tab.Img = I("tab_select"); f.Invalidate();
            new Thread(() =>
            {
                bool up = Server.Length > 0 && Art.TcpUp(Server, 11000, 2000);
                int players = -1;
                try
                {
                    var wc = new WebClient(); string j = wc.DownloadString("http://" + Server + ":8096/status.json");
                    var m = Regex.Match(j, "\"mxo\"\\s*:\\s*\\{[^}]*\"players\"\\s*:\\s*(\\d+)");
                    if (m.Success) players = int.Parse(m.Groups[1].Value);
                }
                catch { }
                f.BeginInvoke((Action)(() =>
                {
                    Say(new[] { "", S["select"], "",
                        string.Format("  {0,-22} {1,-8} {2}", S["name"], S["status"], "Load"),
                        string.Format("  {0,-22} {1,-8} {2}", World, up ? S["open"] : S["down"], players < 0 ? "-" : players + " online") },
                        () => Ready(up));
                }));
            }) { IsBackground = true }.Start();
        }

        void Ready(bool up)
        {
            play.Img = I("play"); play.Hover = I("play_hi"); play.Pressed = I("play_pr"); play.Click = Launch;
            tab.Img = I("tab_done"); f.Invalidate();
            Say(up ? new[] { "" } : new[] { "", "(the world isn't answering right now - you can still try)", "" }, ShowLink);
        }

        void Launch()
        {
            Sound("click");
            Art.Start(Path.Combine(Dir, "MatrixPrivate.exe"), "-nopatch -clone", Dir);
            var t = new System.Windows.Forms.Timer { Interval = 700 }; t.Tick += (s, e) => f.Close(); t.Start();
        }

        void Account()
        {
            Sound("click"); Clear();
            Say(new[] { "ACCOUNTS", "", "No sign-up needed. At the game's login screen type",
                "a NEW username and password: your account is made", "on the spot. Next time use the same ones.",
                "Use a password you don't use anywhere else.", "", "Then create your character (body, face, clothes)",
                "in the character creator and enter the city." }, null);
        }

        void Community()
        {
            Sound("click"); Clear();
            new Thread(() =>
            {
                var names = new List<string>();
                try
                {
                    string j = new WebClient().DownloadString("http://" + Server + ":8096/status.json");
                    var m = Regex.Match(j, "\"mxo\"\\s*:\\s*\\{.*?\"list\"\\s*:\\s*\\[([^\\]]*)\\]");
                    if (m.Success) foreach (Match n in Regex.Matches(m.Groups[1].Value, "\"([^\"]*)\"")) names.Add("  " + n.Groups[1].Value);
                }
                catch { }
                if (names.Count == 0) names.Add("  nobody right now (or the list isn't reachable from here)");
                f.BeginInvoke((Action)(() => { names.InsertRange(0, new[] { "WHO IS JACKED IN (" + World + ")", "" }); Say(names, null); }));
            }) { IsBackground = true }.Start();
        }

        void Support()
        {
            Sound("click"); Clear();
            Say(new[] { "SUPPORT", "", "Screen size and windowed mode: the line below.", "Detail settings: 'The Matrix Online Settings'",
                "in the Start menu (auto-detect tool).", "Can't log in? The server may be restarting - try", "again in a minute.  Install folder:",
                "  " + Dir, "" }, ShowLink);
        }

        [STAThread]
        public static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            try
            {
                if (Array.IndexOf(args, "--extract") >= 0 || !File.Exists(Path.Combine(ArtDir, "strings.txt"))) Extract();
                if (Array.IndexOf(args, "--extract") < 0) new MxoLauncher().Run();
            }
            catch (Exception e) { MessageBox.Show(e.Message, "The Matrix Online launcher"); }
        }
    }
}
