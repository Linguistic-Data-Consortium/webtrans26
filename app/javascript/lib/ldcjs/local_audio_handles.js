// Remembering a local_audio kit's file across reloads, where the browser can.
//
// A File dies with the page. A FileSystemFileHandle, from showOpenFilePicker,
// doesn't: it can be kept in IndexedDB and asked for the file again later.
// Read access has to be re-granted after a reload — one click, or none once
// the user has chosen "Allow on every visit" — but no file dialog. Chrome and
// Edge have the API; elsewhere can_keep_handles() is false and the page asks
// for the file each time, as before.
//
// Handles are kept per kit, under the kit's uid. Nothing is copied: the handle
// points at the file where it is on disk.

import { local_file_mismatch } from './local_audio';

const DB_NAME = 'local-audio';
const STORE = 'handles';

export function can_keep_handles(){
    return typeof window !== 'undefined' && typeof window.showOpenFilePicker === 'function'
        && typeof indexedDB !== 'undefined';
}

function open_db(){
    return new Promise((resolve, reject) => {
        const r = indexedDB.open(DB_NAME, 1);
        r.onupgradeneeded = () => r.result.createObjectStore(STORE);
        r.onsuccess = () => resolve(r.result);
        r.onerror = () => reject(r.error);
    });
}

function in_store(mode, f){
    return open_db().then((db) => new Promise((resolve, reject) => {
        const t = db.transaction(STORE, mode);
        const req = f(t.objectStore(STORE));
        t.oncomplete = () => { db.close(); resolve(req.result); };
        t.onerror = t.onabort = () => { db.close(); reject(t.error); };
    }));
}

export const handle_store = {
    get:    (uid)         => in_store('readonly',  (s) => s.get(uid)),
    put:    (uid, handle) => in_store('readwrite', (s) => s.put(handle, uid)),
    delete: (uid)         => in_store('readwrite', (s) => s.delete(uid))
};

// Read the file behind a handle and check it's still the kit's. A handle
// that no longer works — the file moved, was deleted, or now differs — is
// forgotten, so the next visit doesn't trip over it again.
export async function read_handle(store, uid, handle, name, size){
    let file;
    try {
        file = await handle.getFile();
    }
    catch(e){
        await store.delete(uid).catch(() => {});
        return { error: `${name} couldn't be opened where it was; it may have been moved or deleted. Choose it again.` };
    }
    const mismatch = local_file_mismatch(file, name, size);
    if(mismatch){
        await store.delete(uid).catch(() => {});
        return { error: `${mismatch} Choose it again.` };
    }
    return { file, handle };
}

// What a kit coming back can do with its saved handle:
//
//   null                   nothing saved (or no storage): ask as usual
//   { file, handle }       readable now and the right file: carry on
//   { handle, ask: true }  needs a click to be allowed again
//   { error }              saved, but no longer usable: ask, and say why
export async function reopen_saved(store, uid, name, size){
    let handle;
    try {
        handle = await store.get(uid);
    }
    catch(e){
        return null;
    }
    if(!handle) return null;
    let permission;
    try {
        permission = await handle.queryPermission({ mode: 'read' });
    }
    catch(e){
        return null;
    }
    if(permission !== 'granted') return { handle, ask: true };
    return read_handle(store, uid, handle, name, size);
}
