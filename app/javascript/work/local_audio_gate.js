import { mount, unmount } from 'svelte';
import LocalAudioPicker from '../components/local_audio_picker.svelte';
import { is_local_docid, local_name, register_local_file } from '../lib/ldcjs/local_audio';
import { can_keep_handles, handle_store, reopen_saved } from '../lib/ldcjs/local_audio_handles';

// Holds the work page until a local_audio kit has its file, then resolves with
// the page's data, the kit's local://<name> mapped to the file's blob: url in
// the manifest — which is where the waveform and the <audio> element look up
// every kit's audio. needs_local_audio says whether a page has to wait.
//
// `hash` is window.ldc_work_work. Without a kit it carries local_audio_url,
// and the picker's POST there makes the kit and returns the data a normal
// render would have had.
//
// A kit coming back first tries the handle saved when its file was chosen;
// when the browser still allows reading it, the page carries on with no
// picker at all.
function needs_local_audio(hash){
  return !!hash.local_audio_url || is_local_docid(hash.initt?.source?.uid);
}

function with_file(hash, file){
  if(!hash.manifest) hash.manifest = { urls: {} };
  hash.manifest.urls[hash.initt.source.uid] = register_local_file(file);
  return hash;
}

async function prepare_local_audio(hash){
  const pending = !!hash.local_audio_url;
  const docid = hash.initt?.source?.uid;
  const keep = can_keep_handles();

  let saved = null;
  if(!pending && keep){
    saved = await reopen_saved(handle_store, hash.initt._id, local_name(docid), hash.initt.source.size);
    if(saved?.file) return with_file(hash, saved.file);
  }

  return new Promise((resolve) => {
    const target = document.createElement('div');
    (document.getElementById('main') || document.body).appendChild(target);
    const picker = mount(LocalAudioPicker, {
      target,
      props: {
        local_audio_url: pending ? hash.local_audio_url : null,
        expected_name: pending ? null : local_name(docid),
        expected_size: pending ? null : hash.initt.source.size,
        saved,
        store: handle_store,
        kit_uid: pending ? null : hash.initt._id,
        onready: (file, data, handle) => {
          if(data){
            Object.assign(hash, data);
            delete hash.local_audio_url;
          }
          // Not worth failing the page over: without it the next visit
          // simply asks for the file.
          if(handle && keep) handle_store.put(hash.initt._id, handle).catch((e) => console.warn('local audio handle not saved', e));
          unmount(picker);
          target.remove();
          resolve(with_file(hash, file));
        }
      }
    });
  });
}

export { needs_local_audio, prepare_local_audio };
