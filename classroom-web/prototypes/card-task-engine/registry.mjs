import { lesson4Reference } from './adapters/lesson4-reference.mjs';
import { lesson9Adapter } from './adapters/lesson9.mjs';
import { lesson17Adapter } from './adapters/lesson17.mjs';
import { lesson27Adapter } from './adapters/lesson27.mjs';
import { lesson1Adapter } from './adapters/lesson1.mjs';

export const CARD_TASK_ADAPTERS = Object.freeze({
  lesson1: lesson1Adapter,
  lesson4: lesson4Reference,
  lesson9: lesson9Adapter,
  lesson17: lesson17Adapter,
  lesson27: lesson27Adapter
});

export function getCardTaskAdapter(id) {
  const adapter = CARD_TASK_ADAPTERS[id];
  if (!adapter) throw new Error(`未知课程适配器：${id}`);
  return adapter;
}
