// Local trial identity, deliberately separate from Candy Park authentication.
export const TRIAL_VERSION = 'lesson1-student-trial-v1';
export const TRIAL_CLASSES = Object.freeze(Array.from({ length: 16 }, (_, index) => Object.freeze({
  class_id: `g7-${String(index + 1).padStart(2, '0')}`,
  name: `七年级${index + 1}班`
})));
const PREFIX = 'candy-card-game:g7-l01:student-v1';
export function configuredClasses() { return typeof window !== 'undefined' && window.LESSON1_TRIAL_CONFIG?.experimentEnabled ? window.LESSON1_TRIAL_CONFIG.classes || TRIAL_CLASSES.filter(item => ['g7-01', 'g7-06'].includes(item.class_id)).map(item => ({ ...item, name: item.name.replace('七年级', '初一') })) : TRIAL_CLASSES; }

export function createStudentIdentity(classId, name) {
  const classroom = configuredClasses().find(item => item.class_id === classId);
  if (!classroom) throw new Error('请先选择你的班级。');
  const studentName = typeof name === 'string' ? name.normalize('NFC').trim().replace(/\s+/gu, ' ') : '';
  if (!studentName || studentName.length > 32 || !/\p{L}/u.test(studentName)
    || /[<>\p{Cc}\p{Cf}]/u.test(studentName)) throw new Error('请输入真实姓名，长度为1—32个字，请勿只填空格或数字。');
  return {
    schema_version: 1, identity_source: 'local_trial', study_version: TRIAL_VERSION,
    class_id: classroom.class_id, class_name: classroom.name, student_name: studentName
    , ...(typeof window !== 'undefined' && window.LESSON1_TRIAL_CONFIG?.experimentEnabled ? { experiment_version: window.LESSON1_TRIAL_CONFIG.experimentVersion, experiment_round: window.LESSON1_TRIAL_CONFIG.experimentRound } : {})
  };
}

export function studentStorageKey(student, slot = 'session') {
  return `${PREFIX}${student.experiment_version ? ':' + student.experiment_version + ':' + student.experiment_round : ''}:${encodeURIComponent(JSON.stringify([student.class_id, student.student_name]))}:${slot}`;
}

export function belongsToStudent(snapshot, student) {
  const owner = snapshot?.state?.participant;
  return Boolean(owner && student && owner.identity_source === 'local_trial'
    && owner.study_version === TRIAL_VERSION && owner.class_id === student.class_id
    && owner.student_name === student.student_name && owner.experiment_version === student.experiment_version && owner.experiment_round === student.experiment_round);
}
