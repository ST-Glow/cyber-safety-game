using System.Collections;
using UnityEngine;

namespace CyberSafetyGame.Intervention
{
    public sealed class MockInterventionAgentClient : IInterventionAgentClient
    {
        public IEnumerator RequestHint(InterventionRequest request, System.Action<InterventionResponse> onComplete)
        {
            yield return new WaitForSecondsRealtime(0.4f);
            onComplete?.Invoke(new InterventionResponse
            {
                Success = true,
                Provider = "mock",
                Message = BuildMessage(request)
            });
        }

        static string BuildMessage(InterventionRequest request)
        {
            if (request.Trigger == "idle_30_seconds")
            {
                return "先观察题目里的信息。有没有真实姓名、学校、地址或验证码？";
            }

            if (request.Trigger == "idle_60_seconds")
            {
                return "可以先排除会泄露个人信息的选项，再选最安全的做法。";
            }

            if (request.Trigger == "idle_90_seconds")
            {
                return "如果还是不确定，可以举手问老师。你也可以从“保护自己”这个角度再看一遍。";
            }

            if (request.Trigger == "repeated_wrong_choice")
            {
                return "换个角度想：哪个选择不会把你的身份、位置或验证码交给别人？";
            }

            return "想一想：这个选择会不会把你的身份、位置或验证码告诉别人？";
        }
    }
}
