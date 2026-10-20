import { mount, unmount } from 'svelte';
import LocalAudioPicker from '../components/local_audio_picker.svelte';
import { is_local_docid, local_name, register_local_file } from '../lib/ldcjs/local_audio';

// Holds the work page until a local_audio kit has its file, then resolves with
// the page's data, the kit's local://<name> mapped to the file's blob: url in
// the manifest — which is where the waveform and the <audio> element look up
// every kit's audio. needs_local_audio says whether a page has to wait.
//
// `hash` is window.ldc_work_work. Without a kit it carries local_audio_url,
// and the picker's POST there makes the kit and returns the data a normal
// render would have had.
function needs_local_audio(hash){
  return !!hash.local_audio_url || is_local_docid(hash.initt?.source?.uid);
}

function prepare_local_audio(hash){
  const pending = !!hash.local_audio_url;
  const docid = hash.initt?.source?.uid;

  return new Promise((resolve) => {
    const target = document.createElement('div');
    (document.getElementById('main') || document.body).appendChild(target);
    const picker = mount(LocalAudioPicker, {
      target,
      props: {
        local_audio_url: pending ? hash.local_audio_url : null,
        expected_name: pending ? null : local_name(docid),
        expected_size: pending ? null : hash.initt.source.size,
        onready: (file, data) => {
          if(data){
            Object.assign(hash, data);
            delete hash.local_audio_url;
          }
          if(!hash.manifest) hash.manifest = { urls: {} };
          hash.manifest.urls[hash.initt.source.uid] = register_local_file(file);
          unmount(picker);
          target.remove();
          resolve(hash);
        }
      }
    });
  });
}

export { needs_local_audio, prepare_local_audio };
