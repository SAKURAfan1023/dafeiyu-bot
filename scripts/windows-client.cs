using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

static class DaFeiYuClient {
    [STAThread]
    static int Main(string[] args) {
        bool napcat = args.Length == 1 && args[0] == "--napcat";
        if (args.Length > (napcat ? 1 : 0)) return 1;
        try {
            string runtime = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "runtime");
            var start = new ProcessStartInfo(Path.Combine(runtime, "node.exe"),
                "\"" + Path.Combine(runtime, "launch.mjs") + "\" " + (napcat ? "napcat" : "client"));
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            // Browsers may keep their inherited working directory open after the launcher exits.
            start.WorkingDirectory = Environment.SystemDirectory;
            using (var child = Process.Start(start)) {
                child.WaitForExit();
                if (child.ExitCode != 0) throw new Exception();
            }
            return 0;
        } catch {
            MessageBox.Show(napcat ? "内置 NapCat 准备失败，请检查目录权限及安装包是否完整；已有配置不会被覆盖。" : "无法打开大肥鱼 QQ 客户端。请确认 Microsoft Visual C++ x64 运行库已安装，并检查同目录的使用说明；升级前请先断开并停止旧后台。", "大肥鱼", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
