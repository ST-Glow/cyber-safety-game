using System;
using System.IO;
using UnityEngine;

namespace CyberSafetyGame.Telemetry
{
    public sealed class SessionPaths
    {
        public string SessionId { get; }
        public string RootDirectory { get; }
        public string SessionDirectory { get; }
        public string EventLogPath { get; }
        public string SummaryPath { get; }
        public string RecordingPath { get; }
        public string FrameDirectory { get; }
        public string EndedMarkerPath { get; }
        public string UploadedMarkerPath { get; }

        public SessionPaths(string sessionId)
        {
            SessionId = sessionId;
            RootDirectory = Path.Combine(Application.persistentDataPath, "CyberSafetyResearch", "sessions");
            SessionDirectory = Path.Combine(RootDirectory, sessionId);
            EventLogPath = Path.Combine(SessionDirectory, "session.jsonl");
            SummaryPath = Path.Combine(SessionDirectory, "summary.json");
            RecordingPath = Path.Combine(SessionDirectory, "recording.mp4");
            FrameDirectory = Path.Combine(SessionDirectory, "frames");
            EndedMarkerPath = Path.Combine(SessionDirectory, "ended.ok");
            UploadedMarkerPath = Path.Combine(SessionDirectory, "uploaded.ok");
        }

        public static string NewSessionId()
        {
            return DateTime.UtcNow.ToString("yyyyMMdd_HHmmss") + "_" + Guid.NewGuid().ToString("N").Substring(0, 8);
        }

        public void EnsureDirectories()
        {
            Directory.CreateDirectory(RootDirectory);
            Directory.CreateDirectory(SessionDirectory);
            Directory.CreateDirectory(FrameDirectory);
        }
    }
}
