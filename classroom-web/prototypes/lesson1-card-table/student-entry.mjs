import { configuredClasses, createStudentIdentity } from './student-session.mjs';

export function createStudentEntry(root, onEnter) {
  const dialog = document.createElement('dialog');
  dialog.className = 'student-entry';
  dialog.setAttribute('aria-labelledby', 'student-entry-title');
  dialog.innerHTML = `
    <div class="student-entry-layout">
      <section class="student-entry-story">
        <span class="student-entry-brand">糖果校园 <span>第1课 · 试玩 V1</span></span>
        <div class="student-entry-illustration" aria-hidden="true"><img src="assets/node-device-v1.png" alt=""><span>······</span><img src="assets/announcement-screen-v1.png" alt=""></div>
        <p class="student-entry-eyebrow">欢迎来到网络实验台</p>
        <h1>让网络连起来，<br>让想法动起来。</h1>
        <p class="student-entry-intro">从一次通信开始，用行动卡探索<br>互联网怎样变得更可靠。</p>
        <div class="student-entry-journey"><span>01 认识网络</span><span>02 动手实验</span><span>03 整理发现</span></div>
      </section>
      <section class="student-entry-paper">
        <span class="student-entry-ticket">你的探索通行证</span>
        <h2 id="student-entry-title">准备好，开始探索！</h2>
        <p>选择班级，填好姓名，我们就出发。</p>
        <form class="student-entry-form" novalidate>
          <label for="student-class">你在哪个班级？</label>
          <select id="student-class" name="class_id" required aria-describedby="student-entry-error"><option value="">请选择班级</option></select>
          <label for="student-name">你的姓名</label>
          <input id="student-name" name="student_name" type="text" maxlength="32" autocomplete="off" placeholder="请输入姓名" required aria-describedby="student-entry-error">
          <p id="student-entry-error" role="alert"></p>
          <button class="student-entry-submit" type="submit">进入实验台 <span aria-hidden="true">→</span></button>
        </form>
        <p class="student-entry-note">班级和姓名用于区分试玩记录。<br>进度保存在这台电脑的当前浏览器中。</p>
      </section>
      <p class="student-entry-footer">七年级 · 互联网发展靠创新</p>
    </div>`;
  root.append(dialog);
  if (window.LESSON1_TRIAL_CONFIG?.enabled) dialog.querySelector('.student-entry-note').textContent = '班级和姓名用于区分试玩记录。进入后先确认录制，再开始探索；记录与录像上传至老师的阿里云存储。';
  if (window.LESSON1_TRIAL_CONFIG?.experimentEnabled) {
    const history = document.createElement('a'); history.href = 'legacy-upload.html'; history.textContent = '上传此前试玩的待传记录';
    dialog.querySelector('.student-entry-note').append(document.createElement('br'), history);
  }
  const form = dialog.querySelector('form');
  const classSelect = form.elements.class_id;
  const nameInput = form.elements.student_name;
  const error = dialog.querySelector('#student-entry-error');
  for (const classroom of configuredClasses()) {
    const option = document.createElement('option');
    option.value = classroom.class_id;
    option.textContent = classroom.name;
    classSelect.append(option);
  }
  form.addEventListener('submit', event => {
    event.preventDefault();
    error.textContent = '';
    classSelect.removeAttribute('aria-invalid');
    nameInput.removeAttribute('aria-invalid');
    let student;
    try { student = createStudentIdentity(classSelect.value, nameInput.value); }
    catch (reason) {
      error.textContent = reason.message;
      const invalid = classSelect.value ? nameInput : classSelect;
      invalid.setAttribute('aria-invalid', 'true');
      invalid.focus();
      return;
    }
    dialog.close();
    onEnter(student);
  });
  dialog.addEventListener('cancel', event => event.preventDefault());
  return {
    open() {
      // Shared classroom computers must never silently inherit a previous name.
      form.reset();
      error.textContent = '';
      classSelect.removeAttribute('aria-invalid');
      nameInput.removeAttribute('aria-invalid');
      if (!dialog.open) dialog.showModal();
      classSelect.focus();
    },
    isOpen: () => dialog.open
  };
}
