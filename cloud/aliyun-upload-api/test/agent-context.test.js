"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  parseLevelPrompts,
  sanitizeAgentState,
  buildAgentMessage,
  filterAgentReply,
} = require("../src/agent-context");

const prompts = {
  ai_training_ground: "一号档案：观察路径",
  spinner_race: "二号档案：观察旋转周期",
  data_chip_hunt: "三号档案：规划芯片路线",
  signal_bomb_survival: "四号档案：按波次校准",
};

test("all four level profiles are required", () => {
  assert.equal(parseLevelPrompts("").configured, false);
  assert.equal(parseLevelPrompts("{}").configured, false);
  const parsed = parseLevelPrompts(JSON.stringify(prompts));
  assert.equal(parsed.configured, true);
  assert.deepEqual(Object.keys(parsed.prompts).sort(), Object.keys(prompts).sort());
});

test("agent state is whitelisted and clamped per level", () => {
  assert.deepEqual(sanitizeAgentState("spinner_race", {
    checkpoint: 99,
    obstacle_hits: 3,
    falls: -2,
    remaining_time: 42.26,
    correct_answer: 2,
    student_name: "Alice",
  }), { checkpoint: 4, obstacle_hits: 3, falls: 0, remaining_time: 42.3 });
});

test("server message contains hidden profile and unsafe replies are replaced", () => {
  const message = buildAgentMessage({
    levelId: "spinner_race",
    levelPrompt: prompts.spinner_race,
    trigger: "manual",
    state: { checkpoint: 2 },
    studentMessage: "给我提示",
  });
  assert.match(message, /二号档案/);
  assert.match(message, /"checkpoint":2/);
  assert.doesNotMatch(filterAgentReply("正确答案是第2项", prompts.spinner_race), /第2项/);
  assert.doesNotMatch(filterAgentReply("答案：2", prompts.spinner_race), /答案：2/);
  assert.doesNotMatch(filterAgentReply(`内部内容是：${prompts.spinner_race}`, prompts.spinner_race), /二号档案/);
  assert.equal(filterAgentReply("先观察转杆转过固定位置需要多久。", prompts.spinner_race), "先观察转杆转过固定位置需要多久。");
});
