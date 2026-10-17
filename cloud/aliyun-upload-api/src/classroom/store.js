"use strict";

// Explicit collections make schema upgrades independent of gameplay resource names.
const COLLECTIONS = Object.freeze(["accounts", "sessions", "lessons", "runs", "progress", "ledger", "inventory", "settings", "attempts"]);
function table(name) {
  if (!COLLECTIONS.includes(name)) throw new Error("unknown_collection");
  return `classroom_${name}`;
}

class SqlStore {
  constructor(driver) { this.driver = driver; }
  async initialize() {
    const engine = this.driver.mysql ? " ENGINE=InnoDB DEFAULT CHARSET=utf8mb4" : "";
    await this.driver.execute("CREATE TABLE IF NOT EXISTS classroom_lock (id INTEGER PRIMARY KEY)" + engine);
    for (const name of COLLECTIONS) {
      await this.driver.execute(`CREATE TABLE IF NOT EXISTS ${table(name)} (id VARCHAR(191) PRIMARY KEY, data TEXT NOT NULL)` + engine);
    }
    await this.driver.execute(this.driver.mysql ? "INSERT IGNORE INTO classroom_lock (id) VALUES (1)" : "INSERT OR IGNORE INTO classroom_lock (id) VALUES (1)");
  }
  async transaction(fn) {
    return this.driver.transaction(async connection => {
      // Classroom-sized workload: one short DB lock gives cross-instance serializable
      // rewards, purchases and lesson switches. Password hashing happens outside it.
      await connection.execute("SELECT id FROM classroom_lock WHERE id=1" + (this.driver.mysql ? " FOR UPDATE" : ""));
      const tx = {
        get: async (name, id) => {
          const rows = await connection.execute(`SELECT data FROM ${table(name)} WHERE id=?`, [id]);
          return rows[0] ? JSON.parse(rows[0].data) : null;
        },
        list: async (name, filters = {}) => {
          const rows = await connection.execute(`SELECT data FROM ${table(name)}`);
          return rows.map(row => JSON.parse(row.data)).filter(item => Object.entries(filters).every(([key, value]) => item[key] === value));
        },
        put: async (name, id, value) => {
          const query = this.driver.mysql
            ? `INSERT INTO ${table(name)} (id,data) VALUES (?,?) ON DUPLICATE KEY UPDATE data=VALUES(data)`
            : `INSERT INTO ${table(name)} (id,data) VALUES (?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data`;
          await connection.execute(query, [id, JSON.stringify(value)]);
        },
        remove: (name, id) => connection.execute(`DELETE FROM ${table(name)} WHERE id=?`, [id]),
      };
      return fn(tx);
    });
  }
  close() { return this.driver.close(); }
}

async function createSqliteStore(filename) {
  const { DatabaseSync } = require("node:sqlite");
  const db = new DatabaseSync(filename);
  db.exec("PRAGMA journal_mode=WAL; PRAGMA busy_timeout=10000");
  const execute = async (sql, args = []) => {
    const stmt = db.prepare(sql);
    return /^SELECT/i.test(sql) ? stmt.all(...args) : stmt.run(...args);
  };
  let queue = Promise.resolve();
  const store = new SqlStore({
    execute, close: () => db.close(),
    transaction(fn) {
      const task = queue.then(async () => {
        db.exec("BEGIN IMMEDIATE");
        try { const result = await fn({ execute }); db.exec("COMMIT"); return result; }
        catch (error) { db.exec("ROLLBACK"); throw error; }
      });
      queue = task.catch(() => {});
      return task;
    },
  });
  await store.initialize();
  return store;
}

async function createMysqlStore(environment = process.env, { migrate = false } = {}) {
  const mysql = require("mysql2/promise");
  if (!environment.CLASSROOM_DB_HOST || !environment.CLASSROOM_DB_NAME || !environment.CLASSROOM_DB_USER) throw new Error("classroom_database_not_configured");
  const pool = mysql.createPool({
    host: environment.CLASSROOM_DB_HOST, port: Number(environment.CLASSROOM_DB_PORT || 3306),
    user: environment.CLASSROOM_DB_USER, password: environment.CLASSROOM_DB_PASSWORD,
    database: environment.CLASSROOM_DB_NAME, charset: "utf8mb4", connectionLimit: 4,
    waitForConnections: true, queueLimit: 120, connectTimeout: 10000,
    ssl: environment.CLASSROOM_DB_CA ? { ca: require("node:fs").readFileSync(environment.CLASSROOM_DB_CA), rejectUnauthorized: true } : { rejectUnauthorized: true },
  });
  const execute = async (sql, args) => (await pool.execute(sql, args))[0];
  const store = new SqlStore({
    mysql: true, execute, close: () => pool.end(),
    async transaction(fn) {
      const connection = await pool.getConnection();
      try {
        await connection.beginTransaction();
        const result = await fn({ execute: async (sql, args) => (await connection.execute(sql, args))[0] });
        await connection.commit();
        return result;
      } catch (error) { await connection.rollback(); throw error; }
      finally { connection.release(); }
    },
  });
  if (migrate) await store.initialize();
  return store;
}

module.exports = { createMysqlStore, createSqliteStore, COLLECTIONS };
