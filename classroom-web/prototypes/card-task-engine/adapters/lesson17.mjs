import { makeTarget } from '../core.mjs';

function escapeHtml(value) {
  return String(value).replace(/[&<>"]/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[char]));
}

function buildHtml(data) {
  const heading = data.elements.heading.tag === 'h1' ? data.elements.heading.text : '';
  const paragraph = data.elements.intro.tag === 'p' ? data.elements.intro.text : '';
  const section = data.elements.section.tag === 'section';
  return '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>' + escapeHtml(heading || '科技节网页') + '</title></head><body><main>' + (section ? '<section>' : '') + '<h1>' + escapeHtml(heading) + '</h1><p>' + escapeHtml(paragraph) + '</p>' + (section ? '</section>' : '') + '</main></body></html>';
}

const target = (type, id, label, disabledReason = null) => makeTarget(type, id, label, disabledReason);

export const lesson17Adapter = Object.freeze({
  meta: Object.freeze({
    schema_version: 2, course_id: 'g7-internet-application-innovation', curriculum_lesson_id: 'g7-internet-l17',
    task_id: 'html-page-card-table', content_version: 'g7-l17-card-table.2.0',
    task_title: '把科技节素材做成一个网页', evidence_type: 'html_artifact_and_structure', duration_ms: 600000
  }),
  actions: Object.freeze([
    Object.freeze({ id: 'set-heading', title: '设为标题', purpose: '把主题放进 h1' }),
    Object.freeze({ id: 'add-paragraph', title: '添加段落', purpose: '把介绍文字放进 p' }),
    Object.freeze({ id: 'set-section', title: '调整层级', purpose: '把内容放进 section' }),
    Object.freeze({ id: 'preview', title: '预览网页', purpose: '检查最新代码和呈现结果' }),
    Object.freeze({ id: 'publish', title: '发布网页', purpose: '提交最新 HTML 产物' })
  ]),
  initialFeedback: Object.freeze({ tone: 'info', title: '网页编辑台已打开', text: '先把素材放进正确的 HTML 元素，再预览最新结构。' }),

  createInitialState() {
    return {
      elements: {
        heading: { id: 'heading', label: '科技节主题', text: '校园科技节', tag: 'text' },
        intro: { id: 'intro', label: '项目介绍', text: '探索身边的互联网应用', tag: 'text' },
        section: { id: 'section', label: '内容区域', tag: 'fragment' }
      },
      revision: 0,
      preview: { html: '', srcdoc: '', revision: null, stale: true, structure: null },
      published: { html: '', revision: null },
      evidence: [],
      published_flag: false
    };
  },

  legalTargets(state, action) {
    const d = state.data;
    if (action === 'set-heading') return [target('element', 'heading', '科技节主题')];
    if (action === 'add-paragraph') return [target('element', 'intro', '项目介绍')];
    if (action === 'set-section') return [target('element', 'section', '内容区域')];
    if (action === 'preview') {
      const ready = d.elements.heading.tag === 'h1' && d.elements.intro.tag === 'p' && d.elements.section.tag === 'section';
      return [target('preview', 'preview', '网页预览', ready ? null : '先完成 h1 标题、p 段落和 section 层级，再预览。')];
    }
    if (action === 'publish') {
      const ready = d.preview.revision === d.revision && !d.preview.stale && d.preview.html;
      return [target('publish', 'publish', '发布区', ready ? null : '只能发布最新一次预览；如果改过对象，请先重新预览。')];
    }
    return [];
  },

  selectableObjects(state, action) {
    return this.legalTargets(state, action).filter(item => !item.disabledReason).map(item => item.id);
  },

  actionHint(state, action) {
    if (action === 'set-heading') return '选择“科技节主题”素材，再把它设为 h1。';
    if (action === 'add-paragraph') return '选择“项目介绍”素材，再把它设为 p 段落。';
    if (action === 'set-section') return '把标题和正文放进 section，建立清楚的层级。';
    if (action === 'preview') return '完成 h1、p 和 section 后预览当前 HTML。';
    if (action === 'publish') return '发布前必须有与当前 revision 对应的最新预览。';
    return '';
  },

  applyAction(state, action, objectId, targetId) {
    const d = state.data;
    if (action === 'set-heading') {
      if (objectId !== 'heading' || targetId !== 'heading') return { ok: false, code: 'wrong_target', title: '请选择主题素材', text: 'h1 应该承载网页主题。' };
      d.elements.heading.tag = 'h1'; d.revision++;
      d.evidence.push({ type: 'html_structure', element: 'heading', tag: 'h1', revision: d.revision });
      return { ok: true, feedback: { tone: 'success', title: '主题成为 h1', text: '浏览器会把它识别为网页的主要标题。' }, detail: { element: 'heading', tag: 'h1', revision: d.revision } };
    }
    if (action === 'add-paragraph') {
      if (objectId !== 'intro' || targetId !== 'intro') return { ok: false, code: 'wrong_target', title: '请选择介绍素材', text: '介绍文字应该放进 p 段落。' };
      d.elements.intro.tag = 'p'; d.revision++;
      d.evidence.push({ type: 'html_structure', element: 'intro', tag: 'p', revision: d.revision });
      return { ok: true, feedback: { tone: 'success', title: '介绍成为段落', text: '网页结构现在包含主题和正文。' }, detail: { element: 'intro', tag: 'p', revision: d.revision } };
    }
    if (action === 'set-section') {
      if (objectId !== 'section' || targetId !== 'section') return { ok: false, code: 'wrong_target', title: '请选择内容区域', text: '把内容放入 section，才能表达网页层级。' };
      d.elements.section.tag = 'section'; d.revision++;
      d.evidence.push({ type: 'html_structure', element: 'section', tag: 'section', revision: d.revision });
      return { ok: true, feedback: { tone: 'success', title: '层级已建立', text: '标题和正文现在属于同一个内容区域。' }, detail: { element: 'section', tag: 'section', revision: d.revision } };
    }
    if (action === 'preview') {
      if (targetId !== 'preview') return { ok: false, code: 'wrong_target', title: '请选择预览区', text: this.actionHint(state, action) };
      if (d.elements.heading.tag !== 'h1' || d.elements.intro.tag !== 'p' || d.elements.section.tag !== 'section') return { ok: false, code: 'structure_incomplete', title: '网页结构还不完整', text: this.actionHint(state, action) };
      const html = buildHtml(d);
      d.preview = { html, srcdoc: html, revision: d.revision, stale: false, structure: { heading: 'h1', paragraph: 'p', section: 'section' } };
      d.evidence.push({ type: 'preview', html_bytes: html.length, revision: d.revision, srcdoc: true });
      return { ok: true, phase: 'checked', derived: 'preview', feedback: { tone: 'success', title: '最新预览通过', text: '预览版本与当前对象一致，可以继续发布。' }, detail: { html_bytes: html.length, revision: d.revision } };
    }
    if (action === 'publish') {
      if (targetId !== 'publish') return { ok: false, code: 'wrong_target', title: '请选择发布区', text: this.actionHint(state, action) };
      if (d.preview.revision !== d.revision || d.preview.stale || !d.preview.html) return { ok: false, code: 'stale_preview', title: '预览已经过期', text: '改过对象后必须重新预览，才能发布最新 HTML。' };
      d.published = { html: d.preview.html, revision: d.preview.revision }; d.published_flag = true;
      d.evidence.push({ type: 'published_artifact', html_bytes: d.published.html.length, revision: d.published.revision });
      return { ok: true, complete: true, phase: 'completed', derived: 'publish', feedback: { tone: 'success', title: '网页已发布', text: '这次交付包含真实 HTML、标题、段落和清楚的内容层级。' }, detail: { html_bytes: d.published.html.length, revision: d.published.revision } };
    }
    return { ok: false, code: 'unhandled_action', title: '行动没有完成', text: '请重新选择行动卡。' };
  },

  invalidateDerived(state, context) {
    if (['set-heading', 'add-paragraph', 'set-section'].includes(context.action)) {
      state.data.preview.stale = true;
      state.data.published_flag = false;
      state.data.evidence.push({ type: 'derived_invalidated', derived: 'preview', revision: state.data.revision, reason: '课程对象已变化，旧预览不能代表当前结构' });
    }
  },

  artifact(state) {
    if (!state.data.published?.html) return null;
    return { filename: 'tech-fair.html', mime: 'text/html;charset=utf-8', text: state.data.published.html };
  },

  validateState(state) {
    const d = state.data;
    if (!d?.elements?.heading || !d.elements.intro || !d.elements.section || !Number.isInteger(d.revision) || d.revision < 0 || !d.preview || !d.published || typeof d.preview.html !== 'string' || typeof d.preview.srcdoc !== 'string' || typeof d.preview.stale !== 'boolean' || !Array.isArray(d.evidence) || typeof d.published_flag !== 'boolean') return false;
    if (!['text', 'h1'].includes(d.elements.heading.tag) || !['text', 'p'].includes(d.elements.intro.tag) || !['fragment', 'section'].includes(d.elements.section.tag)) return false;
    if (d.preview.revision !== null && (!Number.isInteger(d.preview.revision) || d.preview.revision < 0 || d.preview.revision > d.revision)) return false;
    if (d.published.revision !== null && (!Number.isInteger(d.published.revision) || d.published.revision < 0 || d.published.revision > d.revision)) return false;
    if (d.preview.html !== d.preview.srcdoc) return false;
    if (!d.preview.stale && (d.preview.revision !== d.revision || !d.preview.html)) return false;
    if (d.published_flag && (d.published.revision !== d.revision || !d.published.html)) return false;
    return true;
  },

  validateWin(state) {
    const d = state.data;
    return Boolean(d.published_flag && d.published.revision === d.revision && /<h1>/.test(d.published.html) && /<p>/.test(d.published.html) && /<section>/.test(d.published.html));
  }
});
