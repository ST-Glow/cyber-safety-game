using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using UnityEngine;

namespace CyberSafetyGame.Telemetry
{
    public sealed class TelemetryManager : MonoBehaviour
    {
        public static TelemetryManager Instance { get; private set; }

        public SessionPaths Paths { get; private set; }
        public string ParticipantHash { get; private set; } = "unset";
        public int EventCount { get; private set; }

        StreamWriter writer;
        DateTime sessionStartUtc;
        bool ended;

        public static TelemetryManager Ensure()
        {
            if (Instance != null)
            {
                return Instance;
            }

            var existing = FindFirstObjectByType<TelemetryManager>();
            if (existing != null)
            {
                Instance = existing;
                return existing;
            }

            var gameObject = new GameObject("TelemetryManager");
            DontDestroyOnLoad(gameObject);
            return gameObject.AddComponent<TelemetryManager>();
        }

        void Awake()
        {
            if (Instance != null && Instance != this)
            {
                Destroy(gameObject);
                return;
            }

            Instance = this;
            DontDestroyOnLoad(gameObject);
            BeginSession();
        }

        public void BeginSession()
        {
            if (Paths != null)
            {
                return;
            }

            sessionStartUtc = DateTime.UtcNow;
            Paths = new SessionPaths(SessionPaths.NewSessionId());
            Paths.EnsureDirectories();
            writer = new StreamWriter(new FileStream(Paths.EventLogPath, FileMode.Append, FileAccess.Write, FileShare.Read), Encoding.UTF8);

            LogEvent("session_started", new Dictionary<string, object>
            {
                ["unity_version"] = Application.unityVersion,
                ["platform"] = Application.platform.ToString(),
                ["data_policy"] = "anonymous_minimum_necessary",
                ["records_game_view_only"] = true,
                ["records_audio"] = false,
                ["records_camera"] = false
            });
        }

        public void SetParticipantCode(string anonymousCode)
        {
            ParticipantHash = HashParticipantCode(anonymousCode);
            LogEvent("participant_code_set", new Dictionary<string, object>
            {
                ["participant_hash"] = ParticipantHash,
                ["raw_code_stored"] = false
            });
        }

        public void LogEvent(string eventType, Dictionary<string, object> payload = null)
        {
            if (writer == null || ended)
            {
                return;
            }

            EventCount++;
            var envelope = new Dictionary<string, object>
            {
                ["event_id"] = EventCount,
                ["event_type"] = eventType,
                ["session_id"] = Paths.SessionId,
                ["participant_hash"] = ParticipantHash,
                ["client_time_utc"] = DateTime.UtcNow.ToString("o"),
                ["elapsed_seconds"] = Math.Round((DateTime.UtcNow - sessionStartUtc).TotalSeconds, 3),
                ["payload"] = payload ?? new Dictionary<string, object>()
            };

            writer.WriteLine(TelemetryJson.Serialize(envelope));
            writer.Flush();
        }

        public void WriteSummary(Dictionary<string, object> summary)
        {
            if (Paths == null)
            {
                return;
            }

            var envelope = new Dictionary<string, object>
            {
                ["session_id"] = Paths.SessionId,
                ["participant_hash"] = ParticipantHash,
                ["ended_at_utc"] = DateTime.UtcNow.ToString("o"),
                ["event_count"] = EventCount,
                ["summary"] = summary
            };

            File.WriteAllText(Paths.SummaryPath, TelemetryJson.Serialize(envelope), Encoding.UTF8);
        }

        public void EndSession(Dictionary<string, object> summary = null)
        {
            if (ended)
            {
                return;
            }

            LogEvent("session_ended", summary);
            WriteSummary(summary ?? new Dictionary<string, object>());
            File.WriteAllText(Paths.EndedMarkerPath, DateTime.UtcNow.ToString("o"), Encoding.UTF8);
            ended = true;
            writer?.Flush();
            writer?.Dispose();
            writer = null;
        }

        void OnApplicationQuit()
        {
            EndSession(new Dictionary<string, object> { ["reason"] = "application_quit" });
        }

        static string HashParticipantCode(string anonymousCode)
        {
            var normalized = (anonymousCode ?? string.Empty).Trim().ToUpperInvariant();
            using var sha = SHA256.Create();
            var bytes = sha.ComputeHash(Encoding.UTF8.GetBytes("cyber-safety-research-v1:" + normalized));
            var builder = new StringBuilder(bytes.Length * 2);
            foreach (var b in bytes)
            {
                builder.Append(b.ToString("x2"));
            }

            return builder.ToString();
        }
    }
}
