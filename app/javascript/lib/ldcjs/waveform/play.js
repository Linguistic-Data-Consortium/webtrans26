import { event } from '../../../guides/guide';
import { play_src_with_audio_id as plays } from '../audio/main';
import { stop_playing as sp } from '../audio/main';
let playing = false;
const redactions = new Map();
const local_redactions = new Map();
let current_redaction = null;

function redaction_docid(docid){
  return docid.replace(/.+\//, '').replace(/\.(wav|flac)(:[ABCD])?/, '');
}

function play_src_with_audio_id_skip_redactions(source_uid, d, src, f){
  sp();
  const r = play_src_with_audio_id(source_uid, d, src, f);
  if(r === false) return; // successful playback
  // at this point, playback failed
  if(!r) return; // redaction check didn't finish
  if(!r.beg) return; // unknown error

  // at this point, r contains a redaction

  // region before redaction
  const x = {
    beg: src.beg,
    end: r.beg - 0.001
  }
  // region after redaction
  const y = {
      beg: r.end + 0.001,
      end: src.end
  }
  // r might go beyond src
  const yok = y.beg < y.end;

  // play x, but block if something else is playing
  window.ldc.vars.loop.set('redactions_callback', () => {
    if(playing) return; // wait
    window.ldc.vars.loop.delete('redactions_callback');
    play_src_with_audio_id(source_uid, d, x, f); // play x
    if(!yok) return; // nothing else to play

    // play y
    window.ldc.vars.loop.set('redactions_callback', () => {
      if(!playing) return; // wait for x to start
      window.ldc.vars.loop.set('redactions_callback', () => {
        if(playing) return; // wait for x to finish
        window.ldc.vars.loop.delete('redactions_callback');
        play_src_with_audio_id_skip_redactions(source_uid, d, y, f);
      } );
    } );
  } );
}

function play_src_with_audio_id(source_uid, d, src, f){
  if(true){
    console.log('tryin to play');
    console.log(source_uid);
    console.log(src);
  }
  const docid = redaction_docid(d);
  if(!redactions.has(docid)){
    console.log(`redactions haven't been checked for ${docid}`);
    return;
  }
  const r = redactions.get(docid);
  let rr;
  if(local_redactions.has(d)) rr = local_redactions.get(d);
  else                                  rr = [];
  console.log(r);
  if(r){
    if(r === true){
      console.log("getting redactions from server");
      return;
    }
    console.log('checking redactions');
    current_redaction = all_intersecting_spans(src, r, rr);
    if(current_redaction){
      console.log('redaction found');
    }
  }
  else{
    console.log('checking redactions');
    current_redaction = all_intersecting_spans(src, [], rr);
    if(current_redaction){
      console.log('redaction found');
    }
  }
  const g = (current_audio_node, playing, currently_playing_audio, now) => {
    f(current_audio_node, playing);
    if(current_redaction && currently_playing_audio){
      let found = first_intersecting_span( { beg: now, end: now }, current_redaction );
      currently_playing_audio.muted = !!found;
      if(current_audio_node) current_audio_node.muted = !!found;
    }
  };
  plays(source_uid, src, g);
  event.dispatch(null,'playback_started');
}

function first_intersecting_span(src, r){
  for(const x of r){
    // console.log(x);
    // console.log(src);
    if(!((src.end < x.beg) || (x.end < src.beg))){
      // console.log('intersection found');
      return x;
    }
  }
  return false;
}

function all_intersecting_spans(src, r, rr){
  const a = [];
  for(const x of r){
    if(!((src.end < x.beg) || (x.end < src.beg))){
      a.push(x);
    }
  }
  for(const x of rr){
    if(!((src.end < x.beg) || (x.end < src.beg))){
      a.push(x);
    }
  }
  if(a.length){
    console.log('intersections');
    console.log(a)
    return a;
  }
  return false;
}

function stop_playing(){
  sp();
  event.dispatch(null,'playback_ended');
}
// # console.log 'AUDIO'
// # console.log parent
// # console.log parent.stereo
// # parent_source = audio_context.createMediaElementSource parent
// # analyzer = audio_context.createAnalyser()
// if false #src.stereo is true
//     splitter = audio_context.createChannelSplitter(2)
//     xcurrently_playing_source.connect(splitter)
//     splitter.connect(analyzer, active_channel)
// else
//     # parent_source.connect(analyzer)
// # analyzer.connect(audio_context.destination)

function redactf(s){
  local_redactions.clear();
  for(let x of s){
    if(!local_redactions.has(x.docid)) local_redactions.set(x.docid, []);
    if(x.speaker == 'redacted'){
      local_redactions.get(x.docid).push(x);
    }
  }
  // if(debug) console.log(local_redactions);
}

export {
  play_src_with_audio_id,
  play_src_with_audio_id_skip_redactions,
  stop_playing,
  redactions,
  local_redactions,
  redactf,
  redaction_docid
}
