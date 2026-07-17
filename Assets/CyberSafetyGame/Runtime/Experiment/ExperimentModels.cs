using System;

namespace CyberSafetyGame.Experiment
{
    [Serializable]
    public sealed class QuizQuestion
    {
        public string Id;
        public string Prompt;
        public string[] Choices;
        public int CorrectIndex;
        public string Explanation;
    }

    [Serializable]
    public sealed class GameScenario
    {
        public string Id;
        public string Title;
        public string Situation;
        public string[] Choices;
        public int CorrectIndex;
        public string SuccessText;
        public string HintText;
    }
}

