import { mountSvelteComponents } from '../mount.js';
import { activeo, urls } from '../lib/ldcjs/waveform/shared.svelte';
import { set_ldc, init_nodes } from './other';
import { getp, postp } from '../lib/ldcjs/getp';
import { refreshToken } from '../lib/ldcjs/aws_helper';
import { resolve_s3_source, signed_url_for, head_source, sign_into, resolve_audio } from '../lib/ldcjs/s3_source';
import { fromCognitoIdentity } from "@aws-sdk/credential-provider-cognito-identity";
import { CognitoIdentityClient } from "@aws-sdk/client-cognito-identity";
import { TranscribeClient } from "@aws-sdk/client-transcribe";
import { S3Client, GetObjectCommand, HeadObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
function init(ldc){
  refreshToken({
    fromCognitoIdentity,
    CognitoIdentityClient,
    TranscribeClient,
    S3Client,
    GetObjectCommand,
    HeadObjectCommand,
    PutObjectCommand,
    getSignedUrl
});
  const obj = ldc.obj2;
  set_ldc(ldc);
  if(obj.nodes) init_nodes(); // a payload with a tree in it, whatever tool this is
  if(!ldc.resources.urls) ldc.resources.urls = urls; //ldc.resources.manifest.urls;
  Object.entries(ldc.resources.manifest.urls).forEach(([k, v]) => urls[k] = v);
//   if(obj.xlass_def_id == 3) obj.source.uid = '';
  // keys can be 24 or 28?
  if(obj.source.uid.match(/^\w{24,28}$/)){
    // alert(Object.keys(ldc.resources.urls))
    if(obj.filename == obj.source.uid) obj.filename = `filename_for_${obj.source.uid}`;
    // active_docid.update( () => obj.filename );
    activeo.docid = obj.filename;
    urls[obj.filename] = urls[obj.source.uid];
    console.log(JSON.stringify(ldc.resources))
    delete urls[obj.source.uid];
  }
  else{
    set_urls(obj.source.uid).then((o) => {
      ldc.maino = o;
      if(o){
        if(obj.source.meta){
            activeo.docid = obj.source.meta;
        }
        else{
            activeo.docid = o.wav;
        }
      }
    });
  }
  function set_urls(kk){
    const k = kk.replace(/\s+$/, '');
    // JSON wrapper source: resolve it to { wav | channels, transcript }. Works for
    // both s3:// wrappers (signed here) and local/static ones served from public/
    // (the transcription REPL harness). Any other source keeps the original
    // passthrough — the Waveform's set_urls prop signs the audio URL downstream.
    if(k.match(/\.json$/)) return get_json_wrapper(k);
    return Promise.resolve({ wav: k });
}

  // Resolve a wrapper-referenced path (audio or transcript) to a fetchable URL.
  // s3:// paths are signed; local/manifest paths are used as-is.
  function resolve_url(path){
    if(resolve_s3_source(path).bucket) return signed_url_for(path);
    return Promise.resolve(urls[path] || path);
  }

  // Make sure urls[wav] is populated so the downstream set_urls_source /
  // set_urlsx resolvers can turn the wav into a playable URL. s3:// wavs get a
  // signed URL; local/static wavs map to their own path.
  function ensure_audio_url(wav){
    if(resolve_s3_source(wav).bucket) return sign_into(urls, wav, wav);
    if(!urls[wav]) urls[wav] = wav;
    return Promise.resolve({ wav: wav, wav_url: urls[wav] });
  }

  // Fetch a JSON wrapper { wav | channels, tsv | tdf | sad_with_aws } and turn it
  // into the { wav, [channels], transcript } object the rest of init/maino expects.
  // The transcript is left as a lazily-resolved promise consumed by
  // UploadTranscriptDialog.create_transcript_retrieve2 when import_transcript_auto.
  function get_json_wrapper(k){
    return resolve_url(k).then(getp).then(function(d){
      const o = {};
      const tkind = d.tsv ? 'tsv' : d.tdf ? 'tdf' : d.sad_with_aws ? 'sad_with_aws' : null;
      if(tkind){
        o.transcript = resolve_url(d[tkind]).then(getp).then(function(td){
          return { use_transcript: tkind, found_transcript: td };
        });
      }
      if(d.wav){
        o.wav = d.wav;
        return ensure_audio_url(d.wav).then(() => o);
      }
      if(d.channels){
        o.wav = d.channels[0];
        o.channels = d.channels;
        let p = Promise.resolve();
        for(const ch of d.channels) p = p.then(() => ensure_audio_url(ch));
        return p.then(() => o);
      }
      return o;
    })
    .catch(() => { alert('error loading transcript wrapper, try refreshing'); });
  }
// set_urls3, not_wav, get_json and set_urls2 were here: an older copy of the
// set_urlsx family below that nothing called, including one of the three
// pasted blocks that derived a bucket from one string and a key from another.
// Resolution now goes through lib/ldcjs/s3_source.js.
    // The Waveform's set_urls: manifest entry k to { wav, wav_url }. An s3 .wav
    // is signed; an s3 .json wrapper and an s3 object with a uid in its metadata
    // are looked into first; anything else goes to resolve_audio, which is the
    // same rule every other site uses.
    function set_urlsx(kk){
        const k = kk.replace(/\s+$/, '');
        const found = resolve_s3_source(k);
        if(found.bucket) {
            return Promise.resolve(
                k.match(/wav$/) ? sign_into(urls, k, k) : not_wavx(found, k)
            );
        }
        else{
            return resolve_audio(k, urls);
        }
    }

    function not_wavx(found, k){
        if(found.key.match(/json$/)){
            return get_jsonx(k);
        }
        else{
            return head_source(k).then(x => {
                if(x.ContentType == 'audio/wav' && x.Metadata.uid){
                    obj.source.meta = x.Metadata.uid;
                    activeo.docid = obj.source.meta;
                    return sign_into(urls, k, k);
                }
            });
        }
    }

    // A transcript named by the wrapper, resolved by the same rule as the
    // wrapper itself — under per-project S3 its paths are project-relative too.
    function wrapper_transcript(src, use_transcript){
        return signed_url_for(src)
        .then( getp )
        .then( (d) => ({ use_transcript, found_transcript: d }) );
    }

    function get_jsonx(k){
        return signed_url_for(k)
            .then( getp )
            .then(function(d){

                const o = {};

                // each resolved in parallel; the last one present wins, as before
                if(d.tsv) o.transcript = wrapper_transcript(d.tsv, 'tsv');
                if(d.tdf) o.transcript = wrapper_transcript(d.tdf, 'tdf');
                if(d.sad_with_aws) o.transcript = wrapper_transcript(d.sad_with_aws, 'sad_with_aws');

                if(d.wav){
                    activeo.docid = d.wav;
                    return sign_into(urls, d.wav, d.wav)
                    .then( (x) => {
                        o.wav = x.wav;
                        o.wav_url = urls[x.wav];
                        return o;
                    });
                }
                else{
                    return o;
                }

            })
            .catch( () => alert('error, try refreshing') )
    }

    ldc.set_urlsx = set_urlsx;
    // ns.main = mount(Main, {
    //   target: $('.view')[0],
    //   props: h
    // });
    mountSvelteComponents()


    // return p;
}

export { init }
