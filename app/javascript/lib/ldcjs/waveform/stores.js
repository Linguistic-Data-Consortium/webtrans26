// The transcript itself moved to transcript.svelte.js, where it's runes rather
// than stores. What's left is either a keystroke/mouse bus — where a store's
// synchronous, fires-every-time behaviour is the point — or settings, whose
// persistence in settings.js is plain JS and subscribes to changes.
import { writable } from 'svelte/store'
import { default_modifier } from './bindings';
const settings = writable({ modifier: default_modifier });
const spectrogram_settings = writable({});
const active_docid = writable(null);
const state = writable(null);
const mouse = writable(null);
const key = writable(null);
const speaker = writable(null);
export {
    settings,
    spectrogram_settings,
    active_docid,
    state,
    mouse,
    key,
    speaker
}
