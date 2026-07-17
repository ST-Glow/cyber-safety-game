using System.Collections;
using CyberSafetyGame.Telemetry;
using UnityEngine;

namespace CyberSafetyGame.Recording
{
    public sealed class RecordingManager : MonoBehaviour
    {
        [SerializeField] bool recordGameView = true;
        [SerializeField] int fps = 8;
        [SerializeField] int maxWidth = 1280;

        IRuntimeScreenRecorder recorder;
        Coroutine captureCoroutine;

        public bool IsRecording => recorder != null && recorder.IsRecording;

        public static RecordingManager Ensure()
        {
            var existing = FindFirstObjectByType<RecordingManager>();
            if (existing != null)
            {
                return existing;
            }

            var gameObject = new GameObject("RecordingManager");
            DontDestroyOnLoad(gameObject);
            return gameObject.AddComponent<RecordingManager>();
        }

        public void StartRecording()
        {
            if (!recordGameView || IsRecording)
            {
                return;
            }

            StartCoroutine(StartRecordingRoutine());
        }

        IEnumerator StartRecordingRoutine()
        {
            var paths = TelemetryManager.Ensure().Paths;
            var width = Mathf.Min(Screen.width, maxWidth);
            var height = Mathf.RoundToInt(Screen.height * (width / (float)Mathf.Max(1, Screen.width)));

            recorder = new FfmpegPipeScreenRecorder();
            yield return recorder.StartRecording(paths.RecordingPath, width, height, fps);

            if (!recorder.IsRecording)
            {
                recorder = new FrameSequenceRecorder();
                yield return recorder.StartRecording(paths.RecordingPath, width, height, Mathf.Min(fps, 4));
            }

            if (recorder is FfmpegPipeScreenRecorder ffmpegRecorder)
            {
                captureCoroutine = StartCoroutine(ffmpegRecorder.CaptureLoop());
            }
            else if (recorder is FrameSequenceRecorder frameRecorder)
            {
                captureCoroutine = StartCoroutine(frameRecorder.CaptureLoop());
            }
        }

        public void StopRecording()
        {
            if (recorder == null)
            {
                return;
            }

            StartCoroutine(StopRecordingAndWait());
        }

        public IEnumerator StopRecordingAndWait()
        {
            if (recorder == null)
            {
                yield break;
            }

            if (captureCoroutine != null)
            {
                StopCoroutine(captureCoroutine);
                captureCoroutine = null;
            }

            yield return recorder.StopRecording();
            recorder = null;
        }

        void OnApplicationQuit()
        {
            StopRecording();
        }
    }
}
