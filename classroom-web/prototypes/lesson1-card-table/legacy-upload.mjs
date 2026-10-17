import { createStudentEntry } from './student-entry.mjs';
import { createTrialStudy } from './trial-study.mjs';
import { trialStore, ownerKey } from './trial-store.mjs';
window.LESSON1_TRIAL_CONFIG = Object.freeze({ ...window.LESSON1_TRIAL_CONFIG, experimentEnabled: false });
const root = document.querySelector('#app');
const message = document.createElement('p'); message.className = 'legacy-upload-message'; message.style.cssText = 'padding:28px;background:#fff8e8;color:#213c4e;font-size:22px'; root.append(message);
const study = createTrialStudy(root, { getSnapshot: () => ({}), onBack: () => entry.open() });
const entry = createStudentEntry(root, async student => {
  const records = (await trialStore.all()).filter(record => record.owner === ownerKey(student) && !['complete', 'cancelled'].includes(record.status));
  message.textContent = records.length ? '请完成当前浏览器中保存的历史记录上传。上传后可重新选择其他学生。' : '这位学生在当前浏览器没有待上传记录。请使用原来试玩的电脑和浏览器核对。';
  try { await study.uploadPending(student); } catch { message.textContent = '历史记录暂时无法读取，请保留当前浏览器数据并联系老师。'; }
  const button = document.createElement('button'); button.type = 'button'; button.textContent = '重新选择学生'; button.onclick = () => entry.open(); message.append(document.createElement('br'), button);
});
entry.open();
