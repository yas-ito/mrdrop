// Mr.Drop — Windows の通知領域（タスクバー右下）に常駐して、本体を抱える小さなプログラム。
//
// 🔴 これが「本体を動かす人」です（本人決定 2026-09-12）。
//    ・node server/mrdrop.js --follow-stdin を**子として**動かす
//    ・このプログラムが終われば、標準入力が閉じて本体も一緒に終わる
//    ・Mac 版（mac/main.swift）とまったく同じ考え方。両OSで揃う
//
// 🔴 前はタスクスケジューラの S4U で窓なし常駐にしていた。やめた理由:
//    ・動いているかが**どこにも見えない**（本人が何度も「動いてる？」と迷った）
//    ・登録に管理者が要る。いまは自動起動がレジストリの Run なので要らない
//      （管理者が要るのはファイアウォールを開ける1回だけ）
//
// 🔴 設定を触る操作は**自分で実装せず、scripts\settings-windows.ps1 を呼ぶ**。
//    受信先の既定値や config.json の書き方を2か所に持つと必ずずれる。
//    実際、config.js と .ps1 の既定がずれて事故ったことがある（2026-09-12）。
//
// ビルド: build\build-tray.ps1（Windows 標準の csc.exe だけ。SDK 不要）

using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Microsoft.Win32;

namespace MrDrop
{
    static class Program
    {
        public const string AppName = "Mr.Drop";
        public const string MutexName = "MrDrop.Tray.SingleInstance";

        [STAThread]
        static void Main()
        {
            bool created;
            using (var mutex = new System.Threading.Mutex(true, MutexName, out created))
            {
                if (!created) return;          // すでに動いている。黙って終わる
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new TrayContext());
            }
        }
    }

    class TrayContext : ApplicationContext
    {
        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        const string RunName = "MrDrop";

        readonly string appRoot;               // このプログラムが置かれている所
        readonly string nodeExe;
        readonly string entryJs;
        readonly string settingsPs1;
        readonly string manualHtml;

        readonly NotifyIcon tray;
        readonly ToolStripMenuItem stateItem;
        readonly ToolStripMenuItem startupItem;
        readonly System.Windows.Forms.Timer poll;
        readonly string versionText;           // 「   バージョン 1.0.2」。読めなければ空

        Process server;
        bool quitting;

        public TrayContext()
        {
            appRoot     = Path.GetDirectoryName(Application.ExecutablePath);
            nodeExe     = Path.Combine(appRoot, "node", "node.exe");
            entryJs     = Path.Combine(appRoot, "server", "mrdrop.js");
            settingsPs1 = Path.Combine(appRoot, "scripts", "settings-windows.ps1");
            manualHtml  = Path.Combine(appRoot, "取扱説明書.html");

            // 🔴 版数はここに書き写さない（ReadPort と同じ理由）。写すと server/mrdrop.js と
            //    ずれたときに黙って食い違い、**どちらが入っているのか分からなくなる**。
            //    入れ替えると exe も起動し直すので、ここで1回読めば足りる。
            string v = ReadVersion();
            versionText = v.Length > 0 ? "   バージョン " + v : "";

            stateItem = new ToolStripMenuItem("しらべています…");
            stateItem.Enabled = false;

            startupItem = new ToolStripMenuItem("Windows 起動時に自動で開始", null, ToggleStartup);
            startupItem.Checked = IsStartupEnabled();

            var menu = new ContextMenuStrip();
            menu.Items.Add(stateItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(new ToolStripMenuItem("受信先を開く", null, (s, e) => RunSettings("-OpenInbox", false)));
            // 🔴 送信箱はデスクトップの中だが、**デスクトップの場所は人によって違う**
            //    （OneDrive でデスクトップを移している人がいる）。2026-09-15 に買った人が
            //    「送信箱がデスクトップに出てこない」で詰まった。ここから必ず開ける。
            menu.Items.Add(new ToolStripMenuItem("送信箱を開く", null, (s, e) => RunSettings("-OpenOutbox", false)));
            menu.Items.Add(new ToolStripMenuItem("受信先を変える...", null, (s, e) => ChangeInbox()));
            menu.Items.Add(new ToolStripMenuItem("送信箱を変える...", null, (s, e) => ChangeOutbox()));
            menu.Items.Add(new ToolStripMenuItem("この PC の名前を変える...", null, (s, e) => ChangeName()));
            menu.Items.Add(new ToolStripMenuItem("取扱説明書", null, (s, e) => OpenManual()));
            menu.Items.Add(startupItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(new ToolStripMenuItem("Mr.Drop をアンインストール", null, (s, e) => Uninstall()));
            menu.Items.Add(new ToolStripMenuItem("終了", null, (s, e) => Quit()));

            tray = new NotifyIcon();
            tray.Icon = LoadIcon();
            tray.Text = Program.AppName;
            tray.ContextMenuStrip = menu;
            tray.Visible = true;
            tray.DoubleClick += (s, e) => RunSettings("-OpenInbox", false);

            StartServer();

            poll = new System.Windows.Forms.Timer();
            poll.Interval = 2000;
            poll.Tick += (s, e) => Refresh();
            poll.Start();
            Refresh();
        }

        // 🔴 アイコンの居場所は、ここ（常駐側）からは伝えられない。
        //    Windows 11 は新しいトレイアイコンを**既定で「∧」の中に隠す**うえ、
        //    **隠れているアイコンからの吹き出し（ShowBalloonTip）は表示されない**。
        //    レジストリの IsPromoted=1 も、あとから書いても効かない
        //    （Windows 11 26200 で確認。値は残るのにアイコンは出ない。
        //      エクスプローラを再起動しても同じ）。
        //    → **入れたあとの画面（install-windows.ps1 の最後）で文字で伝える**。
        //      あそこは はじめる.bat が pause で止めているので、必ず読まれる。

        // ── 見た目 ────────────────────────────────────────────
        Icon LoadIcon()
        {
            // 自分の .exe に埋め込んだアイコンを使う（別ファイルにすると消える事故がある）
            try { return Icon.ExtractAssociatedIcon(Application.ExecutablePath); }
            catch { return SystemIcons.Application; }
        }

        void Refresh()
        {
            bool up = server != null && !server.HasExited;
            stateItem.Text = (up ? "● 動いています" : "○ 止まっています") + versionText;

            string tip = Program.AppName + (up ? " — 動いています" : " — 止まっています");
            int port = ReadPort();
            if (up && port > 0)
            {
                string host = Environment.MachineName.ToLowerInvariant().Replace(".", "-");
                tip = Program.AppName + " — http://" + host + ".local:" + port;
            }
            // NotifyIcon.Text は 63 文字まで。超えると例外になる
            if (tip.Length > 63) tip = tip.Substring(0, 63);
            tray.Text = tip;
        }

        // config.json から番号だけ読む。
        // 🔴 既定値はここに持たない。無ければ「分からない」ままにする。
        //    既定を書き写すと、server/lib/config.js とずれたときに黙って食い違う。
        int ReadPort()
        {
            try
            {
                string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string cfg = Path.Combine(local, "MrDrop", "config.json");
                if (!File.Exists(cfg)) return 0;
                var m = Regex.Match(File.ReadAllText(cfg, Encoding.UTF8), "\"port\"\\s*:\\s*\"?(\\d+)\"?");
                if (m.Success) return int.Parse(m.Groups[1].Value);
            }
            catch { }
            return 0;
        }

        // 版数は server/mrdrop.js から読む（本体が名乗るのと同じ数）。
        // 🔴 ここに書き写さないこと。上の ReadPort と同じ理由で、写すと黙って食い違い、
        //    **どちらの版が入っているのか分からなくなる**（入れ替えのたびに必ず要る情報）。
        string ReadVersion()
        {
            try
            {
                if (!File.Exists(entryJs)) return "";
                var m = Regex.Match(File.ReadAllText(entryJs, Encoding.UTF8), "const VERSION = \"([^\"]+)\"");
                if (m.Success) return m.Groups[1].Value;
            }
            catch { }
            return "";
        }

        // ── 本体（node）を抱える ──────────────────────────────
        void StartServer()
        {
            if (!File.Exists(nodeExe) || !File.Exists(entryJs))
            {
                MessageBox.Show(
                    "Mr.Drop の中身が見つかりません。\n\n" + appRoot + "\n\n" +
                    "ZIP をフォルダごと展開して、「はじめる.bat」を押し直してください。",
                    Program.AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            try
            {
                var psi = new ProcessStartInfo(nodeExe, "\"" + entryJs + "\" --follow-stdin");
                psi.WorkingDirectory       = appRoot;
                psi.UseShellExecute        = false;
                psi.CreateNoWindow         = true;      // 黒い画面を出さない
                psi.RedirectStandardInput  = true;      // 🔴 これを閉じると本体が自分で終わる
                psi.RedirectStandardOutput = true;      // 掴んでおかないと見えない窓へ出ようとする
                psi.RedirectStandardError  = true;
                server = Process.Start(psi);
                server.EnableRaisingEvents = true;
                // 溜まって詰まらないよう読み捨てる。記録は本体が自分でファイルに書いている
                server.BeginOutputReadLine();
                server.BeginErrorReadLine();
                server.OutputDataReceived += delegate { };
                server.ErrorDataReceived += delegate { };
            }
            catch (Exception ex)
            {
                server = null;
                MessageBox.Show("Mr.Drop を動かせませんでした。\n\n" + ex.Message,
                    Program.AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        void StopServer()
        {
            if (server == null) return;
            try
            {
                if (!server.HasExited)
                {
                    // 🔴 まず標準入力を閉じる。--follow-stdin がこれを見て、
                    //    mDNS に「さよなら」を打ってから畳む（いきなり殺すと、
                    //    iPhone 側の一覧にしばらく幽霊が残る）。
                    try { server.StandardInput.Close(); } catch { }
                    if (!server.WaitForExit(4000)) server.Kill();
                }
            }
            catch { }
            server = null;
        }

        void RestartServer()
        {
            StopServer();
            // 前のものが番号を離すまで少し待つ
            System.Threading.Thread.Sleep(600);
            StartServer();
            Refresh();
        }

        // ── 設定は .ps1 に任せる（実装を2つ持たない）──────────
        Process RunSettings(string arg, bool wait)
        {
            if (!File.Exists(settingsPs1))
            {
                MessageBox.Show("scripts\\settings-windows.ps1 が見つかりません。\n\n" + appRoot,
                    Program.AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
                return null;
            }
            try
            {
                var psi = new ProcessStartInfo("powershell.exe",
                    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + settingsPs1 + "\" " + arg);
                psi.UseShellExecute = false;
                psi.CreateNoWindow  = true;     // 黒い画面は出さない。フォルダ選択の窓だけ出る
                var p = Process.Start(psi);
                if (wait && p != null) p.WaitForExit();
                return p;
            }
            catch (Exception ex)
            {
                MessageBox.Show("うまくいきませんでした。\n\n" + ex.Message,
                    Program.AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
                return null;
            }
        }

        void ChangeInbox()
        {
            // 🔴 受信先は起動したときにしか読まない。変えたら**こちらで入れ直す**。
            //    前は .ps1 がタスクを入れ直していたが、いまは本体を抱えているのは私。
            RunSettings("-ChooseInbox -FromTray", true);
            RestartServer();
        }

        // 🔴 送信箱も同じ。**中身は .ps1 が一緒に引っ越す**（場所だけ変えると置き去りになる）。
        //    引っ越しの決まりは向こうに一本化してある。ここには持たない。
        void ChangeOutbox()
        {
            RunSettings("-ChooseOutbox -FromTray", true);
            RestartServer();
        }

        // 🔴 iPhone の一覧に出る名前。既定はパソコンの名前そのまま。
        //    Mac が実機で踏んだ（`yas` と `yasnoMac-mini-local` が並んで取り違えた）。
        //    中身は .ps1 に任せる。設定の書き方を2か所に持たない。
        void ChangeName()
        {
            RunSettings("-ChooseName -FromTray", true);
            RestartServer();
        }

        void OpenManual()
        {
            if (File.Exists(manualHtml)) { try { Process.Start(manualHtml); } catch { } }
            else MessageBox.Show("取扱説明書が見つかりません。\n\n" + manualHtml,
                Program.AppName, MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        void Uninstall()
        {
            var ok = MessageBox.Show(
                "Mr.Drop をこのパソコンから外します。\n\n" +
                "・自動起動\n・ファイアウォールに開けた穴\n・入れたプログラムと設定と記録\n\n" +
                "届いたファイルは消しません。受信先も送信箱もそのままです。\n\n" +
                "よろしいですか？",
                Program.AppName, MessageBoxButtons.OKCancel, MessageBoxIcon.Question);
            if (ok != DialogResult.OK) return;

            // 本体を先に止める。動いたままだと自分の入っているフォルダを消せない
            StopServer();
            SetStartup(false);
            var p = RunSettings("-Uninstall", false);
            // アンインストーラが自分（.exe）の居場所を消すので、こちらは先に消える
            quitting = true;
            tray.Visible = false;
            ExitThread();
        }

        void Quit()
        {
            quitting = true;
            StopServer();
            tray.Visible = false;
            ExitThread();
        }

        // ── 自動起動（レジストリの Run。管理者は要らない）────
        static bool IsStartupEnabled()
        {
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(RunKey))
                    return k != null && k.GetValue(RunName) != null;
            }
            catch { return false; }
        }

        static void SetStartup(bool on)
        {
            try
            {
                using (var k = Registry.CurrentUser.OpenSubKey(RunKey, true))
                {
                    if (k == null) return;
                    if (on) k.SetValue(RunName, "\"" + Application.ExecutablePath + "\"");
                    else k.DeleteValue(RunName, false);
                }
            }
            catch { }
        }

        void ToggleStartup(object sender, EventArgs e)
        {
            bool on = !startupItem.Checked;
            SetStartup(on);
            startupItem.Checked = IsStartupEnabled();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (!quitting) StopServer();
                if (poll != null) poll.Dispose();
                if (tray != null) { tray.Visible = false; tray.Dispose(); }
            }
            base.Dispose(disposing);
        }
    }
}
