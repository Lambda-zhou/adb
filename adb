using System;
using System.Diagnostics;
using System.Text;
using System.Windows.Forms;
using System.Threading.Tasks;

public partial class ADBForm : Form
{
    private readonly ADBHelper _adb = new ADBHelper();
    private ComboBox cmbDevices;
    private TextBox txtOutput;
    private TextBox txtCommand;

    public ADBForm()
    {
        InitializeComponent();
        InitializeUI();
        RefreshDevices();
    }

    private void InitializeComponent()
    {
        // 基础窗体设置
        this.SuspendLayout();
        this.ClientSize = new System.Drawing.Size(800, 600);
        this.Text = "ADB 工具";
        this.ResumeLayout(false);
    }

    private void InitializeUI()
    {
        // 输出文本框
        txtOutput = new TextBox
        {
            Multiline = true,
            ScrollBars = ScrollBars.Vertical,
            Dock = DockStyle.Fill,
            ReadOnly = true,
            Font = new System.Drawing.Font("Consolas", 10)
        };

        // 命令输入框
        txtCommand = new TextBox 
        { 
            Dock = DockStyle.Top,
            Font = new System.Drawing.Font("微软雅黑", 10),
            Height = 30
        };

        // 执行按钮
        var btnExecute = new Button 
        { 
            Text = "执行 (Enter)", 
            Dock = DockStyle.Right,
            Width = 100
        };

        // 刷新按钮
        var btnRefresh = new Button 
        { 
            Text = "刷新设备", 
            Dock = DockStyle.Left,
            Width = 100
        };

        // 设备选择框
        cmbDevices = new ComboBox 
        { 
            Dock = DockStyle.Fill,
            DropDownStyle = ComboBoxStyle.DropDownList,
            Font = new System.Drawing.Font("微软雅黑", 10)
        };

        // 状态栏
        var statusStrip = new StatusStrip();
        var statusLabel = new ToolStripStatusLabel();
        statusStrip.Items.Add(statusLabel);

        // 布局面板
        var topPanel = new Panel { Dock = DockStyle.Top, Height = 30 };
        var devicePanel = new Panel { Dock = DockStyle.Top, Height = 30 };
        
        devicePanel.Controls.Add(btnRefresh);
        devicePanel.Controls.Add(cmbDevices);
        topPanel.Controls.Add(txtCommand);
        topPanel.Controls.Add(btnExecute);

        // 添加控件
        Controls.Add(txtOutput);
        Controls.Add(topPanel);
        Controls.Add(devicePanel);
        Controls.Add(statusStrip);

        // 事件绑定
        btnExecute.Click += ExecuteCommand;
        btnRefresh.Click += (s, e) => RefreshDevices();
        cmbDevices.SelectedIndexChanged += (s, e) => 
        {
            _adb.DeviceSerial = cmbDevices.SelectedItem?.ToString();
        };
        txtCommand.KeyDown += (s, e) => 
        {
            if (e.KeyCode == Keys.Enter) ExecuteCommand(s, e);
        };
    }

    private async void ExecuteCommand(object sender, EventArgs e)
    {
        if (string.IsNullOrEmpty(txtCommand.Text)) return;
        
        var statusLabel = ((StatusStrip)Controls[3]).Items[0] as ToolStripStatusLabel;

        try
        {
            statusLabel.Text = "执行中...";
            var (output, error) = await _adb.ExecuteADBCommandAsync(txtCommand.Text);
            
            txtOutput.AppendText($"> {txtCommand.Text}\n");
            if (!string.IsNullOrEmpty(output)) txtOutput.AppendText($"{output}\n");
            if (!string.IsNullOrEmpty(error)) txtOutput.AppendText($"[ERROR] {error}\n");
        }
        finally
        {
            statusLabel.Text = "就绪";
            txtCommand.Clear();
        }
    }

    private void RefreshDevices()
    {
        cmbDevices.BeginUpdate();
        cmbDevices.Items.Clear();
        
        var devices = _adb.GetDevices().Split('\n');
        foreach (var line in devices)
        {
            if (line.StartsWith("List") || string.IsNullOrWhiteSpace(line)) continue;
            var serial = line.Split('\t')[0];
            cmbDevices.Items.Add(serial);
        }
        
        if (cmbDevices.Items.Count > 0)
            cmbDevices.SelectedIndex = 0;
        
        cmbDevices.EndUpdate();
    }
}

public class ADBHelper
{
    public string ADBPath { get; set; } = "adb";
    public string DeviceSerial { get; set; }

    public string GetDevices()
    {
        using var process = new Process();
        process.StartInfo = new ProcessStartInfo
        {
            FileName = ADBPath,
            Arguments = "devices -l",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8
        };
        
        process.Start();
        return process.StandardOutput.ReadToEnd();
    }

    public async Task<(string Output, string Error)> ExecuteADBCommandAsync(string command, int timeout = 10000)
    {
        try
        {
            using var process = new Process();
            var tcs = new TaskCompletionSource<bool>();
            
            process.StartInfo = new ProcessStartInfo
            {
                FileName = ADBPath,
                Arguments = FormatCommandWithSerial(command),
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                StandardOutputEncoding = Encoding.UTF8
            };

            var output = new StringBuilder();
            var error = new StringBuilder();

            process.OutputDataReceived += (s, e) => 
            {
                if (e.Data != null) output.AppendLine(e.Data);
            };

            process.ErrorDataReceived += (s, e) => 
            {
                if (e.Data != null) error.AppendLine(e.Data);
            };

            process.Exited += (s, e) => tcs.TrySetResult(true);
            
            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            var timeoutTask = Task.Delay(timeout);
            var completedTask = await Task.WhenAny(tcs.Task, timeoutTask);

            if (completedTask == timeoutTask)
            {
                process.Kill();
                return ("", "执行超时");
            }

            return (output.ToString().Trim(), error.ToString().Trim());
        }
        catch (Exception ex)
        {
            return ("", $"错误: {ex.Message}");
        }
    }

    private string FormatCommandWithSerial(string command)
    {
        return string.IsNullOrEmpty(DeviceSerial) 
            ? command 
            : $"-s {DeviceSerial} {command}";
    }
}

// Program.cs 入口文件需要包含：
static class Program
{
    [STAThread]
    static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new ADBForm());
    }
}
