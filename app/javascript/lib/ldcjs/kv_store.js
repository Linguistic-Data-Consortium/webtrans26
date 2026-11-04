// A key → value store in IndexedDB, for small things kept in this browser
// (preview layers per kit, say). Values are structured-cloned, so plain data
// only — take $state.snapshot of a rune first.

export function kv_store(db_name, store_name){
    const open = () => new Promise((resolve, reject) => {
        const r = indexedDB.open(db_name, 1);
        r.onupgradeneeded = () => r.result.createObjectStore(store_name);
        r.onsuccess = () => resolve(r.result);
        r.onerror = () => reject(r.error);
    });
    const run = (mode, f) => open().then((db) => new Promise((resolve, reject) => {
        const t = db.transaction(store_name, mode);
        const req = f(t.objectStore(store_name));
        t.oncomplete = () => { db.close(); resolve(req?.result); };
        t.onerror = t.onabort = () => { db.close(); reject(t.error); };
    }));
    return {
        get:    (k)    => run('readonly',  (s) => s.get(k)),
        put:    (k, v) => run('readwrite', (s) => s.put(v, k)),
        delete: (k)    => run('readwrite', (s) => s.delete(k)),
        keys:   ()     => run('readonly',  (s) => s.getAllKeys())
    };
}
