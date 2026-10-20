import { mountSvelteComponents } from '../mount.js';
import { activeo, urls } from '../lib/ldcjs/waveform/shared.svelte';
import { set_ldc, init_nodes } from './other';
import { getp, postp } from '../lib/ldcjs/getp';
import { refreshToken, s3url, getSignedUrlPromise, headObject } from '../lib/ldcjs/aws_helper';
import { fromCognitoIdentity } from "@aws-sdk/credential-provider-cognito-identity";
import { CognitoIdentityClient } from "@aws-sdk/client-cognito-identity";
import { TranscribeClient } from "@aws-sdk/client-transcribe";
import { S3Client, GetObjectCommand, HeadObjectCommand, ListObjectsV2Command, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
function init(ldc){
  refreshToken({
    fromCognitoIdentity,
    CognitoIdentityClient,
    TranscribeClient,
    S3Client,
    GetObjectCommand,
    HeadObjectCommand,
    ListObjectsV2Command,
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
    ldc.resources.original_s3_key = obj.source.uid;
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
    const found = s3url(path);
    if(found.bucket) return getSignedUrlPromise(found.bucket, found.key);
    return Promise.resolve(urls[path] || path);
  }

  // Make sure urls[wav] is populated so the downstream set_urls_source /
  // set_urlsx resolvers can turn the wav into a playable URL. s3:// wavs get a
  // signed URL; local/static wavs map to their own path.
  function ensure_audio_url(wav){
    const found = s3url(wav);
    if(found.bucket) return signed_url_for_audio(found.bucket, found.key, urls, wav);
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
function set_urls3(found, k){
    ldc.resources.bucket = found.bucket;
    // const urls = urls;
    return Promise.resolve(
        k.match(/wav$/) ? { wav: k } : not_wav(found, k)
    );
}

    function not_wav(found, k){
        if(found.key.match(/json$/)){
            return get_json(found);
        }
        else{
            return headObject(found.bucket, found.key).then(x => {
                if(x.ContentType == 'audio/wav' && x.Metadata.uid){
                    // return({ wav: x.Metadata.uid });
                    obj.source.meta = x.Metadata.uid;
                    urls[obj.source.meta] = urls[k];
                    activeo.docid = obj.source.meta;
                    return({ wav: k });
                }
            });
        }
    }

    function get_json(found){
        getSignedUrlPromise(found.bucket, found.key)
        .then( getp )
        .then(function(d){

            const o = {};

            // resolve this one in parallel
            if(d.tsv){
                let found = s3url(d.tsv);
                o.transcript = getSignedUrlPromise(found.bucket, found.key)
                .then( getp )
                .then(function(d){
                    return {
                        use_transcript: 'tsv',
                        found_transcript: d
                    };
                });
            }

            // resolve this one in parallel
            if(d.tdf){
                let found = s3url(d.tdf);
                o.transcript = getSignedUrlPromise(found.bucket, found.key)
                .then( getp )
                .then(function(d){
                    return {
                        use_transcript: 'tdf',
                        found_transcript: d
                    };
                });
            }

            // resolve this one in parallel
            if(d.sad_with_aws){
                let found = s3url(d.sad_with_aws);
                o.transcript = getSignedUrlPromise(found.bucket, found.key)
                .then( getp )
                .then(function(d){
                    return {
                        use_transcript: 'sad_with_aws',
                        found_transcript: d
                    };
                });
            }

            if(d.wav){
              o.wav = d.wav;
              return o;
                // active_docid.update( () => d.wav );
                // found = s3url(d.wav);
                // return signed_url_for_audio(found.bucket, found.key, urls, d.wav)
                // .then( (x) => {
                //     o.wav = x.wav;
                //     // o.wav_url = urls[x.wav];
                //     return o;
                // });
            }
            else if(d.channels){
              o.wav = d.channels[0];
              o.channels = d.channels;
            //   o.channels = [
            //   ]
              let p = Promise.resolve();
              for(let i = 1; i < o.channels.length; i++){
                const k = o.channels[i];
                const found = s3url(k);
                p = p.then(() => signed_url_for_audio(found.bucket, found.key, urls, k));
              }
              return p.then(() => o);
            }
            else{
                return o;
            }
            
        })
        .catch( () => alert('error, try refreshing') )
}

function signed_url_for_audio(bucket, key, urls, k) {
  return getSignedUrlPromise(bucket, key)
  .then(function(data){
      urls[k] = data;
  })
  .then( () => { return { wav: k, wav_url: urls[k] } } );
}
function set_urls2(k){
//   const urls = urls;
  if(k.match(/^http/)) urls[k] = k;
  if(!urls[k]) return;
  if(urls[k].substr(0, 2) === 's3'){
      if(urls[k] === 's3'){
          return alert(`no bucket in the audio url for ${k} — the kit's source should be an s3:// url, an http url, or a path`);
      }
      else{
          ldc.resources.bucket = urls[k].replace(/^s3(:\/\/)?/, '').replace(/\/.+/, '');
          const bucket = ldc.resources.bucket;
          let key = k.replace(bucket + '/', '').replace('filename_for_', '');
          if(ldc.resources.original_s3_key) key = ldc.resources.original_s3_key;
          return signed_url_for_audio(bucket, key, urls, k);
          // .then( () => k );
      }
  }
  else{
      return Promise.resolve( { wav: k, wav_url: urls[k] } );
  }
 }
    function set_urlsx(kk){
        const k = kk.replace(/\s+$/, '');
        const found = s3url(k);
        if(found.bucket) {
            return set_urls3x(found, k);
            // .then( (x) => signed_url_for_audio(found.bucket, found.key, urls, x) )
            // .then( () => k );
        }
        else{
            return set_urls2x(k);
        }
    }
    function set_urls3x(found, k){
        ldc.resources.bucket = found.bucket;
        // const urls = urls;
        return Promise.resolve( 
            k.match(/wav$/) ? signed_url_for_audio(found.bucket, found.key, urls, k) : not_wavx(found, k)
        );
    }

    function not_wavx(found, k){
        // alert(found.key)
        if(found.key.match(/json$/)){
            return get_jsonx(found);
        }
        else{
            return headObject(found.bucket, found.key).then(x => {
                if(x.ContentType == 'audio/wav' && x.Metadata.uid){
                    obj.source.meta = x.Metadata.uid;
                    activeo.docid = obj.source.meta;
                    return signed_url_for_audio(found.bucket, found.key, urls, k);
                }
            });
        }
    }

    function get_jsonx(found){
        return getSignedUrlPromise(found.bucket, found.key)
            .then( getp )
            .then(function(d){

                const o = {};

                // resolve this one in parallel
                if(d.tsv){
                    let found = s3url(d.tsv);
                    o.transcript = getSignedUrlPromise(found.bucket, found.key)
                    .then( getp )
                    .then(function(d){
                        return {
                            use_transcript: 'tsv',
                            found_transcript: d
                        };
                    });
                }

                // resolve this one in parallel
                if(d.tdf){
                    let found = s3url(d.tdf);
                    o.transcript = getSignedUrlPromise(found.bucket, found.key)
                    .then( getp )
                    .then(function(d){
                        return {
                            use_transcript: 'tdf',
                            found_transcript: d
                        };
                    });
                }

                // resolve this one in parallel
                if(d.sad_with_aws){
                    let found = s3url(d.sad_with_aws);
                    o.transcript = getSignedUrlPromise(found.bucket, found.key)
                    .then( getp )
                    .then(function(d){
                        return {
                            use_transcript: 'sad_with_aws',
                            found_transcript: d
                        };
                    });
                }

                if(d.wav){
                    // active_docid.update( () => d.wav );
                    activeo.docid = d.wav;
                    found = s3url(d.wav);
                    return signed_url_for_audio(found.bucket, found.key, urls, d.wav)
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

    function set_urls2x(k){
        // const urls = urls;
        if(k.match(/^http/)) urls[k] = k;
        if(!urls[k]) return;
        if(urls[k].substr(0, 2) === 's3'){
            if(urls[k] === 's3'){
                return alert(`no bucket in the audio url for ${k} — the kit's source should be an s3:// url, an http url, or a path`);
            }
            else{
                ldc.resources.bucket = urls[k].replace(/^s3(:\/\/)?/, '').replace(/\/.+/, '');
                const bucket = ldc.resources.bucket;
                let key = k.replace(bucket + '/', '').replace('filename_for_', '');
                if(ldc.resources.original_s3_key) key = ldc.resources.original_s3_key;
                return signed_url_for_audio(bucket, key, urls, k);
                // .then( () => k );
            }
        }
        else{
            return Promise.resolve( { wav: k, wav_url: urls[k] } );
        }
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
