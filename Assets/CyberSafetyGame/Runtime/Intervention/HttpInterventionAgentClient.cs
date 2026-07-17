using System.Collections;
using System.Collections.Generic;
using System.Text;
using CyberSafetyGame.Telemetry;
using UnityEngine;
using UnityEngine.Networking;

namespace CyberSafetyGame.Intervention
{
    public sealed class HttpInterventionAgentClient : IInterventionAgentClient
    {
        readonly string endpoint;
        readonly string apiKey;

        public HttpInterventionAgentClient(string endpoint, string apiKey)
        {
            this.endpoint = endpoint;
            this.apiKey = apiKey;
        }

        public IEnumerator RequestHint(InterventionRequest request, System.Action<InterventionResponse> onComplete)
        {
            if (string.IsNullOrWhiteSpace(endpoint))
            {
                yield return new MockInterventionAgentClient().RequestHint(request, onComplete);
                yield break;
            }

            var body = TelemetryJson.Serialize(new Dictionary<string, object>
            {
                ["session_id"] = request.SessionId,
                ["participant_hash"] = request.ParticipantHash,
                ["trigger"] = request.Trigger,
                ["scene_context"] = request.SceneContext,
                ["wrong_attempts"] = request.WrongAttempts,
                ["idle_seconds"] = request.IdleSeconds,
                ["tone"] = "short_encouraging_for_grade_5_6_do_not_give_direct_answer"
            });

            using var webRequest = new UnityWebRequest(endpoint, "POST");
            webRequest.uploadHandler = new UploadHandlerRaw(Encoding.UTF8.GetBytes(body));
            webRequest.downloadHandler = new DownloadHandlerBuffer();
            webRequest.SetRequestHeader("Content-Type", "application/json");
            if (!string.IsNullOrWhiteSpace(apiKey))
            {
                webRequest.SetRequestHeader("X-Research-Api-Key", apiKey);
            }

            yield return webRequest.SendWebRequest();

            if (webRequest.result != UnityWebRequest.Result.Success)
            {
                onComplete?.Invoke(new InterventionResponse
                {
                    Success = false,
                    Provider = "http",
                    Message = "我再给你一个小提示：先找出这里有没有个人信息。"
                });
                yield break;
            }

            var message = string.IsNullOrWhiteSpace(webRequest.downloadHandler.text)
                ? "观察一下，哪一项最能保护你的个人信息？"
                : webRequest.downloadHandler.text;

            onComplete?.Invoke(new InterventionResponse
            {
                Success = true,
                Provider = "http",
                Message = message
            });
        }
    }
}

