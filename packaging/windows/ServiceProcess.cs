using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

// Callbacks run entirely in .NET; no PowerShell runspace is needed to drain pipes.
public sealed class PlantService : IDisposable {
    readonly object gate = new object();
    readonly StreamWriter output, error;
    public Process Process { get; private set; }
    public string Name { get; private set; }
    public PlantService(string name, string executable, string arguments, string workingDirectory,
                        string outputPath, string errorPath, IDictionary<string,string> environment) {
        Name = name;
        output = new StreamWriter(outputPath, false, new UTF8Encoding(false)); output.AutoFlush = true;
        try { error = new StreamWriter(errorPath, false, new UTF8Encoding(false)); error.AutoFlush = true; }
        catch { output.Dispose(); throw; }
        Process = new Process();
        Process.StartInfo = new ProcessStartInfo(executable, arguments) {
            WorkingDirectory = workingDirectory, UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
        };
        foreach (var item in environment) {
            if (item.Value == null) Process.StartInfo.EnvironmentVariables.Remove(item.Key);
            else Process.StartInfo.EnvironmentVariables[item.Key] = item.Value;
        }
        Process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e) { Write(output, e.Data); };
        Process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) { Write(error, e.Data); };
    }
    void Write(StreamWriter writer, string line) {
        if (line == null) return;
        lock(gate) { writer.WriteLine(DateTime.UtcNow.ToString("o") + " " + line); }
    }
    public void Start() {
        if (!Process.Start()) throw new IOException("Process.Start returned false: " + Name);
        Process.BeginOutputReadLine(); Process.BeginErrorReadLine();
    }
    public bool HasExited { get { Process.Refresh(); return Process.HasExited; } }
    public string ExitCodeText { get { return HasExited ? Process.ExitCode.ToString() + " (0x" + unchecked((uint)Process.ExitCode).ToString("X8") + ")" : "running"; } }
    // WaitForExit() after the timed wait also drains the async stdout/stderr callbacks.
    public void FlushExited() { if (HasExited) Process.WaitForExit(); }
    public void Dispose() {
        try {
            if (!HasExited) Process.Kill();
            if (Process.WaitForExit(3000)) Process.WaitForExit();
        } catch (InvalidOperationException) { }
        finally {
            // A process which could not be stopped may still send callbacks. Do not close its pipes early.
            try { if (HasExited) { lock(gate) { output.Dispose(); error.Dispose(); } Process.Dispose(); } }
            catch (InvalidOperationException) { lock(gate) { output.Dispose(); error.Dispose(); } Process.Dispose(); }
        }
    }
}
