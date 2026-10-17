import test from 'node:test';
import assert from 'node:assert/strict';
import { TRIAL_CLASSES, createStudentIdentity, studentStorageKey, belongsToStudent } from '../prototypes/lesson1-card-table/student-session.mjs';

test('lesson 1 trial accepts configured classes 1–16 and normalizes names', () => {
  assert.equal(TRIAL_CLASSES.length, 16);
  const student = createStudentIdentity('g7-16', '  测试学生  ');
  assert.equal(student.class_name, '七年级16班');
  assert.equal(student.student_name, '测试学生');
  assert.equal(student.identity_source, 'local_trial');
  for (const name of ['', '  ', '1234', '<script>', '甲'.repeat(33), '李\u200B明']) {
    assert.throws(() => createStudentIdentity('g7-01', name));
  }
  assert.throws(() => createStudentIdentity('g7-17', '测试学生'));
});

test('lesson 1 ownership never restores other students or unassigned legacy records', () => {
  const one = createStudentIdentity('g7-01', '测试学生');
  const otherClass = createStudentIdentity('g7-16', '测试学生');
  const otherName = createStudentIdentity('g7-01', '其他学生');
  const snapshot = { state: { participant: one } };
  assert.equal(belongsToStudent(snapshot, one), true);
  assert.equal(belongsToStudent(snapshot, otherClass), false);
  assert.equal(belongsToStudent(snapshot, otherName), false);
  assert.equal(belongsToStudent({ state: {} }, one), false);
  assert.equal(new Set([studentStorageKey(one), studentStorageKey(otherClass), studentStorageKey(otherName), studentStorageKey(one, 'backup')]).size, 4);
  assert.equal(studentStorageKey(one), studentStorageKey(createStudentIdentity('g7-01', ' 测试学生 ')));
});
