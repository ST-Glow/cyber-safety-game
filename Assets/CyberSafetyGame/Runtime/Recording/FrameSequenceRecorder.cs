using System.Collections;
using System.IO;
using CyberSafetyGame.Telemetry;
using UnityEngine;

namespace CyberSafetyGame.Recording
{
    public sealed class FrameSequenceRecorder : IRuntimeScreenRecorder
    {
        public bool IsRecording { get; private set; }
        public string OutputPath { get; private set; }

        string frameDirectory;
        int frameIndex;
        int fps;

        public IEnumerator StartRecording(string outputPath, int width, int height, int captureFps)
        {
            OutputPath = outputPath;
            frameDirectory = Path.Combine(Path.GetDirectoryName(outputPath), "frames");
            Directory.CreateDirectory(frameDirectory);
            frameIndex = 0;
            fps = Mathf.Clamp(captureFps, 1, 10);
            IsRecording = true;
            TelemetryManager.Ensure().LogEvent("recording_started", new System.Collections.Generic.Dictionary<string, object>
            {
                ["mode"] = "png_frame_sequence",
                ["fps"] = fps,
                ["reason"] = "ffmpeg_not_available"
            });
            yield return null;
        }

        public IEnumerator CaptureLoop()
        {
            var wait = new WaitForEndOfFrame();
            var frameDelay = new WaitForSecondsRealtime(1f / Mathf.Max(1, fps));
            while (IsRecording)
            {
                yield return wait;
                var texture = ScreenCapture.CaptureScreenshotAsTexture();
                if (texture != null)
                {
                    var bytes = texture.EncodeToPNG();
                    File.WriteAllBytes(Path.Combine(frameDirectory, "frame_" + frameIndex.ToString("D06") + ".png"), bytes);
                    Object.Destroy(texture);
                    frameIndex++;
                }

                yield return frameDelay;
            }
        }

        public IEnumerator StopRecording()
        {
            IsRecording = false;
            TelemetryManager.Ensure().LogEvent("recording_stopped", new System.Collections.Generic.Dictionary<string, object>
            {
                ["mode"] = "png_frame_sequence",
                ["frame_count"] = frameIndex,
                ["output_directory"] = frameDirectory
            });
            yield return null;
        }
    }
}

