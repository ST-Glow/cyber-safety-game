using System.Collections;
using System.Diagnostics;
using System.IO;
using CyberSafetyGame.Telemetry;
using UnityEngine;

namespace CyberSafetyGame.Recording
{
    public sealed class FfmpegPipeScreenRecorder : IRuntimeScreenRecorder
    {
        public bool IsRecording { get; private set; }
        public string OutputPath { get; private set; }

        Process process;
        int width;
        int height;
        int fps;

        public IEnumerator StartRecording(string outputPath, int captureWidth, int captureHeight, int captureFps)
        {
            OutputPath = outputPath;
            width = Mathf.Max(16, captureWidth);
            height = Mathf.Max(16, captureHeight);
            fps = Mathf.Clamp(captureFps, 1, 30);

            var ffmpegPath = ResolveFfmpegPath();
            if (string.IsNullOrEmpty(ffmpegPath))
            {
                yield break;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(OutputPath));
            if (File.Exists(OutputPath))
            {
                File.Delete(OutputPath);
            }

            var args = "-y -f rawvideo -pix_fmt rgba -s " + width + "x" + height +
                       " -r " + fps + " -i pipe:0 -vf vflip -an -c:v libx264 -preset veryfast -pix_fmt yuv420p " +
                       Quote(OutputPath);

            process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = ffmpegPath,
                    Arguments = args,
                    UseShellExecute = false,
                    RedirectStandardInput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true
                }
            };

            try
            {
                process.Start();
            }
            catch (System.Exception exception)
            {
                process?.Dispose();
                process = null;
                TelemetryManager.Ensure().LogEvent("recording_unavailable", new System.Collections.Generic.Dictionary<string, object>
                {
                    ["mode"] = "ffmpeg_mp4",
                    ["reason"] = exception.GetType().Name
                });
                yield break;
            }

            IsRecording = true;
            TelemetryManager.Ensure().LogEvent("recording_started", new System.Collections.Generic.Dictionary<string, object>
            {
                ["mode"] = "ffmpeg_mp4",
                ["width"] = width,
                ["height"] = height,
                ["fps"] = fps
            });

            yield return null;
        }

        public IEnumerator CaptureLoop()
        {
            var wait = new WaitForEndOfFrame();
            var frameDelay = new WaitForSecondsRealtime(1f / Mathf.Max(1, fps));

            while (IsRecording && process != null && !process.HasExited)
            {
                yield return wait;
                var texture = ScreenCapture.CaptureScreenshotAsTexture();
                if (texture != null)
                {
                    var scaled = ResizeIfNeeded(texture, width, height);
                    var raw = scaled.GetRawTextureData<byte>().ToArray();
                    try
                    {
                        process.StandardInput.BaseStream.Write(raw, 0, raw.Length);
                    }
                    catch
                    {
                        IsRecording = false;
                    }

                    Object.Destroy(scaled);
                    if (scaled != texture)
                    {
                        Object.Destroy(texture);
                    }
                }

                yield return frameDelay;
            }
        }

        public IEnumerator StopRecording()
        {
            IsRecording = false;
            if (process != null)
            {
                try
                {
                    process.StandardInput.Flush();
                    process.StandardInput.Close();
                    if (!process.WaitForExit(3000))
                    {
                        process.Kill();
                    }
                }
                catch
                {
                    if (!process.HasExited)
                    {
                        process.Kill();
                    }
                }
                finally
                {
                    process.Dispose();
                    process = null;
                }
            }

            TelemetryManager.Ensure().LogEvent("recording_stopped", new System.Collections.Generic.Dictionary<string, object>
            {
                ["mode"] = "ffmpeg_mp4",
                ["output_path"] = OutputPath,
                ["file_exists"] = File.Exists(OutputPath)
            });
            yield return null;
        }

        public static string ResolveFfmpegPath()
        {
            var bundled = Path.Combine(Application.streamingAssetsPath, "ffmpeg", "bin", "ffmpeg.exe");
            if (File.Exists(bundled))
            {
                return bundled;
            }

            return "ffmpeg";
        }

        static Texture2D ResizeIfNeeded(Texture2D source, int targetWidth, int targetHeight)
        {
            if (source.width == targetWidth && source.height == targetHeight)
            {
                return source;
            }

            var renderTexture = RenderTexture.GetTemporary(targetWidth, targetHeight, 0, RenderTextureFormat.ARGB32);
            Graphics.Blit(source, renderTexture);
            var previous = RenderTexture.active;
            RenderTexture.active = renderTexture;
            var result = new Texture2D(targetWidth, targetHeight, TextureFormat.RGBA32, false);
            result.ReadPixels(new Rect(0, 0, targetWidth, targetHeight), 0, 0);
            result.Apply();
            RenderTexture.active = previous;
            RenderTexture.ReleaseTemporary(renderTexture);
            return result;
        }

        static string Quote(string path)
        {
            return "\"" + path.Replace("\"", "\\\"") + "\"";
        }
    }
}
