import { writable } from 'svelte/store';
import { get_hlt_promise } from '../aws';
import {  round_to_3_places } from './times';
import { asro } from './asr.svelte';
const asr_store = writable(null);
let asrrp;
// let asro = {};
const asr_items = new Map();

function add_asr_send(path, ldc){
  return add_asr_sendx(path, 'asr', ldc);
}

function add_asr_sendx(path, type, ldc){
  if(!path.startsWith("s3://")){
    if(ldc.obj.source.uid.startsWith("s3://")){
      path = ldc.obj.source.uid;
    }
    else if(ldc.resources.bucket){
      path = `s3://${ldc.resources.bucket}/${path}`;
    }
    else{
      // alert(`can't run asr on ${source_uid}`);
      alert(`can't run asr on ${path}`);
      return null;
    }
  }
  console.log('trying2 asr on ', path);
  return get_hlt_promise(path, type);
}


function split_word_sequence(x, switch_channels, stereo){
  let segments = [];
  x = x.filter( x => x.beg != x.end );
  let last = null;
  let ch_0 = 'ch_0';
  let ch_1 = 'ch_1';
  if(switch_channels){
    ch_0 = 'ch_1';
    ch_1 = 'ch_0';
  }
  for(const y of x){
    if(last && (y.beg == last.end) && (y.speaker == last.speaker)){
      last.text += ` ${y.text}`;
      last.end = y.end;
    }
    else{
      y.channel = stereo && y.speaker != '0' ? ch_1 : ch_0;
      segments.push(y);
      last = y;
    }
  }
  return segments;
}

function xasr_process(x, mapf){
  // if(!asrpv) return;
  xasr_process2(x);
  let asro_i = 0;
  let check = 0;
  let vvsegs = [];
  while(asro_i < asro.items.length){
    check++;
    asro_i = xasr2(asro_i, mapf, vvsegs);
    if(check > 10000) break;
  }
  // sort_segments();
  console.log(vvsegs);
  asro.vvsegs = vvsegs;
  return vvsegs;
  // return asro;  // something about returning this is crashing everything
}

function xasr_process2(x){
  // const x = asrpv;
  console.log('first')
  console.log(x)
  // asro = {};
  asro.segments = [];
        // let y = x.results;
        // for(let j = 0; j < y.items.length; j++){
        //     let z = y.items[j];
        //     let zz = `${z.start_time},${z.end_time},${z.speaker_label}`;
        //     asr_items.set(zz, z);
        //     if(z.type == 'pronunciation'){
        //         if(z.alternatives.length > 1){
        //             asro.error = 'multiple alternatives';
        //             break;
        //         }
        //         z.token = z.alternatives[0].content;
        //     }
        //     if(z.type == 'punctuation'){
        //         z.punc = z.alternatives[0].content;
        //     }
        // }
  asro.items = x;//.results.items;
//   if(debug) console.log(asro);
  if(asro.error) console.error(asro.error);
  else           asro.show = true;
}

// let virtual_iid = 0;
function xasr2(asro_i, mapf, vvsegs){
  let segment = asro.items[asro_i];
    // const segment = {
    //     virtual: true,
    //     iid: `virtual-${virtual_iid++}`,
    //     tokens: [],
    //     text: ''
    // };
    // if(asro_i == asro.items.length){
    //     alert('finished');
    //     return;
    // }
    // let i = 0;
    // for(i = asro_i; i < asro.items.length; i++){
    //     const x = asro.items[i];
    //     if(!segment.beg){
    //         segment.beg = parseFloat(x.start_time);
    //         segment.speaker = x.speaker_label;
    //     }
    //     if(segment.speaker == x.speaker_label){
    //         if(x.type == 'pronunciation'){
    //             if(segment.end && x.start_time - segment.end > 0.25) break;
    //             segment.end = parseFloat(x.end_time);
    //             // segment.tokens.push(x.alternatives);
    //             if(segment.text.length) segment.text += ' ';
    //             segment.text += x.alternatives[0].content;
    //         }
    //         if(x.type == 'punctuation'){
    //             // segment.punc = x.alternatives[0].content;
    //             // asr_items_i++;
    //             // break;
    //             // segment.tokens.push(x.alternatives);
    //             segment.text += x.alternatives[0].content;
    //         }
    //         // asro.i = i;
    //     }
    //     else{
    //         break;
    //     }
    // }
    // // if(segment.tokens.every( x => x.length == 1)){
    // //     segment.text = segment.tokens.map( x => x[0].content ).join(' ');
    // //     if(segment.punc) segment.text += segment.punc;
    // // }

  segment.docid = mapf(segment.channel);
  segment.offset = segment.beg;
  segment.length = round_to_3_places(segment.end - segment.beg);
  segment.transcript = segment.text;
  vvsegs.push(segment);
  return asro_i + 1;
//   return i;
}

export {
    asr_store,
    split_word_sequence,
    add_asr_sendx,
    xasr_process
}
