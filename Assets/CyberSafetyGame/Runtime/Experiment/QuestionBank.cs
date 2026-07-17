namespace CyberSafetyGame.Experiment
{
    public static class QuestionBank
    {
        public static readonly QuizQuestion[] PreTest =
        {
            new QuizQuestion
            {
                Id = "pre_private_info",
                Prompt = "下面哪一项最不应该随便告诉陌生网友？",
                Choices = new[] { "喜欢的颜色", "家庭住址", "喜欢的运动" },
                CorrectIndex = 1,
                Explanation = "家庭住址属于重要个人信息，不能随便告诉陌生人。"
            },
            new QuizQuestion
            {
                Id = "pre_code",
                Prompt = "有人说要帮你领奖，向你要短信验证码，你应该怎么做？",
                Choices = new[] { "马上告诉他", "不告诉，并告诉老师或家长", "发给同学看看" },
                CorrectIndex = 1,
                Explanation = "验证码像钥匙，不能告诉别人。"
            },
            new QuizQuestion
            {
                Id = "pre_photo",
                Prompt = "发布照片前，哪件事最重要？",
                Choices = new[] { "看照片有没有暴露学校、门牌等信息", "加很多贴纸", "只看自己好不好看" },
                CorrectIndex = 0,
                Explanation = "照片里可能藏着位置、学校和身份信息。"
            }
        };

        public static readonly QuizQuestion[] PostTest =
        {
            new QuizQuestion
            {
                Id = "post_private_info",
                Prompt = "游戏账号资料里，哪项最好不要公开？",
                Choices = new[] { "昵称", "真实姓名和学校", "喜欢的游戏类型" },
                CorrectIndex = 1,
                Explanation = "真实姓名和学校可能让别人找到你。"
            },
            new QuizQuestion
            {
                Id = "post_code",
                Prompt = "陌生人索要验证码时，最安全的做法是？",
                Choices = new[] { "拒绝并求助老师或家长", "只告诉一次", "换一个验证码告诉他" },
                CorrectIndex = 0,
                Explanation = "验证码不能告诉别人，遇到可疑情况要及时求助。"
            },
            new QuizQuestion
            {
                Id = "post_permission",
                Prompt = "一个小游戏想读取通讯录，你应该先想什么？",
                Choices = new[] { "它为什么需要这个权限", "它图标好不好看", "它有没有音乐" },
                CorrectIndex = 0,
                Explanation = "权限请求要和功能有关，不合理的权限要拒绝。"
            }
        };

        public static readonly GameScenario[] Scenarios =
        {
            new GameScenario
            {
                Id = "profile_card",
                Title = "任务一：整理个人资料卡",
                Situation = "你正在设置游戏资料卡。哪些内容可以公开？哪些内容要隐藏？",
                Choices = new[] { "公开昵称和兴趣，隐藏真实姓名、学校、家庭住址", "全部公开，认识朋友更快", "只隐藏昵称，公开地址方便收礼物" },
                CorrectIndex = 0,
                SuccessText = "很好！昵称和兴趣通常风险较低，真实姓名、学校、住址要保护。",
                HintText = "想一想：哪些信息会让陌生人找到现实中的你？"
            },
            new GameScenario
            {
                Id = "stranger_message",
                Title = "任务二：陌生网友的礼物",
                Situation = "陌生网友说要送你皮肤，但要你发家庭住址和电话。",
                Choices = new[] { "拒绝，不提供信息，并告诉老师或家长", "只发电话，不发地址", "马上发给他，怕错过礼物" },
                CorrectIndex = 0,
                SuccessText = "做得对！真正的奖励不会要求你交出重要个人信息。",
                HintText = "礼物听起来很诱人，但它是不是在交换你的隐私？"
            },
            new GameScenario
            {
                Id = "verification_code",
                Title = "任务三：验证码不是答案",
                Situation = "有人自称客服，说需要你的短信验证码才能帮你解除账号限制。",
                Choices = new[] { "不给验证码，通过官方渠道确认", "给他验证码，请他快点处理", "把验证码发到班级群问问" },
                CorrectIndex = 0,
                SuccessText = "正确！验证码像钥匙，不能交给别人。",
                HintText = "如果验证码像一把钥匙，你会把钥匙交给陌生人吗？"
            },
            new GameScenario
            {
                Id = "photo_share",
                Title = "任务四：发布照片前检查",
                Situation = "你想分享一张照片，但照片里能看到校牌和家门口门牌。",
                Choices = new[] { "先遮挡或换一张不暴露位置的照片", "直接发布，朋友们会点赞", "把照片发给陌生网友帮忙修图" },
                CorrectIndex = 0,
                SuccessText = "太好了！分享前检查照片细节，是保护自己的好习惯。",
                HintText = "照片里除了人物，还可能藏着地点和身份线索。"
            }
        };
    }
}

