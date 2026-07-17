using System.Collections.Generic;
using UnityEngine;

namespace CyberSafetyGame.Telemetry
{
    public sealed class IdleDifficultyDetector : MonoBehaviour
    {
        [SerializeField] float[] idleStageSeconds = { 30f, 60f, 90f };
        float lastActivityTime;
        bool idleEventOpen;
        int nextIdleStageIndex;
        int highestIdleStageReached;

        public bool IsIdleEventOpen => idleEventOpen;
        public float CurrentIdleSeconds => Time.unscaledTime - lastActivityTime;
        public int ActivityVersion { get; private set; }
        public float SecondsUntilFirstIdleStage => idleStageSeconds == null || idleStageSeconds.Length == 0
            ? 0f
            : Mathf.Max(0f, idleStageSeconds[0] - CurrentIdleSeconds);

        public void ResetDetector()
        {
            lastActivityTime = Time.unscaledTime;
            idleEventOpen = false;
            nextIdleStageIndex = 0;
            highestIdleStageReached = 0;
        }

        public void SetIdleStagesForTesting(float first, float second, float third)
        {
            idleStageSeconds = new[] { first, second, third };
            ResetDetector();
        }

        public void NotifyActivity(string activityType)
        {
            ActivityVersion++;
            if (idleEventOpen)
            {
                TelemetryManager.Ensure().LogEvent("idle_or_stuck_recovered", new Dictionary<string, object>
                {
                    ["activity_type"] = activityType,
                    ["idle_duration_seconds"] = Mathf.Round(CurrentIdleSeconds),
                    ["highest_idle_stage_reached"] = highestIdleStageReached
                });
            }

            lastActivityTime = Time.unscaledTime;
            idleEventOpen = false;
            nextIdleStageIndex = 0;
            highestIdleStageReached = 0;
        }

        public string Tick(Vector2 pointerPosition)
        {
            if (idleStageSeconds == null || idleStageSeconds.Length == 0 || nextIdleStageIndex >= idleStageSeconds.Length)
            {
                return null;
            }

            var threshold = idleStageSeconds[nextIdleStageIndex];
            if (CurrentIdleSeconds < threshold)
            {
                return null;
            }

            idleEventOpen = true;
            highestIdleStageReached = nextIdleStageIndex + 1;
            nextIdleStageIndex++;
            var trigger = "idle_" + Mathf.RoundToInt(threshold) + "_seconds";
            TelemetryManager.Ensure().LogEvent("idle_or_stuck_episode", new Dictionary<string, object>
            {
                ["trigger"] = trigger,
                ["stage"] = highestIdleStageReached,
                ["threshold_seconds"] = threshold,
                ["idle_duration_seconds"] = Mathf.Round(CurrentIdleSeconds),
                ["detection_basis"] = "no_effective_game_activity"
            });
            return trigger;
        }
    }
}
