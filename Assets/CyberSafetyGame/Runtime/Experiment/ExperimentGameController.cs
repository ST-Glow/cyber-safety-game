using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using CyberSafetyGame.Intervention;
using CyberSafetyGame.Recording;
using CyberSafetyGame.Telemetry;
using CyberSafetyGame.Upload;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem;
using UnityEngine.InputSystem.UI;
using UnityEngine.UI;

namespace CyberSafetyGame.Experiment
{
    public sealed class ExperimentGameController : MonoBehaviour
    {
        static ExperimentGameController instance;

        [Header("Agent")]
        [SerializeField] bool useHttpAgent;
        [SerializeField] string agentEndpoint = "";
        [SerializeField] string agentApiKey = "";
        [SerializeField] bool autoOpenAgentOnIdle = true;
        [SerializeField] bool debugShortIdleAgentTest;

        [Header("Upload")]
        [SerializeField] bool uploadEnabled;
        [SerializeField] string uploadBaseUrl = "";
        [SerializeField] string uploadApiKey = "";

        Canvas canvas;
        Text titleText;
        Text bodyText;
        Text progressText;
        Text hintText;
        Text hudText;
        Text missionBadgeText;
        Text assistantTitleText;
        Text assistantStatusText;
        Text gameTitleText;
        Text gameProgressText;
        Text gameObjectiveText;
        Text floatingFeedbackText;
        InputField codeInput;
        Transform buttonRoot;
        RectTransform missionCardRect;
        RectTransform gameMapRect;
        RectTransform mapFieldRect;
        RectTransform playerRect;
        RectTransform terminalRect;
        RectTransform floatingFeedbackRect;
        readonly List<RectTransform> clueRects = new List<RectTransform>();
        readonly List<RectTransform> riskRects = new List<RectTransform>();
        readonly List<RectTransform> pathRects = new List<RectTransform>();
        Sprite playerArtSprite;
        Sprite assistantArtSprite;
        Sprite clueArtSprite;
        Sprite riskArtSprite;
        Sprite terminalArtSprite;
        IdleDifficultyDetector idleDetector;
        IInterventionAgentClient agentClient;

        int preScore;
        int postScore;
        int currentQuestionIndex;
        int currentScenarioIndex;
        int wrongAttemptsInScenario;
        int totalWrongAttempts;
        int clickCount;
        int levelsCompleted;
        int totalCluesCollected;
        int totalRiskContacts;
        int idleEpisodeCount;
        float totalMoveDistance;
        float lastMoveSampleTime;
        Vector2 lastMoveSamplePosition;
        Vector2 playerMapPosition;
        Vector2 terminalPosition;
        Vector2[] cluePositions = new Vector2[0];
        Vector2[] riskPositions = new Vector2[0];
        bool[] clueCollected = new bool[0];
        bool[] riskContacted = new bool[0];
        bool levelGameplayActive;
        bool terminalOpen;
        bool terminalLockedNotified;
        bool cozeAgentOpenedForCurrentIdle;
        int observedActivityVersion;
        float feedbackHideTime;
        string currentContext = "startup";

        const float playerMoveSpeed = 320f;
        const float collectRadius = 48f;
        const string cozeAgentRelativePath = "coze-agent/agent.html";

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Bootstrap()
        {
            var existing = FindFirstObjectByType<ExperimentGameController>();
            if (existing != null)
            {
                return;
            }

            var gameObject = new GameObject("CyberSafetyExperiment");
            gameObject.AddComponent<ExperimentGameController>();
        }

        void Awake()
        {
            if (instance != null && instance != this)
            {
                Destroy(gameObject);
                return;
            }

            instance = this;
            DontDestroyOnLoad(gameObject);

            TelemetryManager.Ensure();
            RecordingManager.Ensure();
            var uploadManager = UploadManager.Ensure();
            uploadManager.Configure(uploadEnabled, uploadBaseUrl, uploadApiKey);

            idleDetector = gameObject.AddComponent<IdleDifficultyDetector>();
            idleDetector.ResetDetector();
            if (debugShortIdleAgentTest)
            {
                idleDetector.SetIdleStagesForTesting(5f, 10f, 15f);
            }
            agentClient = useHttpAgent
                ? new HttpInterventionAgentClient(agentEndpoint, agentApiKey)
                : new MockInterventionAgentClient();
        }

        void Start()
        {
            if (instance != this)
            {
                return;
            }

            EnsureEventSystem();
            BuildUi();
            RecordingManager.Ensure().StartRecording();
            UploadManager.Ensure().TryUploadAllSessions();
            ShowWelcome();
        }

        void Update()
        {
            var mouse = Mouse.current;

            if (mouse != null && mouse.leftButton.wasPressedThisFrame)
            {
                clickCount++;
                RefreshHud();
                idleDetector.NotifyActivity("pointer_click");
                TelemetryManager.Ensure().LogEvent("pointer_click", new Dictionary<string, object>
                {
                    ["click_count"] = clickCount,
                    ["x"] = mouse.position.ReadValue().x,
                    ["y"] = mouse.position.ReadValue().y,
                    ["context"] = currentContext
                });
            }

            TickLevelMovement();
            AnimateLevelVisuals();
            RefreshIdleStatus();

            var pointerPosition = mouse == null ? Vector2.zero : mouse.position.ReadValue();
            var idleTrigger = idleDetector.Tick(pointerPosition);
            if (observedActivityVersion != idleDetector.ActivityVersion)
            {
                observedActivityVersion = idleDetector.ActivityVersion;
                cozeAgentOpenedForCurrentIdle = false;
            }

            if (!string.IsNullOrEmpty(idleTrigger))
            {
                idleEpisodeCount++;
                StartCoroutine(RequestIntervention(idleTrigger, idleDetector.CurrentIdleSeconds));
            }
        }

        void AnimateLevelVisuals()
        {
            if (!levelGameplayActive)
            {
                return;
            }

            var pulse = 1f + Mathf.Sin(Time.unscaledTime * 5f) * 0.04f;
            var terminalPulse = CountCollectedClues() >= cluePositions.Length ? 1f + Mathf.Sin(Time.unscaledTime * 6f) * 0.08f : 1f;
            if (playerRect != null)
            {
                playerRect.localScale = new Vector3(pulse, pulse, 1f);
            }

            if (terminalRect != null)
            {
                terminalRect.localScale = new Vector3(terminalPulse, terminalPulse, 1f);
            }

            for (var i = 0; i < clueRects.Count; i++)
            {
                if (clueRects[i].gameObject.activeSelf)
                {
                    var bob = Mathf.Sin(Time.unscaledTime * 4f + i) * 4f;
                    clueRects[i].anchoredPosition = cluePositions[i] + new Vector2(0, bob);
                }
            }

            for (var i = 0; i < riskRects.Count; i++)
            {
                if (riskRects[i].gameObject.activeSelf)
                {
                    var wiggle = Mathf.Sin(Time.unscaledTime * 7f + i) * 3f;
                    riskRects[i].anchoredPosition = riskPositions[i] + new Vector2(wiggle, 0);
                }
            }

            if (floatingFeedbackRect != null && floatingFeedbackRect.gameObject.activeSelf && Time.unscaledTime >= feedbackHideTime)
            {
                floatingFeedbackRect.gameObject.SetActive(false);
            }
        }

        void TickLevelMovement()
        {
            if (!levelGameplayActive || terminalOpen || mapFieldRect == null)
            {
                return;
            }

            var keyboard = Keyboard.current;
            if (keyboard == null)
            {
                return;
            }

            var input = Vector2.zero;
            if (keyboard.aKey.isPressed || keyboard.leftArrowKey.isPressed)
            {
                input.x -= 1f;
            }

            if (keyboard.dKey.isPressed || keyboard.rightArrowKey.isPressed)
            {
                input.x += 1f;
            }

            if (keyboard.wKey.isPressed || keyboard.upArrowKey.isPressed)
            {
                input.y += 1f;
            }

            if (keyboard.sKey.isPressed || keyboard.downArrowKey.isPressed)
            {
                input.y -= 1f;
            }

            if (input.sqrMagnitude <= 0.01f)
            {
                return;
            }

            input.Normalize();
            var previous = playerMapPosition;
            var halfSize = GetMapHalfSize();
            playerMapPosition += input * playerMoveSpeed * Time.unscaledDeltaTime;
            playerMapPosition.x = Mathf.Clamp(playerMapPosition.x, -halfSize.x, halfSize.x);
            playerMapPosition.y = Mathf.Clamp(playerMapPosition.y, -halfSize.y, halfSize.y);

            var moved = Vector2.Distance(previous, playerMapPosition);
            if (moved <= 0.01f)
            {
                return;
            }

            totalMoveDistance += moved;
            playerRect.anchoredPosition = playerMapPosition;
            idleDetector.NotifyActivity("player_move");
            CheckLevelInteractions();

            if (Time.unscaledTime - lastMoveSampleTime >= 1f || Vector2.Distance(lastMoveSamplePosition, playerMapPosition) >= 100f)
            {
                lastMoveSampleTime = Time.unscaledTime;
                lastMoveSamplePosition = playerMapPosition;
                TelemetryManager.Ensure().LogEvent("player_move_sample", new Dictionary<string, object>
                {
                    ["scenario_id"] = QuestionBank.Scenarios[currentScenarioIndex].Id,
                    ["level_index"] = currentScenarioIndex + 1,
                    ["x"] = Mathf.Round(playerMapPosition.x),
                    ["y"] = Mathf.Round(playerMapPosition.y),
                    ["total_move_distance"] = Mathf.Round(totalMoveDistance)
                });
            }
        }

        void ShowWelcome()
        {
            currentContext = "welcome";
            SetGameMode(false);
            titleText.text = "个人信息保护实验游戏";
            bodyText.text = "本游戏用于课堂学习研究。正式流程是：先输入匿名编号，再完成 3 道前测题，之后会进入可以用 WASD 或方向键移动的 2D 闯关地图。系统只记录游戏画面和游戏内操作，不记录摄像头、麦克风、桌面或真实姓名。";
            progressText.text = "流程：匿名编号 - 前测 - 2D 闯关任务 - 后测";
            missionBadgeText.text = "新手说明";
            SetHint("想直接看移动玩法，可以点下方“调试：直接进入闯关”。正式实验请点“正式开始”。");
            codeInput.gameObject.SetActive(false);
            RefreshHud();
            SetButtons(new[]
            {
                ButtonSpec.Text("正式开始：输入编号并前测", ShowCodeEntry),
                ButtonSpec.Text("调试：直接进入闯关", DebugStartLevel)
            });
            TelemetryManager.Ensure().LogEvent("consent_notice_shown");
        }

        void DebugStartLevel()
        {
            TelemetryManager.Ensure().LogEvent("debug_skip_to_level");
            TelemetryManager.Ensure().SetParticipantCode("debug");
            currentQuestionIndex = 0;
            preScore = 0;
            StartScenarios();
        }

        void ShowCodeEntry()
        {
            currentContext = "code_entry";
            SetGameMode(false);
            titleText.text = "输入匿名编号";
            bodyText.text = "请输入老师发给你的编号。不要输入姓名、手机号或其他真实身份信息。";
            progressText.text = "第 1 步，共 3 步";
            missionBadgeText.text = "身份登记";
            SetHint("只输入老师发给你的匿名编号，例如 S01。这里不会保存你的真实姓名。");
            codeInput.text = "";
            codeInput.gameObject.SetActive(true);
            RefreshHud();
            SetButtons(new[]
            {
                ButtonSpec.Text("进入前测", () =>
                {
                    var code = string.IsNullOrWhiteSpace(codeInput.text) ? "anonymous" : codeInput.text;
                    TelemetryManager.Ensure().SetParticipantCode(code);
                    codeInput.gameObject.SetActive(false);
                    StartPreTest();
                })
            });
        }

        void StartPreTest()
        {
            currentQuestionIndex = 0;
            preScore = 0;
            ShowQuizQuestion("pretest", QuestionBank.PreTest, currentQuestionIndex);
        }

        void StartPostTest()
        {
            currentQuestionIndex = 0;
            postScore = 0;
            ShowQuizQuestion("posttest", QuestionBank.PostTest, currentQuestionIndex);
        }

        void ShowQuizQuestion(string phase, QuizQuestion[] questions, int index)
        {
            SetGameMode(false);
            currentContext = phase + ":" + questions[index].Id;
            var question = questions[index];
            titleText.text = phase == "pretest" ? "前测" : "后测";
            bodyText.text = question.Prompt;
            missionBadgeText.text = phase == "pretest" ? "护盾能力扫描" : "护盾升级检测";
            progressText.text = (phase == "pretest" ? "第 1 步，共 3 步" : "第 3 步，共 3 步") +
                                "  题目 " + (index + 1) + "/" + questions.Length;
            SetHint("先自己判断。看一看选项里有没有真实姓名、学校、地址、验证码或不合理权限。");
            RefreshHud();

            var specs = new List<ButtonSpec>();
            for (var i = 0; i < question.Choices.Length; i++)
            {
                var choiceIndex = i;
                specs.Add(ButtonSpec.Text(question.Choices[i], () =>
                {
                    var correct = choiceIndex == question.CorrectIndex;
                    if (correct)
                    {
                        if (phase == "pretest")
                        {
                            preScore++;
                        }
                        else
                        {
                            postScore++;
                        }
                    }

                    TelemetryManager.Ensure().LogEvent("quiz_answered", new Dictionary<string, object>
                    {
                        ["phase"] = phase,
                        ["question_id"] = question.Id,
                        ["choice_index"] = choiceIndex,
                        ["correct"] = correct
                    });

                    SetHint((correct ? "判断正确！" : "这个地方可以再想想。") + question.Explanation);
                    RefreshHud();
                    SetButtons(new[] { ButtonSpec.Text("继续", () => AdvanceQuiz(phase, questions)) });
                }));
            }

            SetButtons(specs);
        }

        void AdvanceQuiz(string phase, QuizQuestion[] questions)
        {
            currentQuestionIndex++;
            if (currentQuestionIndex < questions.Length)
            {
                ShowQuizQuestion(phase, questions, currentQuestionIndex);
                return;
            }

            TelemetryManager.Ensure().LogEvent("quiz_completed", new Dictionary<string, object>
            {
                ["phase"] = phase,
                ["score"] = phase == "pretest" ? preScore : postScore,
                ["total"] = questions.Length
            });

            if (phase == "pretest")
            {
                StartScenarios();
            }
            else
            {
                CompleteExperiment();
            }
        }

        void StartScenarios()
        {
            currentScenarioIndex = 0;
            wrongAttemptsInScenario = 0;
            StartCurrentLevel();
        }

        void StartCurrentLevel()
        {
            var scenario = QuestionBank.Scenarios[currentScenarioIndex];
            currentContext = "scenario:" + scenario.Id;
            wrongAttemptsInScenario = 0;
            levelGameplayActive = true;
            terminalOpen = false;
            SetGameMode(true);
            SetupLevelObjects();
            gameTitleText.text = scenario.Title;
            gameObjectiveText.text = "目标：收集 3 个安全线索，解锁终端完成判断。移动：WASD / 方向键。";
            missionBadgeText.text = "任务 " + (currentScenarioIndex + 1) + " / " + QuestionBank.Scenarios.Length;
            gameProgressText.text = "第 2 步，共 3 步  任务 " + (currentScenarioIndex + 1) + "/" + QuestionBank.Scenarios.Length;
            SetHint("用 WASD 或方向键移动。收集 3 个安全线索后，到右上角终端完成判断。");
            RefreshHud();
            ClearButtons();

            TelemetryManager.Ensure().LogEvent("level_started", new Dictionary<string, object>
            {
                ["scenario_id"] = scenario.Id,
                ["level_index"] = currentScenarioIndex + 1,
                ["clue_count"] = cluePositions.Length,
                ["risk_count"] = riskPositions.Length
            });
        }

        void SelectScenarioChoice(GameScenario scenario, int choiceIndex)
        {
            idleDetector.NotifyActivity("scenario_choice");
            var correct = choiceIndex == scenario.CorrectIndex;
            TelemetryManager.Ensure().LogEvent("scenario_choice", new Dictionary<string, object>
            {
                ["scenario_id"] = scenario.Id,
                ["choice_index"] = choiceIndex,
                ["correct"] = correct,
                ["wrong_attempts_before_choice"] = wrongAttemptsInScenario
            });

            if (correct)
            {
                SetHint("护盾增强！" + scenario.SuccessText);
                levelGameplayActive = false;
                levelsCompleted++;
                TelemetryManager.Ensure().LogEvent("level_completed", new Dictionary<string, object>
                {
                    ["scenario_id"] = scenario.Id,
                    ["level_index"] = currentScenarioIndex + 1,
                    ["clues_collected"] = CountCollectedClues(),
                    ["risk_contacts_in_level"] = CountRiskContacts(),
                    ["wrong_attempts_in_scenario"] = wrongAttemptsInScenario
                });
                RefreshHud();
                SetButtons(new[] { ButtonSpec.Text("下一个任务", AdvanceScenario) });
                return;
            }

            wrongAttemptsInScenario++;
            totalWrongAttempts++;
            SetHint("警报：这个选择有风险。" + scenario.HintText);
            terminalOpen = false;
            SetButtons(new[] { ButtonSpec.Text("重新观察地图", ResumeLevelExploration) });
            RefreshHud();
            TelemetryManager.Ensure().LogEvent("wrong_attempt", new Dictionary<string, object>
            {
                ["scenario_id"] = scenario.Id,
                ["wrong_attempts_in_scenario"] = wrongAttemptsInScenario,
                ["total_wrong_attempts"] = totalWrongAttempts
            });

            if (wrongAttemptsInScenario >= 2)
            {
                StartCoroutine(RequestIntervention("repeated_wrong_choice", 0f));
            }
        }

        void AdvanceScenario()
        {
            currentScenarioIndex++;
            if (currentScenarioIndex < QuestionBank.Scenarios.Length)
            {
                StartCurrentLevel();
            }
            else
            {
                SetGameMode(false);
                StartPostTest();
            }
        }

        void SetGameMode(bool active)
        {
            if (!active)
            {
                levelGameplayActive = false;
                terminalOpen = false;
            }

            if (missionCardRect != null)
            {
                missionCardRect.gameObject.SetActive(!active);
            }

            if (gameMapRect != null)
            {
                gameMapRect.gameObject.SetActive(active);
            }
        }

        void SetupLevelObjects()
        {
            var halfSize = GetMapHalfSize();
            playerMapPosition = new Vector2(-halfSize.x * 0.82f, -halfSize.y * 0.58f);
            terminalPosition = new Vector2(halfSize.x * 0.78f, halfSize.y * 0.48f);
            cluePositions = new[]
            {
                new Vector2(-halfSize.x * 0.48f, -halfSize.y * 0.12f),
                new Vector2(-halfSize.x * 0.02f, halfSize.y * 0.36f),
                new Vector2(halfSize.x * 0.44f, -halfSize.y * 0.06f)
            };
            riskPositions = new[]
            {
                new Vector2(-halfSize.x * 0.20f, -halfSize.y * 0.50f),
                new Vector2(halfSize.x * 0.28f, halfSize.y * 0.52f)
            };
            clueCollected = new bool[cluePositions.Length];
            riskContacted = new bool[riskPositions.Length];
            terminalLockedNotified = false;
            lastMoveSampleTime = 0f;
            lastMoveSamplePosition = playerMapPosition;

            playerRect.anchoredPosition = playerMapPosition;
            terminalRect.anchoredPosition = terminalPosition;
            terminalRect.localScale = Vector3.one;
            playerRect.localScale = Vector3.one;
            DrawPath(new[]
            {
                playerMapPosition,
                cluePositions[0],
                cluePositions[1],
                cluePositions[2],
                terminalPosition
            });

            EnsureIconCount(clueRects, cluePositions.Length, "线索", new Color(0.96f, 0.82f, 0.24f), "!", clueArtSprite);
            for (var i = 0; i < clueRects.Count; i++)
            {
                clueRects[i].gameObject.SetActive(i < cluePositions.Length);
                if (i < cluePositions.Length)
                {
                    clueRects[i].anchoredPosition = cluePositions[i];
                }
            }

            EnsureIconCount(riskRects, riskPositions.Length, "风险", new Color(0.86f, 0.22f, 0.2f), "X", riskArtSprite);
            for (var i = 0; i < riskRects.Count; i++)
            {
                riskRects[i].gameObject.SetActive(i < riskPositions.Length);
                if (i < riskPositions.Length)
                {
                    riskRects[i].anchoredPosition = riskPositions[i];
                }
            }

            terminalRect.SetAsLastSibling();
            playerRect.SetAsLastSibling();
            ShowFloatingFeedback("任务开始！收集 3 个安全线索", playerMapPosition + new Vector2(180f, 72f), new Color(0.85f, 1f, 0.84f));
        }

        void CheckLevelInteractions()
        {
            for (var i = 0; i < cluePositions.Length; i++)
            {
                if (clueCollected[i] || Vector2.Distance(playerMapPosition, cluePositions[i]) > collectRadius)
                {
                    continue;
                }

                clueCollected[i] = true;
                totalCluesCollected++;
                clueRects[i].gameObject.SetActive(false);
                idleDetector.NotifyActivity("clue_collected");
                SetHint(BuildClueHint(currentScenarioIndex, i));
                ShowFloatingFeedback("+1 安全线索", cluePositions[i] + new Vector2(0, 58f), new Color(1f, 0.92f, 0.36f));
                RefreshHud();
                TelemetryManager.Ensure().LogEvent("clue_collected", new Dictionary<string, object>
                {
                    ["scenario_id"] = QuestionBank.Scenarios[currentScenarioIndex].Id,
                    ["level_index"] = currentScenarioIndex + 1,
                    ["clue_index"] = i,
                    ["clues_collected"] = CountCollectedClues()
                });
            }

            for (var i = 0; i < riskPositions.Length; i++)
            {
                if (riskContacted[i] || Vector2.Distance(playerMapPosition, riskPositions[i]) > collectRadius)
                {
                    continue;
                }

                riskContacted[i] = true;
                totalRiskContacts++;
                idleDetector.NotifyActivity("risk_contacted");
                SetHint("风险提醒：这里可能会诱导你泄露个人信息。绕开它，继续寻找安全线索。");
                ShowFloatingFeedback("风险提醒", riskPositions[i] + new Vector2(0, 58f), new Color(1f, 0.42f, 0.36f));
                RefreshHud();
                TelemetryManager.Ensure().LogEvent("risk_contacted", new Dictionary<string, object>
                {
                    ["scenario_id"] = QuestionBank.Scenarios[currentScenarioIndex].Id,
                    ["level_index"] = currentScenarioIndex + 1,
                    ["risk_index"] = i,
                    ["total_risk_contacts"] = totalRiskContacts
                });
            }

            if (Vector2.Distance(playerMapPosition, terminalPosition) <= collectRadius)
            {
                TryOpenTerminal();
            }
        }

        void TryOpenTerminal()
        {
            if (terminalOpen)
            {
                return;
            }

            if (CountCollectedClues() < cluePositions.Length)
            {
                SetHint("终端还没有解锁。先收集所有黄色安全线索，再回来完成判断。");
                ShowFloatingFeedback("还差 " + (cluePositions.Length - CountCollectedClues()) + " 个线索", terminalPosition + new Vector2(0, 66f), new Color(0.78f, 0.92f, 1f));
                if (!terminalLockedNotified)
                {
                    terminalLockedNotified = true;
                    TelemetryManager.Ensure().LogEvent("terminal_locked", new Dictionary<string, object>
                    {
                        ["scenario_id"] = QuestionBank.Scenarios[currentScenarioIndex].Id,
                        ["clues_collected"] = CountCollectedClues(),
                        ["clue_count"] = cluePositions.Length
                    });
                }

                return;
            }

            terminalOpen = true;
            idleDetector.NotifyActivity("terminal_opened");
            var scenario = QuestionBank.Scenarios[currentScenarioIndex];
            gameObjectiveText.text = scenario.Situation;
            SetHint("终端已打开。选择最能保护个人信息的行动。");
            ShowFloatingFeedback("终端解锁！", terminalPosition + new Vector2(0, 72f), new Color(0.56f, 1f, 0.84f));
            TelemetryManager.Ensure().LogEvent("terminal_opened", new Dictionary<string, object>
            {
                ["scenario_id"] = scenario.Id,
                ["level_index"] = currentScenarioIndex + 1,
                ["clues_collected"] = CountCollectedClues()
            });

            var specs = new List<ButtonSpec>();
            for (var i = 0; i < scenario.Choices.Length; i++)
            {
                var choiceIndex = i;
                specs.Add(ButtonSpec.Text(scenario.Choices[i], () => SelectScenarioChoice(scenario, choiceIndex)));
            }

            SetButtons(specs);
        }

        void ResumeLevelExploration()
        {
            terminalOpen = false;
            ClearButtons();
            gameObjectiveText.text = "目标：重新观察线索，回到终端选择更安全的行动。";
            SetHint("可以重新移动观察。黄色是安全线索，红色是风险提醒。");
        }

        Vector2 GetMapHalfSize()
        {
            if (mapFieldRect == null)
            {
                return new Vector2(360f, 140f);
            }

            var rect = mapFieldRect.rect;
            return new Vector2(Mathf.Max(160f, rect.width * 0.5f - 34f), Mathf.Max(90f, rect.height * 0.5f - 34f));
        }

        void DrawPath(Vector2[] points)
        {
            var segmentCount = Mathf.Max(0, points.Length - 1);
            EnsurePathCount(segmentCount);
            for (var i = 0; i < pathRects.Count; i++)
            {
                var active = i < segmentCount;
                pathRects[i].gameObject.SetActive(active);
                if (!active)
                {
                    continue;
                }

                var from = points[i];
                var to = points[i + 1];
                var midpoint = (from + to) * 0.5f;
                var delta = to - from;
                pathRects[i].anchoredPosition = midpoint;
                pathRects[i].sizeDelta = new Vector2(delta.magnitude, 10f);
                pathRects[i].localEulerAngles = new Vector3(0, 0, Mathf.Atan2(delta.y, delta.x) * Mathf.Rad2Deg);
                pathRects[i].SetAsFirstSibling();
            }
        }

        void EnsurePathCount(int count)
        {
            while (pathRects.Count < count)
            {
                var segment = new GameObject("PathSegment").AddComponent<Image>();
                segment.transform.SetParent(mapFieldRect, false);
                segment.color = new Color(0.20f, 0.88f, 0.78f, 0.34f);
                var rect = segment.rectTransform;
                rect.anchorMin = new Vector2(0.5f, 0.5f);
                rect.anchorMax = new Vector2(0.5f, 0.5f);
                rect.pivot = new Vector2(0.5f, 0.5f);
                pathRects.Add(rect);
            }
        }

        void ShowFloatingFeedback(string message, Vector2 mapPosition, Color color)
        {
            if (floatingFeedbackRect == null || floatingFeedbackText == null)
            {
                return;
            }

            floatingFeedbackText.text = message;
            floatingFeedbackText.color = color;
            floatingFeedbackRect.anchoredPosition = mapPosition;
            floatingFeedbackRect.gameObject.SetActive(true);
            feedbackHideTime = Time.unscaledTime + 1.4f;
            floatingFeedbackRect.SetAsLastSibling();
        }

        int CountCollectedClues()
        {
            var count = 0;
            for (var i = 0; i < clueCollected.Length; i++)
            {
                if (clueCollected[i])
                {
                    count++;
                }
            }

            return count;
        }

        int CountRiskContacts()
        {
            var count = 0;
            for (var i = 0; i < riskContacted.Length; i++)
            {
                if (riskContacted[i])
                {
                    count++;
                }
            }

            return count;
        }

        string BuildClueHint(int levelIndex, int clueIndex)
        {
            var hints = new[]
            {
                new[] { "线索：昵称可以公开，但真实姓名要保护。", "线索：学校和班级会暴露现实身份。", "线索：家庭住址不能随便给陌生人。" },
                new[] { "线索：免费礼物常常是诱饵。", "线索：电话和住址都属于重要个人信息。", "线索：遇到可疑要求，可以告诉老师或家长。" },
                new[] { "线索：验证码像钥匙，不能告诉别人。", "线索：自称客服也要通过官方渠道确认。", "线索：别把验证码发到群里让更多人看到。" },
                new[] { "线索：照片里可能藏着学校、门牌和位置。", "线索：发布前可以遮挡敏感信息。", "线索：不要把原图发给陌生人处理。" }
            };

            return hints[Mathf.Clamp(levelIndex, 0, hints.Length - 1)][Mathf.Clamp(clueIndex, 0, 2)];
        }

        IEnumerator RequestIntervention(string trigger, float idleSeconds)
        {
            TelemetryManager.Ensure().LogEvent("intervention_requested", new Dictionary<string, object>
            {
                ["trigger"] = trigger,
                ["context"] = currentContext,
                ["wrong_attempts"] = wrongAttemptsInScenario
            });

            if (autoOpenAgentOnIdle && trigger == "idle_30_seconds" && !cozeAgentOpenedForCurrentIdle)
            {
                cozeAgentOpenedForCurrentIdle = true;
                OpenCozeAgent(true, trigger);
                TelemetryManager.Ensure().LogEvent("intervention_response", new Dictionary<string, object>
                {
                    ["trigger"] = trigger,
                    ["provider"] = "coze_external_page",
                    ["success"] = true,
                    ["message_length"] = hintText == null || hintText.text == null ? 0 : hintText.text.Length
                });
                yield break;
            }

            var request = new InterventionRequest
            {
                SessionId = TelemetryManager.Ensure().Paths.SessionId,
                ParticipantHash = TelemetryManager.Ensure().ParticipantHash,
                Trigger = trigger,
                SceneContext = currentContext,
                WrongAttempts = wrongAttemptsInScenario,
                IdleSeconds = idleSeconds
            };

            InterventionResponse response = null;
            yield return agentClient.RequestHint(request, value => response = value);
            if (response == null)
            {
                yield break;
            }

            SetHint(response.Message);
            TelemetryManager.Ensure().LogEvent("intervention_response", new Dictionary<string, object>
            {
                ["trigger"] = trigger,
                ["provider"] = response.Provider,
                ["success"] = response.Success,
                ["message_length"] = response.Message == null ? 0 : response.Message.Length
            });
        }

        void CompleteExperiment()
        {
            currentContext = "complete";
            titleText.text = "完成啦";
            bodyText.text = "你已经完成了个人信息保护挑战。请举手告诉老师。";
            missionBadgeText.text = "训练完成";
            progressText.text = "前测得分：" + preScore + "/" + QuestionBank.PreTest.Length +
                                "  后测得分：" + postScore + "/" + QuestionBank.PostTest.Length;
            SetHint("记住：验证码、地址、学校、真实姓名，都要认真保护。");
            RefreshHud();
            SetButtons(new[]
            {
                ButtonSpec.Text("结束并保存", () =>
                {
                    StartCoroutine(FinishExperimentRoutine());
                })
            });
        }

        IEnumerator FinishExperimentRoutine()
        {
            ClearButtons();
            SetHint("正在保存数据，请稍等。");
            var summary = new Dictionary<string, object>
            {
                ["pre_score"] = preScore,
                ["post_score"] = postScore,
                ["scenario_count"] = QuestionBank.Scenarios.Length,
                ["total_wrong_attempts"] = totalWrongAttempts,
                ["click_count"] = clickCount,
                ["levels_completed"] = levelsCompleted,
                ["total_clues_collected"] = totalCluesCollected,
                ["total_risk_contacts"] = totalRiskContacts,
                ["total_move_distance"] = Mathf.Round(totalMoveDistance),
                ["idle_episode_count"] = idleEpisodeCount
            };

            TelemetryManager.Ensure().EndSession(summary);
            yield return RecordingManager.Ensure().StopRecordingAndWait();
            UploadManager.Ensure().TryUploadAllSessions();
            SetHint("数据已保存。可以等待老师检查。");
        }

        void SetHint(string message)
        {
            hintText.text = message;
            RefreshIdleStatus();
        }

        void RefreshIdleStatus()
        {
            if (assistantStatusText == null || idleDetector == null)
            {
                return;
            }

            if (idleDetector.IsIdleEventOpen)
            {
                assistantStatusText.text = "已触发停滞介入";
                return;
            }

            var remaining = Mathf.CeilToInt(idleDetector.SecondsUntilFirstIdleStage);
            assistantStatusText.text = remaining > 0
                ? "停滞检测：" + remaining + " 秒后自动介入"
                : "正在准备介入";
        }

        void OpenCozeAgent(bool automatic, string trigger)
        {
            var agentPath = Path.Combine(Application.streamingAssetsPath, cozeAgentRelativePath);
            if (!File.Exists(agentPath))
            {
                SetHint("没有找到智能体页面文件。请检查 StreamingAssets/coze-agent/agent.html。");
                TelemetryManager.Ensure().LogEvent("coze_agent_open_failed", new Dictionary<string, object>
                {
                    ["reason"] = "html_missing",
                    ["path"] = agentPath,
                    ["automatic"] = automatic,
                    ["trigger"] = trigger
                });
                return;
            }

            var url = new System.Uri(agentPath).AbsoluteUri;
            var openedByShell = false;
            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = agentPath,
                    UseShellExecute = true
                });
                openedByShell = true;
            }
            catch
            {
                Application.OpenURL(url);
            }

            SetHint("我发现你停住了一会儿，已经尝试打开智能体。如果浏览器没有弹出，请手动打开：D:/大学/游戏项目开发/Assets/StreamingAssets/coze-agent/agent.html");
            TelemetryManager.Ensure().LogEvent("coze_agent_opened", new Dictionary<string, object>
            {
                ["mode"] = openedByShell ? "shell_default_browser" : "application_open_url",
                ["context"] = currentContext,
                ["automatic"] = automatic,
                ["trigger"] = trigger,
                ["resolved_path"] = agentPath,
                ["url"] = url
            });
        }

        void RefreshHud()
        {
            if (hudText == null)
            {
                return;
            }

            var shield = preScore + postScore + Mathf.Max(0, currentScenarioIndex) - totalWrongAttempts;
            if (levelGameplayActive)
            {
                hudText.text = "护盾值 " + Mathf.Max(0, shield) +
                               "    关卡 " + (currentScenarioIndex + 1) + "/" + QuestionBank.Scenarios.Length +
                               "    线索 " + CountCollectedClues() + "/" + cluePositions.Length +
                               "    风险 " + totalRiskContacts;
            }
            else
            {
                hudText.text = "护盾值 " + Mathf.Max(0, shield) + "    点击 " + clickCount + "    错误尝试 " + totalWrongAttempts;
            }
        }

        void LoadArtSprites()
        {
            playerArtSprite = LoadStreamingSprite("player.png");
            assistantArtSprite = LoadStreamingSprite("assistant.png");
            clueArtSprite = LoadStreamingSprite("clue.png");
            riskArtSprite = LoadStreamingSprite("risk.png");
            terminalArtSprite = LoadStreamingSprite("terminal.png");
        }

        static Sprite LoadStreamingSprite(string fileName)
        {
            var path = Path.Combine(Application.streamingAssetsPath, "art", fileName);
            if (!File.Exists(path))
            {
                return null;
            }

            var bytes = File.ReadAllBytes(path);
            var texture = new Texture2D(2, 2, TextureFormat.RGBA32, false);
            if (!texture.LoadImage(bytes))
            {
                Object.Destroy(texture);
                return null;
            }

            texture.wrapMode = TextureWrapMode.Clamp;
            texture.filterMode = FilterMode.Bilinear;
            return Sprite.Create(texture, new Rect(0, 0, texture.width, texture.height), new Vector2(0.5f, 0.5f), 100f);
        }

        void BuildUi()
        {
            LoadArtSprites();
            canvas = new GameObject("Canvas").AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            var scaler = canvas.gameObject.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1280, 720);
            scaler.matchWidthOrHeight = 0.5f;
            canvas.gameObject.AddComponent<GraphicRaycaster>();
            DontDestroyOnLoad(canvas.gameObject);

            var background = CreatePanel(canvas.transform, "Background", new Color(0.06f, 0.10f, 0.16f), Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero);
            var backgroundImage = background.GetComponent<Image>();
            backgroundImage.sprite = CreateCyberBackdropSprite();
            backgroundImage.type = Image.Type.Simple;
            background.offsetMin = Vector2.zero;
            background.offsetMax = Vector2.zero;

            var hud = CreatePanel(canvas.transform, "TopHud", new Color(0.04f, 0.12f, 0.18f, 0.92f), new Vector2(0, 1), new Vector2(1, 1), new Vector2(0.5f, 1), Vector2.zero);
            hud.offsetMin = new Vector2(22, -76);
            hud.offsetMax = new Vector2(-22, -18);
            missionBadgeText = CreateText(hud, "MissionBadge", 22, FontStyle.Bold, TextAnchor.MiddleLeft, Vector2.zero, Vector2.zero, new Color(0.87f, 0.97f, 1f));
            Stretch(missionBadgeText.rectTransform, 24, 6, 520, 52);
            hudText = CreateText(hud, "HudStats", 18, FontStyle.Bold, TextAnchor.MiddleRight, Vector2.zero, Vector2.zero, new Color(0.78f, 0.96f, 0.81f));
            Stretch(hudText.rectTransform, 560, 8, 24, 52);

            var content = new GameObject("PlayArea").AddComponent<RectTransform>();
            content.SetParent(canvas.transform, false);
            content.anchorMin = Vector2.zero;
            content.anchorMax = Vector2.one;
            content.pivot = new Vector2(0.5f, 0.5f);
            content.offsetMin = new Vector2(22, 22);
            content.offsetMax = new Vector2(-22, -92);

            missionCardRect = CreatePanel(content, "MissionCard", new Color(0.95f, 0.98f, 0.95f, 0.96f), new Vector2(0, 0.27f), new Vector2(0.68f, 1), new Vector2(0, 1), Vector2.zero);
            missionCardRect.offsetMin = new Vector2(0, 0);
            missionCardRect.offsetMax = new Vector2(-14, 0);

            titleText = CreateText(missionCardRect, "Title", 32, FontStyle.Bold, TextAnchor.MiddleLeft, Vector2.zero, Vector2.zero, new Color(0.05f, 0.12f, 0.16f));
            Stretch(titleText.rectTransform, 34, 24, 34, 84);
            progressText = CreateText(missionCardRect, "Progress", 16, FontStyle.Bold, TextAnchor.MiddleLeft, Vector2.zero, Vector2.zero, new Color(0.1f, 0.36f, 0.43f));
            Stretch(progressText.rectTransform, 34, 86, 34, 122);
            bodyText = CreateText(missionCardRect, "Body", 24, FontStyle.Bold, TextAnchor.UpperLeft, Vector2.zero, Vector2.zero, new Color(0.06f, 0.13f, 0.16f));
            Stretch(bodyText.rectTransform, 34, 146, 34, 292);
            bodyText.horizontalOverflow = HorizontalWrapMode.Wrap;
            bodyText.verticalOverflow = VerticalWrapMode.Truncate;

            codeInput = CreateInput(missionCardRect, new Vector2(34, -322), new Vector2(360, 54));
            codeInput.gameObject.SetActive(false);

            gameMapRect = CreatePanel(content, "GameMap", new Color(0.07f, 0.16f, 0.20f, 0.96f), new Vector2(0, 0.27f), new Vector2(0.68f, 1), new Vector2(0, 1), Vector2.zero);
            gameMapRect.offsetMin = new Vector2(0, 0);
            gameMapRect.offsetMax = new Vector2(-14, 0);
            gameMapRect.GetComponent<Image>().sprite = CreateMapGridSprite();
            gameTitleText = CreateText(gameMapRect, "GameTitle", 28, FontStyle.Bold, TextAnchor.MiddleLeft, Vector2.zero, Vector2.zero, new Color(0.87f, 1f, 0.95f));
            Stretch(gameTitleText.rectTransform, 24, 12, 24, 54);
            gameProgressText = CreateText(gameMapRect, "GameProgress", 16, FontStyle.Bold, TextAnchor.MiddleLeft, Vector2.zero, Vector2.zero, new Color(0.66f, 0.93f, 0.90f));
            Stretch(gameProgressText.rectTransform, 24, 54, 24, 82);
            gameObjectiveText = CreateText(gameMapRect, "GameObjective", 18, FontStyle.Bold, TextAnchor.UpperLeft, Vector2.zero, Vector2.zero, new Color(0.93f, 1f, 0.90f));
            Stretch(gameObjectiveText.rectTransform, 24, 84, 24, 130);
            gameObjectiveText.horizontalOverflow = HorizontalWrapMode.Wrap;
            mapFieldRect = CreatePanel(gameMapRect, "MapField", new Color(0.04f, 0.10f, 0.13f, 0.84f), Vector2.zero, Vector2.one, new Vector2(0.5f, 0.5f), Vector2.zero);
            Stretch(mapFieldRect, 24, 138, 24, 20);
            mapFieldRect.GetComponent<Image>().sprite = CreateMapGridSprite();
            terminalRect = CreateMapToken(mapFieldRect, "Terminal", new Color(0.20f, 0.58f, 0.95f), "终");
            playerRect = CreateMapToken(mapFieldRect, "Player", new Color(0.26f, 0.92f, 0.70f), "我");
            ApplyTokenSprite(terminalRect, terminalArtSprite, new Vector2(74, 74));
            ApplyTokenSprite(playerRect, playerArtSprite, new Vector2(92, 92));
            floatingFeedbackRect = new GameObject("FloatingFeedback").AddComponent<RectTransform>();
            floatingFeedbackRect.SetParent(mapFieldRect, false);
            floatingFeedbackRect.anchorMin = new Vector2(0.5f, 0.5f);
            floatingFeedbackRect.anchorMax = new Vector2(0.5f, 0.5f);
            floatingFeedbackRect.pivot = new Vector2(0.5f, 0.5f);
            floatingFeedbackRect.sizeDelta = new Vector2(260, 44);
            floatingFeedbackText = CreateText(floatingFeedbackRect, "Text", 20, FontStyle.Bold, TextAnchor.MiddleCenter, Vector2.zero, Vector2.zero, new Color(0.85f, 1f, 0.84f));
            floatingFeedbackText.rectTransform.anchorMin = Vector2.zero;
            floatingFeedbackText.rectTransform.anchorMax = Vector2.one;
            floatingFeedbackText.rectTransform.offsetMin = Vector2.zero;
            floatingFeedbackText.rectTransform.offsetMax = Vector2.zero;
            floatingFeedbackRect.gameObject.SetActive(false);
            gameMapRect.gameObject.SetActive(false);

            var assistantCard = CreatePanel(content, "AssistantCard", new Color(0.08f, 0.22f, 0.28f, 0.94f), new Vector2(0.68f, 0.27f), new Vector2(1, 1), new Vector2(1, 1), Vector2.zero);
            assistantCard.offsetMin = new Vector2(14, 0);
            assistantCard.offsetMax = Vector2.zero;
            var portrait = new GameObject("ShieldPortrait").AddComponent<Image>();
            portrait.transform.SetParent(assistantCard, false);
            portrait.sprite = assistantArtSprite != null ? assistantArtSprite : CreateShieldSprite();
            portrait.color = Color.white;
            portrait.preserveAspect = true;
            portrait.rectTransform.anchorMin = new Vector2(0.5f, 1);
            portrait.rectTransform.anchorMax = new Vector2(0.5f, 1);
            portrait.rectTransform.pivot = new Vector2(0.5f, 1);
            portrait.rectTransform.anchoredPosition = new Vector2(0, -24);
            portrait.rectTransform.sizeDelta = new Vector2(144, 144);
            assistantTitleText = CreateText(assistantCard, "AssistantTitle", 22, FontStyle.Bold, TextAnchor.MiddleCenter, Vector2.zero, Vector2.zero, new Color(0.87f, 0.99f, 1f));
            Stretch(assistantTitleText.rectTransform, 18, 146, 18, 186);
            assistantTitleText.text = "守护助手";
            assistantStatusText = CreateText(assistantCard, "AssistantStatus", 15, FontStyle.Normal, TextAnchor.MiddleCenter, Vector2.zero, Vector2.zero, new Color(0.69f, 0.92f, 0.95f));
            Stretch(assistantStatusText.rectTransform, 18, 184, 18, 218);
            assistantStatusText.text = "待命中";
            var hintBubble = CreatePanel(assistantCard, "HintBubble", new Color(0.91f, 0.98f, 0.95f, 0.96f), new Vector2(0, 0), new Vector2(1, 1), new Vector2(0.5f, 1), Vector2.zero);
            Stretch(hintBubble, 18, 236, 18, 440);
            hintText = CreateText(hintBubble, "Hint", 19, FontStyle.Bold, TextAnchor.UpperLeft, Vector2.zero, Vector2.zero, new Color(0.04f, 0.28f, 0.24f));
            Stretch(hintText.rectTransform, 18, 16, 18, 188);
            hintText.horizontalOverflow = HorizontalWrapMode.Wrap;
            hintText.verticalOverflow = VerticalWrapMode.Truncate;

            var buttons = new GameObject("Buttons").AddComponent<RectTransform>();
            buttons.SetParent(content, false);
            buttons.anchorMin = new Vector2(0, 0);
            buttons.anchorMax = new Vector2(1, 0);
            buttons.pivot = new Vector2(0.5f, 0);
            buttons.anchoredPosition = Vector2.zero;
            buttons.sizeDelta = new Vector2(0, 168);
            var layout = buttons.gameObject.AddComponent<VerticalLayoutGroup>();
            layout.spacing = 12;
            layout.padding = new RectOffset(0, 0, 0, 0);
            layout.childControlHeight = true;
            layout.childControlWidth = true;
            layout.childForceExpandHeight = false;
            layout.childForceExpandWidth = true;
            buttonRoot = buttons;
        }

        static void Stretch(RectTransform rect, float left, float top, float right, float bottom)
        {
            rect.anchorMin = new Vector2(0, 1);
            rect.anchorMax = new Vector2(1, 1);
            rect.pivot = new Vector2(0.5f, 1);
            rect.offsetMin = new Vector2(left, -bottom);
            rect.offsetMax = new Vector2(-right, -top);
        }

        static RectTransform CreatePanel(Transform parent, string name, Color color, Vector2 anchorMin, Vector2 anchorMax, Vector2 pivot, Vector2 size)
        {
            var image = new GameObject(name).AddComponent<Image>();
            image.color = color;
            var rect = image.rectTransform;
            rect.SetParent(parent, false);
            rect.anchorMin = anchorMin;
            rect.anchorMax = anchorMax;
            rect.pivot = pivot;
            rect.sizeDelta = size;
            return rect;
        }

        static Text CreateText(Transform parent, string name, int size, FontStyle style, TextAnchor anchor, Vector2 position, Vector2 dimensions, Color color)
        {
            var text = new GameObject(name).AddComponent<Text>();
            text.transform.SetParent(parent, false);
            text.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            text.fontSize = size;
            text.resizeTextForBestFit = true;
            text.resizeTextMinSize = 12;
            text.resizeTextMaxSize = size;
            text.fontStyle = style;
            text.alignment = anchor;
            text.color = color;
            var rect = text.rectTransform;
            rect.anchorMin = new Vector2(0, 1);
            rect.anchorMax = new Vector2(0, 1);
            rect.pivot = new Vector2(0, 1);
            rect.anchoredPosition = position;
            rect.sizeDelta = dimensions;
            return text;
        }

        static InputField CreateInput(Transform parent, Vector2 position, Vector2 dimensions)
        {
            var image = new GameObject("AnonymousCodeInput").AddComponent<Image>();
            image.transform.SetParent(parent, false);
            image.color = Color.white;
            var rect = image.rectTransform;
            rect.anchorMin = new Vector2(0, 1);
            rect.anchorMax = new Vector2(0, 1);
            rect.pivot = new Vector2(0, 1);
            rect.anchoredPosition = position;
            rect.sizeDelta = dimensions;

            var input = image.gameObject.AddComponent<InputField>();
            var text = CreateText(image.transform, "Text", 24, FontStyle.Normal, TextAnchor.MiddleLeft, new Vector2(14, -8), new Vector2(dimensions.x - 28, dimensions.y - 16), Color.black);
            var placeholder = CreateText(image.transform, "Placeholder", 22, FontStyle.Italic, TextAnchor.MiddleLeft, new Vector2(14, -8), new Vector2(dimensions.x - 28, dimensions.y - 16), new Color(0.45f, 0.45f, 0.45f));
            placeholder.text = "例如：S01";
            input.textComponent = text;
            input.placeholder = placeholder;
            return input;
        }

        void SetButtons(IEnumerable<ButtonSpec> specs)
        {
            ClearButtons();
            foreach (var spec in specs)
            {
                var button = CreateButton(buttonRoot, spec.Label, spec.Action);
                button.gameObject.SetActive(true);
            }
        }

        void ClearButtons()
        {
            for (var i = buttonRoot.childCount - 1; i >= 0; i--)
            {
                Destroy(buttonRoot.GetChild(i).gameObject);
            }
        }

        void EnsureIconCount(List<RectTransform> icons, int count, string prefix, Color color, string label, Sprite sprite)
        {
            while (icons.Count < count)
            {
                var token = CreateMapToken(mapFieldRect, prefix + icons.Count, color, label);
                ApplyTokenSprite(token, sprite, new Vector2(62, 62));
                icons.Add(token);
            }
        }

        static Button CreateButton(Transform parent, string label, UnityEngine.Events.UnityAction action)
        {
            var image = new GameObject("Button").AddComponent<Image>();
            image.transform.SetParent(parent, false);
            image.color = new Color(0.09f, 0.42f, 0.52f);
            var layout = image.gameObject.AddComponent<LayoutElement>();
            layout.minHeight = 48;
            layout.preferredHeight = 54;
            var button = image.gameObject.AddComponent<Button>();
            button.onClick.AddListener(action);
            var colors = button.colors;
            colors.normalColor = new Color(0.09f, 0.42f, 0.52f);
            colors.highlightedColor = new Color(0.13f, 0.55f, 0.65f);
            colors.pressedColor = new Color(0.07f, 0.30f, 0.38f);
            colors.selectedColor = colors.highlightedColor;
            colors.colorMultiplier = 1f;
            button.colors = colors;

            var text = CreateText(image.transform, "Label", 20, FontStyle.Bold, TextAnchor.MiddleCenter, Vector2.zero, new Vector2(760, 42), new Color(0.97f, 1f, 0.98f));
            text.rectTransform.anchorMin = Vector2.zero;
            text.rectTransform.anchorMax = Vector2.one;
            text.rectTransform.offsetMin = new Vector2(12, 4);
            text.rectTransform.offsetMax = new Vector2(-12, -4);
            text.text = label;
            text.horizontalOverflow = HorizontalWrapMode.Wrap;
            return button;
        }

        static RectTransform CreateMapToken(Transform parent, string name, Color color, string label)
        {
            var image = new GameObject(name).AddComponent<Image>();
            image.transform.SetParent(parent, false);
            image.color = color;
            var rect = image.rectTransform;
            rect.anchorMin = new Vector2(0.5f, 0.5f);
            rect.anchorMax = new Vector2(0.5f, 0.5f);
            rect.pivot = new Vector2(0.5f, 0.5f);
            rect.sizeDelta = new Vector2(44, 44);

            var text = CreateText(image.transform, "Label", 19, FontStyle.Bold, TextAnchor.MiddleCenter, Vector2.zero, Vector2.zero, Color.white);
            text.rectTransform.anchorMin = Vector2.zero;
            text.rectTransform.anchorMax = Vector2.one;
            text.rectTransform.offsetMin = Vector2.zero;
            text.rectTransform.offsetMax = Vector2.zero;
            text.text = label;
            return rect;
        }

        static void ApplyTokenSprite(RectTransform token, Sprite sprite, Vector2 size)
        {
            if (token == null || sprite == null)
            {
                return;
            }

            var image = token.GetComponent<Image>();
            image.sprite = sprite;
            image.color = Color.white;
            image.preserveAspect = true;
            token.sizeDelta = size;

            var label = token.GetComponentInChildren<Text>();
            if (label != null)
            {
                label.text = "";
            }
        }

        static Sprite CreateMapGridSprite()
        {
            const int size = 128;
            var texture = new Texture2D(size, size, TextureFormat.RGBA32, false);
            for (var y = 0; y < size; y++)
            {
                for (var x = 0; x < size; x++)
                {
                    var color = new Color(0.07f, 0.16f, 0.18f, 1f);
                    if ((x / 32 + y / 32) % 2 == 0)
                    {
                        color = new Color(0.08f, 0.20f, 0.22f, 1f);
                    }

                    if (x % 32 == 0 || y % 32 == 0)
                    {
                        color = new Color(0.14f, 0.40f, 0.38f, 1f);
                    }

                    if (Mathf.Abs((x - y) % 64) < 2)
                    {
                        color = new Color(0.12f, 0.34f, 0.40f, 1f);
                    }

                    if ((x + y) % 53 == 0)
                    {
                        color = new Color(0.34f, 0.72f, 0.66f, 1f);
                    }

                    texture.SetPixel(x, y, color);
                }
            }

            texture.Apply();
            texture.wrapMode = TextureWrapMode.Repeat;
            texture.filterMode = FilterMode.Point;
            return Sprite.Create(texture, new Rect(0, 0, size, size), new Vector2(0.5f, 0.5f), 100f);
        }

        static Sprite CreateCyberBackdropSprite()
        {
            const int width = 256;
            const int height = 128;
            var texture = new Texture2D(width, height, TextureFormat.RGBA32, false);
            for (var y = 0; y < height; y++)
            {
                var t = y / (float)(height - 1);
                var baseColor = Color.Lerp(new Color(0.03f, 0.09f, 0.14f), new Color(0.08f, 0.28f, 0.34f), t);
                for (var x = 0; x < width; x++)
                {
                    var color = baseColor;
                    if (y < 36 && (x % 28 < 18))
                    {
                        color = new Color(0.04f, 0.15f, 0.2f);
                    }

                    if (y < 36 && x % 28 == 8 && y % 10 < 4)
                    {
                        color = new Color(0.24f, 0.78f, 0.74f, 0.9f);
                    }

                    if (y < 18 && (x + y) % 18 == 0)
                    {
                        color = new Color(0.28f, 0.62f, 0.58f, 0.8f);
                    }

                    texture.SetPixel(x, y, color);
                }
            }

            texture.Apply();
            texture.wrapMode = TextureWrapMode.Clamp;
            texture.filterMode = FilterMode.Bilinear;
            return Sprite.Create(texture, new Rect(0, 0, width, height), new Vector2(0.5f, 0.5f));
        }

        static Sprite CreateShieldSprite()
        {
            const int size = 128;
            var texture = new Texture2D(size, size, TextureFormat.RGBA32, false);
            var center = new Vector2(size * 0.5f, size * 0.48f);
            for (var y = 0; y < size; y++)
            {
                for (var x = 0; x < size; x++)
                {
                    var dx = Mathf.Abs(x - center.x) / 46f;
                    var top = y > 24 && y < 82 && dx < 1f;
                    var bottomWidth = Mathf.Lerp(0.05f, 1f, Mathf.InverseLerp(16, 82, y));
                    var bottom = y >= 82 && y < 118 && dx < bottomWidth;
                    var inside = top || bottom;
                    var border = inside && (dx > 0.82f || y < 30 || y > 110);
                    var color = new Color(0, 0, 0, 0);
                    if (inside)
                    {
                        color = border ? new Color(0.84f, 1f, 0.92f, 1f) : new Color(0.1f, 0.72f, 0.65f, 1f);
                    }

                    if (inside && x > 58 && x < 70 && y > 42 && y < 92)
                    {
                        color = new Color(0.95f, 1f, 0.82f, 1f);
                    }

                    if (inside && y > 61 && y < 73 && x > 40 && x < 88)
                    {
                        color = new Color(0.95f, 1f, 0.82f, 1f);
                    }

                    texture.SetPixel(x, y, color);
                }
            }

            texture.Apply();
            texture.wrapMode = TextureWrapMode.Clamp;
            texture.filterMode = FilterMode.Bilinear;
            return Sprite.Create(texture, new Rect(0, 0, size, size), new Vector2(0.5f, 0.5f));
        }

        static void EnsureEventSystem()
        {
            if (FindFirstObjectByType<EventSystem>() != null)
            {
                return;
            }

            var eventSystem = new GameObject("EventSystem");
            eventSystem.AddComponent<EventSystem>();
            eventSystem.AddComponent<InputSystemUIInputModule>();
            DontDestroyOnLoad(eventSystem);
        }

        readonly struct ButtonSpec
        {
            public readonly string Label;
            public readonly UnityEngine.Events.UnityAction Action;

            ButtonSpec(string label, UnityEngine.Events.UnityAction action)
            {
                Label = label;
                Action = action;
            }

            public static ButtonSpec Text(string label, UnityEngine.Events.UnityAction action)
            {
                return new ButtonSpec(label, action);
            }
        }
    }
}
