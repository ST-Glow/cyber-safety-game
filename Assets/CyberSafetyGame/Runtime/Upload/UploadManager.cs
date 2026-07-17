using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Text;
using CyberSafetyGame.Telemetry;
using UnityEngine;
using UnityEngine.Networking;

namespace CyberSafetyGame.Upload
{
    public sealed class UploadManager : MonoBehaviour
    {
        [SerializeField] bool uploadEnabled;
        [SerializeField] string baseUrl = "";
        [SerializeField] string apiKey = "";
        [SerializeField] float retryDelaySeconds = 10f;

        bool uploading;

        public static UploadManager Ensure()
        {
            var existing = FindFirstObjectByType<UploadManager>();
            if (existing != null)
            {
                return existing;
            }

            var gameObject = new GameObject("UploadManager");
            DontDestroyOnLoad(gameObject);
            return gameObject.AddComponent<UploadManager>();
        }

        public void Configure(bool enabled, string url, string key)
        {
            uploadEnabled = enabled;
            baseUrl = url;
            apiKey = key;
        }

        public void TryUploadAllSessions()
        {
            if (!uploadEnabled || uploading || string.IsNullOrWhiteSpace(baseUrl))
            {
                return;
            }

            StartCoroutine(UploadLoop());
        }

        IEnumerator UploadLoop()
        {
            uploading = true;
            var root = Path.Combine(Application.persistentDataPath, "CyberSafetyResearch", "sessions");
            Directory.CreateDirectory(root);

            foreach (var sessionDirectory in Directory.GetDirectories(root))
            {
                var marker = Path.Combine(sessionDirectory, "uploaded.ok");
                var endedMarker = Path.Combine(sessionDirectory, "ended.ok");
                if (File.Exists(marker))
                {
                    continue;
                }

                if (!File.Exists(endedMarker))
                {
                    continue;
                }

                var sessionId = Path.GetFileName(sessionDirectory);
                var success = true;
                foreach (var filePath in EnumerateUploadFiles(sessionDirectory))
                {
                    yield return UploadFile(sessionId, filePath, result => success = result);
                    if (!success)
                    {
                        TelemetryManager.Ensure().LogEvent("upload_failed", new Dictionary<string, object>
                        {
                            ["session_id_to_upload"] = sessionId,
                            ["file_name"] = Path.GetFileName(filePath)
                        });
                        yield return new WaitForSecondsRealtime(retryDelaySeconds);
                        break;
                    }
                }

                if (success)
                {
                    yield return CompleteSession(sessionId, result => success = result);
                }

                if (success)
                {
                    File.WriteAllText(marker, DateTime.UtcNow.ToString("o"), Encoding.UTF8);
                    TelemetryManager.Ensure().LogEvent("upload_completed", new Dictionary<string, object>
                    {
                        ["session_id_uploaded"] = sessionId
                    });
                }
            }

            uploading = false;
        }

        static IEnumerable<string> EnumerateUploadFiles(string sessionDirectory)
        {
            foreach (var path in Directory.GetFiles(sessionDirectory, "*", SearchOption.AllDirectories))
            {
                var name = Path.GetFileName(path);
                if (name == "uploaded.ok")
                {
                    continue;
                }

                yield return path;
            }
        }

        IEnumerator UploadFile(string sessionId, string filePath, Action<bool> onComplete)
        {
            var safeName = Uri.EscapeDataString(Path.GetFileName(filePath));
            var url = TrimSlash(baseUrl) + "/sessions/" + Uri.EscapeDataString(sessionId) + "/files/" + safeName;
            var bytes = File.ReadAllBytes(filePath);
            using var request = new UnityWebRequest(url, "POST");
            request.uploadHandler = new UploadHandlerRaw(bytes);
            request.downloadHandler = new DownloadHandlerBuffer();
            request.SetRequestHeader("Content-Type", "application/octet-stream");
            if (!string.IsNullOrWhiteSpace(apiKey))
            {
                request.SetRequestHeader("X-Research-Api-Key", apiKey);
            }

            yield return request.SendWebRequest();
            onComplete?.Invoke(request.result == UnityWebRequest.Result.Success);
        }

        IEnumerator CompleteSession(string sessionId, Action<bool> onComplete)
        {
            var url = TrimSlash(baseUrl) + "/sessions/" + Uri.EscapeDataString(sessionId) + "/complete";
            var body = TelemetryJson.Serialize(new Dictionary<string, object>
            {
                ["session_id"] = sessionId,
                ["client_time_utc"] = DateTime.UtcNow.ToString("o")
            });

            using var request = new UnityWebRequest(url, "POST");
            request.uploadHandler = new UploadHandlerRaw(Encoding.UTF8.GetBytes(body));
            request.downloadHandler = new DownloadHandlerBuffer();
            request.SetRequestHeader("Content-Type", "application/json");
            if (!string.IsNullOrWhiteSpace(apiKey))
            {
                request.SetRequestHeader("X-Research-Api-Key", apiKey);
            }

            yield return request.SendWebRequest();
            onComplete?.Invoke(request.result == UnityWebRequest.Result.Success);
        }

        static string TrimSlash(string value)
        {
            return (value ?? string.Empty).TrimEnd('/');
        }
    }
}
