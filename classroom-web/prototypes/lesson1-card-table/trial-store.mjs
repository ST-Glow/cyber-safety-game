const DATABASE = 'candy-lesson1-trial-recordings-v1';
export function ownerKey(student) { return JSON.stringify([student.class_id, student.student_name]); }

async function transaction(store, mode, operation) {
  const database = await new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE, 1);
    request.onupgradeneeded = () => {
      request.result.createObjectStore('sessions', { keyPath: 'segment_id' });
      const chunks = request.result.createObjectStore('chunks', { keyPath: 'id' });
      chunks.createIndex('segment_id', 'segment_id');
    };
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
  });
  try {
    return await new Promise((resolve, reject) => {
      const tx = database.transaction(store, mode);
      let result;
      const request = operation(tx.objectStore(store));
      request.onsuccess = () => { result = request.result; };
      tx.oncomplete = () => resolve(result);
      tx.onerror = () => reject(tx.error || Error('本机录像暂存失败'));
      tx.onabort = () => reject(tx.error || Error('本机录像暂存被中断'));
    });
  } finally { database.close(); }
}

export const trialStore = {
  save: record => transaction('sessions', 'readwrite', store => store.put(record)),
  all: () => transaction('sessions', 'readonly', store => store.getAll()),
  chunk: (id, sequence, blob) => transaction('chunks', 'readwrite', store => store.put({ id: `${id}:${String(sequence).padStart(8, '0')}`, segment_id: id, sequence, blob })),
  chunks: id => transaction('chunks', 'readonly', store => store.index('segment_id').getAll(id)),
  async recording(record) {
    const chunks = await this.chunks(record.segment_id);
    chunks.sort((a, b) => a.sequence - b.sequence);
    return new Blob(chunks.map(chunk => chunk.blob), { type: record.mime });
  },
  async clearChunks(id) {
    const chunks = await this.chunks(id);
    for (const chunk of chunks) await transaction('chunks', 'readwrite', store => store.delete(chunk.id));
  }
};
