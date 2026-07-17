using System.Collections;

namespace CyberSafetyGame.Recording
{
    public interface IRuntimeScreenRecorder
    {
        bool IsRecording { get; }
        string OutputPath { get; }
        IEnumerator StartRecording(string outputPath, int width, int height, int fps);
        IEnumerator StopRecording();
    }
}

