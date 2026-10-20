import { assign_menu_keys } from './menu_keys';
import {
    set_ldc,
    done,
    skip,
    broken,
    add_audio_to_list,
    add_audio_to_listp,
    add_audio_to_listq,
    update_node,
    split_segment_at_cursor,
    merge_with_following_segment,
    add_cb,
    delete_all,
    delete_all2,
    delete_section,
    check_for_submit,
    change_value,
    change_value_src,
    add_section,
    delete_transcript_line_based_on_segment_id,
    save_redaction
} from './modification1';
import { round_to_3_places } from './times';
import { refreshToken, getSignedUrlPromise, putObject, s3url } from '../aws_helper';
import { getp, getp_wav, postp, getp_simple } from '../getp';
import { ParseB } from './parse_b';
import { get_hlt_promise } from '../aws';
import { hlt_endpoint } from '../service_config';
import { get } from 'svelte/store';
import { input_map as inputmap, modifier_event_key, default_modifier } from './bindings';
import { settings } from './stores';

function docid2channel(x, docids){
    if(docids.length > 1){
        for(let i = 0; i < docids.length; i++){
            if(x == docids[i]) return i;
        }
    }
    if(x.match(/[:_]B$/)){
        return 1;
    }
    else if(x.match(/[:_]C$/)){
        return 2;
    }
    else if(x.match(/[:_]D$/)){
        return 3;
    }
    return 0;
}

function add_save_asr(json, docid, f){
    setTimeout( () => {
        add_timestamps2(json, docid, f)
        // console.log(json)
        // add_cb( () => {
            // window.location.reload();
            // add_cb(cb);
        // });
    }, 100 );
}

function add_timestamps2(data, docid, f){
    var j, len, span, x;
    for (j = 0, len = data.length; j < len; j++) {
        x = data[j];
        span = {
            offset: x.beg,
            length: round_to_3_places(x.end - x.beg),
            transcript: x.text,
            speaker: x.speaker
        };
        // console.log(span);
        // console.log('wave')
        // console.log(ns.waveform)
        add_audio_to_list(docid, null, null, span);
    }
    add_audio_to_listq(f);
}

function signed_url_for_audio(bucket, key, urls, k) {
    return getSignedUrlPromise(bucket, key)
    .then(function(data){
        urls[k] = data;
    })
    .then( () => { return { wav: k, wav_url: urls[k] } } );
}

function set_urls_source(k, ldc){
    const found = s3url(k);
    if(found.bucket) {
        return set_urls3_source(found, k, ldc);
        // .then( (x) => signed_url_for_audio(found.bucket, found.key, urls, x) )
        // .then( () => k );
    }
    else{
        const found2 = s3url(ldc.resources.urls[k]);
        if(found2.bucket){
            return set_urls3_source(found2, k, ldc);
        }
        else{
            return set_urls2_source(k, ldc);
        }
    }
}
function set_urls3_source(found, k, ldc){
    ldc.resources.bucket = found.bucket;
    return Promise.resolve(
        signed_url_for_audio(found.bucket, found.key, ldc.resources.urls, k)
        .catch( () => alert('error, try refreshing') )
    );
}

function set_urls2_source(k, ldc){
    const urls = ldc.resources.urls;
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

function get_audio_buffer_info(k, ldc){
    // # url = "/audio_files2?audio_id=#{audio.id}&info=true"
    // # get url, (data) ->
    // #     data
    // # url = "#{bucket}#{audio.id}.wav"
    return new Promise( (resolve, reject) => {
        // ldc_nodes.wait_for_root_key_key( "resources", "urls", () => {
        set_urls_source(k, ldc).then( (x) => {
            const url = x.wav_url;
            // urls = $('.Root').data().resources.urls
            // const urls = ldc.resources.urls;
            // const url = urls[audio.uid || audio.id];
            // console.log(JSON.stringify(urls));
            // console.log(urls);
            // console.log(audio);
            getp_wav(url, 0, 8191).then( (header) => {
                // # url = "#{bucket}#{audio.id}.json"
                console.log("header ", header);
                // const url = urls[audio.uid || audio.id]
                console.log(url);
                const ret = {};
                const parser = new ParseB('name');
                ret.info = parser.parse(header);
                console.log(ret);
                getp_wav(url, 0, ret.info.dataOffset-1).then( (data) => {
                    console.log("data2 ",  data);
                    ret.header = data;
                    resolve(ret);
                } );
            } );
        } );
    } );
}

function fill_speakerm(speakerm, short, speakers){
    let i = 0;
    // unnecessary?  maybe just short[i] unneeded
    for(const [x, v] of speakers){
        if (x && !speakerm[x]) {
            speakerm[x] = short[i];
        }
        i++;
    }
}

// Lists the names in `speakerm` on the menu and binds a letter to each.
//
// The letters come from assign_menu_keys, which steps over the ones the menu
// has already claimed for itself — N for "new", R for "replace". This used to
// count straight through, so the fourteenth name took N and overwrote "new
// section" in the keymap.
function fill_speakers(speakerm, short, speakers, kb){
    for(const { name, key } of assign_menu_keys(Object.keys(speakerm), kb.map, short)){
        // A name with no letter left to give it is still worth listing — it
        // says the section exists. Reaching it means typing it under "new".
        speakers.push([ key ?? '', name ]);
        if(key === null) continue;
        kb.map[key] = `setf_${key}`;
        kb.delegate[kb.map[key]] = () => name;
    }
}

function three_way_split_on_selection(input){
    return three_way_split(input.value, input.selectionStart, input.selectionEnd);
}

function three_way_split(value, a, b){
    const x = value.substring(0, a);
    const y = value.substring(a, b);
    const z = value.substring(b);
    return({ x, y, z });
}

function get_promises(set_sp, set_op, o){
    const base = hlt_endpoint();
    let service_promise;
    let output_promise;
    let interval;
    const get_service_promise = (o) => {
        service_promise = postp(base + '/promises', o);
        set_sp(service_promise);
        service_promise.then( (o) => {
            interval = setInterval( () => get_output_promise(o), 1000);
        } );
    };
    const get_output_promise = (o) => {
        service_promise = getp(base + '/promises/' + o.id);
        set_sp(service_promise);
        service_promise.then( (o) => {
            if(o.status == 'resolved'){
                clearInterval(interval);
                output_promise = getp(o.data[0].output).then( (x) => JSON.parse(x) );
                set_op(output_promise);
                console.log('done');
            }
            else{
                console.log('waiting');
                console.log(o)
            }
        } );
    };
    get_service_promise(o);
}

function add_sad(k, ldc){
    // w.keyboards.services.reset();
    // return
    // $.each window.ldc.resources.manifest.urls, (k, v) ->
    // $('.ChannelA').after('<div class="waiting">Waiting</div>');
    // a = [ [ 1.0, 2.0], [3.0, 4.0], [ 5.0, 6.0] ]
    // f2 a
    // return
    // if(k.match(/\.json$/)) k = k.replace(/json$/, 'wav');
    if(ldc.resources.bucket){
        const bucket = ldc.resources.bucket;
        let key = k; //.replace('10s.wav', '5s.wav')
        if(key.startsWith("s3://")){
            const idx = key.indexOf(bucket) + bucket.length + 1;
            key = key.substring(idx);
        }
        return getSignedUrlPromise(bucket, key);
    }
}
    //     return getSignedUrlPromise(bucket, key).then(function(fn) {
    //       // inputs: ["/NIEUW02/promises/sad_in/#{w.wave_docid}.wav"]
    //       // inputs: ["/NIEUW02/Armstrong_moon_cut.wav"]
    //       return ldc_services.sad(o, function(data) {
    //         return add_timestamps(data);
    //       });
    //     });
    //   }
    // }

async function add_sad_send(x, ldc){
    let p = add_sad(x, ldc);
    let p2 = p.then( (url) => {
        const o = { type: 'sad', data: { audio: url } };
        // if(x.startsWith('s3://')) return get_hlt_promise(x, 'sad').then(check_channels);
        return hlt_sad(o, function(data) {
            return check_channels(data);
        } );
    } );
    return p2;
}

function check_channels(data) {
    const o = {
        ch1: [],
        ch2: []
    }
    // new format
    // or coincidentally old and short
    if(data.length === 1 || data.length === 2){
        o.ch1 = data[0];
        // check for old format
        if(o.ch1.length === 3 && typeof o.ch1[2] === 'string'){
            o.ch1 = data;
        }
        else if(data.length === 2){
            o.ch2 = data[1];
        }
    }
    else{
        o.ch1 = data;
    }
    o.ch1 = o.ch1.filter( x => x[2] == 'speech' );
    o.ch2 = o.ch2.filter( x => x[2] == 'speech' );
    return o;
}

async function hlt_sad(o, ff){
    const endpoint = hlt_endpoint();
    const data = await getp_simple(endpoint);
    const promises = data.promises;
    const create_promises_url = `${endpoint}${promises.create_promise.uri}`;
    // url = url.replace ':4567', '' if external
    return postp(create_promises_url, o).then( function(oo) {
        var f, url2;
        console.log('HERE');
        console.log(oo);
        url2 = oo.promiseStatusUrl;
        url2 = `${create_promises_url}/${oo.id}`;
        f = function() {
            return getp(url2).then( function(data) {
                var url3;
                console.log("HERE");
                console.log(data);
                window.$('.waiting').append('*');
                if (data.status === 'resolved') {
                    console.log('DONE');
                    window.$('.waiting').remove();
                    url3 = data.data[0].output;
                    console.log(url3);
                    return getp(url3).then( function(data) {
                        return ff(data);
                    });
                } else {
                    return setTimeout(function() {
                        return f();
                    }, 1000);
                }
            });
        };
        return f();
    });
}

function fmap_helper(e, map){
    // The single active modifier key is user-configurable in the settings
    // dialog. Only that one modifier flips us into the `.control` submap.
    const mod_id = get(settings).modifier || default_modifier;
    if(e[modifier_event_key(mod_id)]) map = map.control;
    if(!map) map = {};
    const v = map[e.key];
    if(v){
        // Bindings may be a bare action name (string) or { action, desc, group, ... }.
        return typeof v === 'string' ? v : v.action;
    }
    else{
        console.log('no binding 1');
        console.log(e);
        return false;
    }
}

function fmap_helper_suserf(e, x, suserf){
  const userf = fmap_helper(e, inputmap);
  if(userf){
    suserf( { detail: { userf: userf, e: e } }, x);
  }
}

function wait_for_f1_f2(f1, f2) {
  if (f1() === true) {
    return f2();
  } else {
    return setTimeout(function() {
      return wait_for_f1_f2(f1, f2);
    }, 100);
  }
}

function wait_for(sel, f2) {
  var f1;
  f1 = function() {
    return document.querySelectorAll(sel).length !== 0;
  };
  return wait_for_f1_f2(f1, f2);
}

function display_docid(x){
  if(!x) return '';
  return x.replace(/((s3|https?):)?[^:]+:?\//, '');
}

function pad(x){
  let s = String(x);
  let dec = s.split('.')[1];
  if(!dec){
    s += '.000';
  }
  else{
    if(dec.length == 2) s += '0';
    if(dec.length == 1) s += '00';
  }
  return s;
}

export {
    docid2channel,
    add_save_asr,
    signed_url_for_audio,
    set_urls_source,
    get_audio_buffer_info,
    fill_speakerm,
    fill_speakers,
    three_way_split_on_selection,
    three_way_split,
    add_sad_send,
    get_promises,
    fmap_helper,
    fmap_helper_suserf,
    wait_for,
    wait_for_f1_f2,
    display_docid,
    pad
}

