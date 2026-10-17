import { makeTarget } from '../core.mjs';

const target = (type, id, label, disabledReason = null) => makeTarget(type, id, label, disabledReason);

function audiencePreview(data) {
  return Object.values(data.objects).map(item => ({ id: item.id, title: item.title, audience: item.audience, shared: item.shared, sensitivity: item.sensitivity, safe_stop: item.held === true || item.removed === true || item.redacted === true }));
}

function riskReasons(data) {
  const reasons = [];
  const { profile, photo, qr } = data.objects;
  if (profile.sensitivity === 'high' && !profile.redacted) reasons.push('姓名和学号必须遮挡，不能公开');
  if (profile.shared && profile.audience === 'public') reasons.push('姓名和学号仍然面向所有人');
  if (photo.shared && photo.audience === 'public' && !photo.replaced) reasons.push('原图仍可能暴露位置和设备信息');
  if (qr.shared && !qr.removed && !qr.held) reasons.push('来源不明二维码仍然可见');
  return reasons;
}

export const lesson27Adapter = Object.freeze({
  meta: Object.freeze({
    schema_version: 2, course_id: 'g7-internet-application-innovation', curriculum_lesson_id: 'g7-internet-l27',
    task_id: 'privacy-protection-card-table', content_version: 'g7-l27-card-table.2.0',
    task_title: '在发布校园活动前保护个人信息', evidence_type: 'privacy_decisions_and_reasons', duration_ms: 300000
  }),
  actions: Object.freeze([
    Object.freeze({ id: 'identify-risk', title: '识别风险', purpose: '先标出敏感字段、受众和来源问题' }),
    Object.freeze({ id: 'redact', title: '遮挡', purpose: '隐藏不必要的个人信息' }),
    Object.freeze({ id: 'remove', title: '移除', purpose: '删除不该公开的素材' }),
    Object.freeze({ id: 'narrow-audience', title: '缩小受众', purpose: '只给需要的人查看' }),
    Object.freeze({ id: 'replace', title: '替换素材', purpose: '去掉照片中的位置元数据' }),
    Object.freeze({ id: 'hold', title: '暂不分享', purpose: '来源不明时先安全停止' }),
    Object.freeze({ id: 'review', title: '检查风险', purpose: '查看受众预览和仍然暴露的信息' }),
    Object.freeze({ id: 'deliver', title: '交付方案', purpose: '提交保护方案或安全停止决定' })
  ]),
  initialFeedback: Object.freeze({ tone: 'info', title: '发布前安全检查', text: '先识别敏感字段、受众范围和来源，再决定是否分享。' }),

  createInitialState() {
    const objects = {
      profile: { id: 'profile', title: '姓名 + 学号', sensitivity: 'high', audience: 'public', redacted: false, shared: true, held: false },
      photo: { id: 'photo', title: '活动原图', sensitivity: 'medium', audience: 'public', metadata: 'location-and-device', replaced: false, shared: true, held: false },
      qr: { id: 'qr', title: '来源不明二维码', sensitivity: 'high', audience: 'public', source: 'unknown', shared: true, removed: false, held: false }
    };
    return {
      objects,
      identified: false,
      risk: { level: 'unknown', reasons: [], revision: null, stale: true },
      audience_preview: audiencePreview({ objects }),
      revision: 0,
      reviewed: false,
      review_revision: null,
      outcome: null,
      submitted: false,
      evidence: []
    };
  },

  legalTargets(state, action) {
    const d = state.data;
    if (action === 'identify-risk') return [target('risk-board', 'risk-board', '风险识别台', d.identified ? '风险已经识别；改动对象后请重新检查。' : null)];
    if (action === 'redact') return [target('privacy-field', 'profile', '姓名 + 学号')];
    if (action === 'remove' || action === 'hold') return [target('privacy-field', 'qr', '来源不明二维码')];
    if (action === 'narrow-audience') return [target('privacy-field', 'profile', '姓名 + 学号', '高敏感字段必须遮挡，不能只靠缩小受众。'), target('privacy-field', 'photo', '活动原图')];
    if (action === 'replace') return [target('privacy-field', 'photo', '活动原图')];
    if (action === 'review') return [target('risk-board', 'risk-board', '风险复核台', d.identified ? null : '先使用“识别风险”标出敏感字段和受众问题。')];
    if (action === 'deliver') return [target('delivery', 'advocacy', '安全交付区', d.reviewed && d.risk.level === 'low' ? null : '先完成风险识别、修正并重新检查，风险降到低后才能交付。')];
    return [];
  },

  selectableObjects(state, action) {
    return this.legalTargets(state, action).filter(item => !item.disabledReason).map(item => item.id);
  },

  actionHint(state, action) {
    if (action === 'identify-risk') return '先标出高敏感字段、公开受众和来源不明内容。';
    if (action === 'redact') return '姓名和学号是高敏感字段，必须遮挡。';
    if (action === 'remove') return '来源不明二维码不应直接公开，移除它。';
    if (action === 'narrow-audience') return '把受众缩小到真正需要查看活动内容的人。';
    if (action === 'replace') return '把可能携带位置和设备信息的原图换成去元数据版本。';
    if (action === 'hold') return '无法确认来源时，暂不分享是安全停止。';
    if (action === 'review') return '查看受众预览，确认每个对象还暴露了什么。';
    if (action === 'deliver') return '检查通过后提交保护方案；安全停止也可以作为结果保存。';
    return '';
  },

  applyAction(state, action, objectId, targetId) {
    const d = state.data;
    if (action === 'identify-risk') {
      if (targetId !== 'risk-board' || objectId !== null) return { ok: false, code: 'wrong_target', title: '请选择风险识别台', text: this.actionHint(state, action) };
      d.identified = true; d.audience_preview = audiencePreview(d); d.risk = { level: 'high', reasons: riskReasons(d), revision: d.revision, stale: false };
      d.evidence.push({ type: 'risk_identified', revision: d.revision, reasons: [...d.risk.reasons], audience_preview: d.audience_preview });
      return { ok: true, phase: 'identified', derived: 'risk-identification', feedback: { tone: 'warn', title: '风险已经标出', text: '姓名学号、公开受众、原图元数据和来源不明二维码都需要进一步处理。' }, detail: { reasons: [...d.risk.reasons] } };
    }
    if (action === 'review') {
      if (targetId !== 'risk-board' || objectId !== null) return { ok: false, code: 'wrong_target', title: '请选择风险复核台', text: this.actionHint(state, action) };
      if (!d.identified) return { ok: false, code: 'risk_not_identified', title: '请先识别风险', text: this.actionHint(state, action) };
      const reasons = riskReasons(d);
      d.risk = { level: reasons.length ? 'high' : 'low', reasons, revision: d.revision, stale: false };
      d.audience_preview = audiencePreview(d); d.reviewed = true; d.review_revision = d.revision;
      d.evidence.push({ type: 'risk_review', level: d.risk.level, reasons: [...reasons], audience_preview: d.audience_preview, revision: d.revision });
      return { ok: true, phase: 'checked', derived: 'risk-review', feedback: { tone: reasons.length ? 'warn' : 'success', title: reasons.length ? '检查发现风险' : '检查通过', text: reasons.length ? reasons.join('；') + '。继续修正后再检查。' : '受众预览已经安全，来源不明内容也没有公开。' }, detail: { level: d.risk.level, reasons } };
    }
    if (action === 'deliver') {
      if (targetId !== 'advocacy' || objectId !== null) return { ok: false, code: 'wrong_target', title: '请选择安全交付区', text: this.actionHint(state, action) };
      if (!d.reviewed || d.review_revision !== d.revision || d.risk.level !== 'low') return { ok: false, code: 'risk_remaining', title: '还有隐私风险', text: '先修正对象并重新检查，再交付。' };
      d.submitted = true;
      d.outcome = d.objects.qr.held && !d.objects.qr.removed ? 'safe_stopped' : 'delivered';
      d.evidence.push({ type: d.outcome === 'safe_stopped' ? 'safe_stop_submitted' : 'advocacy_submitted', reasons: ['最少收集', '控制受众', '来源不明时停止分享'], audience_preview: d.audience_preview });
      return { ok: true, complete: true, phase: d.outcome === 'safe_stopped' ? 'safe_stopped' : 'completed', derived: 'delivery', feedback: { tone: 'success', title: d.outcome === 'safe_stopped' ? '安全停止已记录' : '保护方案已交付', text: d.outcome === 'safe_stopped' ? '来源不明二维码没有公开；这是安全停止，不代表已经发布。' : '必要内容保留，敏感字段和高风险来源都已处理。' }, detail: { outcome: d.outcome, risk_level: d.risk.level } };
    }
    const item = d.objects[objectId];
    if (!item) return { ok: false, code: 'wrong_object', title: '请选择牌桌上的对象', text: this.actionHint(state, action) };
    if (action === 'redact') {
      item.redacted = true; item.shared = false; d.revision++;
      d.evidence.push({ type: 'redacted', object: objectId, reason: '公开内容不需要姓名和学号', revision: d.revision });
      return { ok: true, feedback: { tone: 'success', title: '敏感字段已遮挡', text: '姓名和学号不再随公开内容传播。' }, detail: { object: objectId, revision: d.revision } };
    }
    if (action === 'remove') {
      item.removed = true; item.held = false; item.shared = false; d.revision++;
      d.evidence.push({ type: 'removed', object: objectId, reason: '来源不明', revision: d.revision });
      return { ok: true, feedback: { tone: 'success', title: '来源不明内容已移除', text: '先确认来源，再考虑是否分享，是更安全的选择。' }, detail: { object: objectId, revision: d.revision } };
    }
    if (action === 'hold') {
      item.held = true; item.shared = false; d.revision++;
      d.evidence.push({ type: 'held', object: objectId, reason: '无法确认来源', revision: d.revision });
      return { ok: true, feedback: { tone: 'info', title: '分享已暂停', text: '无法确认来源时，暂停操作可以避免泄露。' }, detail: { object: objectId, revision: d.revision } };
    }
    if (action === 'narrow-audience') {
      if (objectId === 'profile') return { ok: false, code: 'high_sensitivity_requires_redaction', title: '高敏感字段必须遮挡', text: '姓名和学号不能只缩小受众，请使用“遮挡”牌。' };
      item.audience = 'classmates'; d.revision++;
      d.evidence.push({ type: 'audience_narrowed', object: objectId, audience: 'classmates', revision: d.revision });
      return { ok: true, feedback: { tone: 'success', title: '受众已缩小', text: '只有需要查看活动内容的同学可以看到它。' }, detail: { object: objectId, audience: 'classmates', revision: d.revision } };
    }
    if (action === 'replace') {
      item.replaced = true; item.metadata = 'removed'; d.revision++;
      d.evidence.push({ type: 'metadata_removed', object: objectId, reason: '原图可能包含位置和设备信息', revision: d.revision });
      return { ok: true, feedback: { tone: 'success', title: '素材已替换', text: '分享版本不再携带不必要的位置和设备元数据。' }, detail: { object: objectId, revision: d.revision } };
    }
    return { ok: false, code: 'unhandled_action', title: '行动没有完成', text: '请重新选择行动卡。' };
  },

  invalidateDerived(state, context) {
    if (['redact', 'remove', 'hold', 'narrow-audience', 'replace'].includes(context.action)) {
      state.data.reviewed = false; state.data.review_revision = null; state.data.risk.stale = true; state.data.risk.level = 'unknown'; state.data.audience_preview = audiencePreview(state.data);
      state.data.evidence.push({ type: 'derived_invalidated', derived: 'risk-review', revision: state.data.revision, reason: '对象或受众发生变化，旧风险检查不能代表当前状态' });
    }
  },

  validateState(state) {
    const d = state.data;
    const profile = d?.objects?.profile;
    const photo = d?.objects?.photo;
    const qr = d?.objects?.qr;
    if (!profile || !photo || !qr || typeof d.identified !== 'boolean' || !d.risk || !Array.isArray(d.audience_preview) || Number.isInteger(d.revision) === false || d.revision < 0 || !Array.isArray(d.evidence) || typeof d.reviewed !== 'boolean' || (d.outcome !== null && d.outcome !== 'delivered' && d.outcome !== 'safe_stopped') || typeof d.submitted !== 'boolean') return false;
    if (profile.sensitivity !== 'high' || photo.sensitivity !== 'medium' || qr.sensitivity !== 'high') return false;
    if (!['public', 'classmates'].includes(profile.audience) || !['public', 'classmates'].includes(photo.audience) || qr.source !== 'unknown') return false;
    if (typeof profile.redacted !== 'boolean' || typeof profile.shared !== 'boolean' || typeof profile.held !== 'boolean' || typeof photo.replaced !== 'boolean' || typeof photo.shared !== 'boolean' || typeof photo.held !== 'boolean' || typeof qr.removed !== 'boolean' || typeof qr.shared !== 'boolean' || typeof qr.held !== 'boolean') return false;
    if (!['unknown', 'high', 'low'].includes(d.risk.level) || !Array.isArray(d.risk.reasons) || typeof d.risk.stale !== 'boolean' || (d.risk.revision !== null && (!Number.isInteger(d.risk.revision) || d.risk.revision < 0 || d.risk.revision > d.revision))) return false;
    if (!Number.isInteger(d.review_revision) && d.review_revision !== null) return false;
    if (d.reviewed && (d.review_revision !== d.revision || d.risk.stale)) return false;
    if (d.audience_preview.length !== 3 || !d.audience_preview.every(item => item && ['profile', 'photo', 'qr'].includes(item.id))) return false;
    return true;
  },

  validateWin(state) {
    const d = state.data; const { profile, photo, qr } = d.objects;
    const protectedState = profile.redacted && !profile.shared && (photo.replaced || photo.audience === 'classmates') && (!qr.shared && (qr.removed || qr.held));
    return Boolean(d.submitted && d.reviewed && d.review_revision === d.revision && d.risk.level === 'low' && protectedState && (d.outcome === 'delivered' || d.outcome === 'safe_stopped'));
  }
});
