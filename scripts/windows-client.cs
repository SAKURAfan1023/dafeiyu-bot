using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

static class DaFeiYuClient {
    [STAThread]
    static int Main() {
        try {
            string runtime = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "runtime");
            var start = new ProcessStartInfo(Path.Combine(runtime, "node.exe"),
                "\"" + Path.Combine(runtime, "launch.mjs") + "\" client");
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
            MessageBox.Show("无法打开大肥鱼 QQ 客户端。请确认 Microsoft Visual C++ x64 运行库已安装，并检查同目录的使用说明；升级前请先断开并停止旧后台。", "大肥鱼", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
