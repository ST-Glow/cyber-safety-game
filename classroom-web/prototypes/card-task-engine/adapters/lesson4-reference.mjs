// 第4课仍由 lesson4-card-table/model.mjs 作为已验证的垂直切片实现。
// 这里仅提供注册表描述，避免在抽取底座时复制一份会漂移的课程规则。
import { ACTIONS, AREAS, LINKS, META, PACKETS } from '../../lesson4-card-table/config.mjs';

export const lesson4Reference = Object.freeze({
  id: META.task_id,
  curriculum_lesson_id: META.curriculum_lesson_id,
  implementation: 'classroom-web/prototypes/lesson4-card-table/model.mjs',
  layout: 'network-control-room',
  actions: ACTIONS.map(action => action.id),
  objects: PACKETS.map(packet => packet.id),
  areas: Object.keys(AREAS),
  links: Object.keys(LINKS),
  evidence: ['packet_paths', 'arrival_order', 'reassembly_draft', 'delivery_result']
});
