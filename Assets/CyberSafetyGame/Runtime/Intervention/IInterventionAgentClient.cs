using System.Collections;

namespace CyberSafetyGame.Intervention
{
    public sealed class InterventionRequest
    {
        public string SessionId;
        public string ParticipantHash;
        public string Trigger;
        public string SceneContext;
        public int WrongAttempts;
        public float IdleSeconds;
    }

    public sealed class InterventionResponse
    {
        public bool Success;
        public string Message;
        public string Provider;
    }

    public interface IInterventionAgentClient
    {
        IEnumerator RequestHint(InterventionRequest request, System.Action<InterventionResponse> onComplete);
    }
}

