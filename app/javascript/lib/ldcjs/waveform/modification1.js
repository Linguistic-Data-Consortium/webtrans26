import { add_message, add_message_listitem, submit_form, add_callback, setldc } from './modification2';
import { BATCH_SIZE, bulk_start, bulk_after_paint, bulk_done, bulk_end } from './bulk.svelte';
import { sourceso, sourcesor } from './shared.svelte';
import { touch_segments } from './transcript.svelte';
import { event } from '../../../guides/guide';
import { round_to_3_places } from './times';
import { text_only_refuses } from './text_only';

let ldc;
function set_ldc(x){
  ldc = x;
  setldc(x);
}

// transcribe_text_only: the operations below that would change the transcript's
// shape refuse, one guard each — see text_only.js. The seeding of the imported
// segments runs before the tool locks itself (waveform.svelte's
// load_imported_transcript), so it goes through these same functions and isn't
// refused.

function done(comment){
  // add_message('0', 'done', { value: comment});
  add_message('0', 'done', comment);
  submit_form();
}

function broken(comment){
  // add_message('0', 'broken', {value: comment});
  add_message('0', 'broken', comment);
  submit_form();
}

function skip(){
  add_message('0', 'skip', null);
  submit_form();
}

function change_value(n, v, f){
  add_message(n, 'change', { value: v });
  submit_form();
  if(f) add_callback(f);
}

function change_value_src(n, src, f){
  add_message(n, 'change', src);
  submit_form();
  if(f) add_callback(f);
}

function delete_all(){
  if(text_only_refuses('delete every segment')) return;
  const all = [];
  for(const [k, v] of ldc.nodes){
    if(v.level == 2) all.push(k);
  }
  // Nothing to do, and nothing to report — starting the panel here would show
  // it for a frame and leave the count at 0 of 0.
  if(all.length == 0) return;
  bulk_start('Deleting segments', all.length);
  // After a paint, so the list is already gone and the message already up when
  // the first batch starts. See bulk_after_paint.
  bulk_after_paint(() => delete_batch(0, all));
}

// Was ten per round trip where ASR used a hundred, for no reason either could
// point at. BATCH_SIZE now, shared with the other batched operations.
function delete_batch(i, all){
  let j = i;
  while(j < i + BATCH_SIZE && j < all.length) add_message(all[j++], 'delete', null);
  submit_form();
  // After the batch's submit resolves, so the count tracks what the server has
  // taken rather than what was queued.
  add_callback(() => bulk_done(j));
  if(j < all.length) add_callback(() => delete_batch(j, all));
  else               add_callback(bulk_end);
}

// The same change applied to many nodes, batched. `change_value` submits per
// call, so doing this a node at a time is one round trip per node — which is
// what replacing a speaker label across a long transcript used to cost.
//
// The caller collects the iids, because what counts as "many" is its business:
// the speaker replace walks segmap for rows carrying the old label. Guarding is
// the caller's too, the way `change_value` leaves it alone — the operations that
// reach here are already past text_only_refuses.
function change_values(iids, value, f, label){
  if(iids.length == 0) return;
  bulk_start(label, iids.length);
  bulk_after_paint(() => change_batch(0, iids, value, f));
}

function change_batch(i, iids, value, f){
  let j = i;
  while(j < i + BATCH_SIZE && j < iids.length) add_message(iids[j++], 'change', { value: value });
  submit_form();
  add_callback(() => bulk_done(j));
  if(j < iids.length){
    add_callback(() => change_batch(j, iids, value, f));
  }
  else {
    // The caller's callback is a render refresh — it rebuilds the transcript
    // rows and, through index_segments, sets the active line again. None of
    // that is visible while the progress panel is up, so it runs once, after
    // the last batch, rather than per batch on the way.
    //
    // After bulk_end, so the panel is already down when the list is rebuilt.
    add_callback(bulk_end);
    if(f) add_callback(f);
  }
}

function delete_all2(all, f){
  if(text_only_refuses('delete every segment')) return;
  $('.ListItem').each(function(i, x) {
    let docid = $(x).find('.Segment').data().value.docid;
    if(all.includes(docid)){
      add_message($(x).data().meta.id, 'delete', null);
      console.log(`delete ${docid}`);
    }
  });
  submit_form();
  if(f) add_callback(f);
}

function delete_all_sections(f){
  if(text_only_refuses('delete the sections')) return;
  $('.SectionListItem').each(function(i, x) {
    add_message($(x).data().meta.id, 'delete', null);
  });
  submit_form();
  if(f) add_callback(f);
}

function delete_last_section(f){
  if(text_only_refuses('delete a section')) return;
  let last = null;
  $('.SectionListItem').each(function(i, x) {
    let id = $(x).data().meta.id;
    if (Number(id) > Number(last)) {
      last = id;
    }
  });
  if(last){
    add_message(last, 'delete', null);
    submit_form();
    if(f) add_callback(f);
  }
}

function create_test_segment(waveform, f){
  if(text_only_refuses('create a segment')) return;
  const list_selector = '.SegmentList';
  const audio_path = 'new.Segment';
  const span = {
    offset: 1.0,
    length: 1.0
  };
  add_audio_to_list(list_selector, audio_path, span);
  submit_form();
  if(f) add_callback(f);
}

function split_segment_at_cursor(cursortime, split_line_margin, f) {
  if(text_only_refuses('split a segment')) return;
  if(ldc.crnt){
    // id = $('.active-transcript-line').attr 'id'
    let data;
    let seg;
    let crnt = parseInt(ldc.crnt);
    seg = ldc.segmap.get(crnt);
    data = {
        meta: {
            id: crnt + 1
        },
        value: {
            beg: seg.beg,
            end: seg.end
        }
    };
    const src = data.value;
    const e = seg.endi;
    if(cursortime > src.beg && cursortime < src.end){
      const span = { offset: round_to_3_places(cursortime + split_line_margin) };
      span.length = round_to_3_places(src.end - span.offset);
      src.end = round_to_3_places(cursortime - split_line_margin);
      const b = ldc.obj.last_iid + 1;
      add_nodes1(2);
      const src2 = { beg: seg.begi, end: b };
      add_message(data.meta.id, 'change', src2);
      add_message('SegmentList', 'add', null);
      add_message('new.Arc', 'change', { beg: (b+2), end: e });
      add_nodes2(seg.docid, [ [ b, src.end ], [ b+2, span.offset ] ]);
      submit_form();
      if(f) add_callback(f);
    }
  }
}

function merge_with_following_segment(ids, map, f){
    if(text_only_refuses('merge two segments')) return;
    if(ids.id && ids.next){
      const id = ids.id;
      const next_id = ids.next;
      const crnt = parseInt(map.get(id).split('-')[1]);
      let seg = ldc.segmap.get(crnt);
      const seg1 = seg;
      const data = {
        meta: {
          id: crnt + 1
        },
        value: {
          beg: seg.begi,
          end: seg.endi
        }
      };
      const crnt2 = parseInt(map.get(next_id).split('-')[1]);
      seg = ldc.segmap.get(crnt2);
      const next_data = {
        meta: {
          id: crnt2 + 1
        },
        value: {
          beg: seg.begi,
          end: seg.endi
        }
      };
      // w.delete_transcript_line_based_on_segment_id(next_id, false);
      const src = data.value;
      src.end = next_data.value.end;
      // data.meta.id is seg1's Arc: re-pointing it at the far segment's end
      // anchor is the whole of the merge, structurally.
      add_message(data.meta.id, 'change', src);
      const v1 = ldc.segmap.get(crnt).text;
      const v2 = ldc.segmap.get(crnt2).text;
      if(v2 && v2.length > 0){
        // crnt+2 is seg1's Text.
        add_message(crnt + 2, 'change', { value: `${v1} ${v2}` });
      }
      delete_transcript_line_based_on_segment_id(map, next_id, false);
      touch_segments();
      submit_form();
      if(f) add_callback(f);
      event.dispatch(null, 'merged_segments');
    }
  }

function delete_transcript_line_based_on_listitem_id(id, submit, f) {
  if(text_only_refuses('delete a segment')) return;
  let idd = `${parseInt(id) + 1}`;
  // Remove the entry from both source objects: sourceso (the plain,
  // non-reactive one) and sourcesor (the $state one that the underlines
  // effect in channels.svelte watches). Without the sourcesor delete
  // the blue segment underline stays on the waveform after removal.
  for (const store of [sourceso.srcs, sourcesor.srcs]) {
    for (const k in store) {
      if (store[k][idd]) delete store[k][idd];
    }
  }
  add_message(id, 'delete', null);
  if(submit){
    submit_form();
    if(f) add_callback(f);
  }
}

function delete_transcript_line_based_on_segment_id(map, x, submit, f) {
  const sel = `#${map.get(x)}`;
  return delete_transcript_line_based_on_listitem_id(sel.split('-')[1], submit, f);
}

function add_segment(segment, callback){
  if(text_only_refuses('create a segment')) return;
  let b = ldc.obj.last_iid + 1;
  let vals = [];
  // Two anchors, then the span between them.
  vals.push([ 'N', { docid: segment.docid, beg: segment.beg, type: 'real' } ]);
  add_message_listitem('NList', vals);
  vals = [];
  vals.push([ 'N', { docid: segment.docid, beg: segment.end, type: 'real' } ]);
  add_message_listitem('NList', vals);
  vals = [];
  vals.push([ 'Arc', { beg: b, end: (b+2) } ]);
  if(segment.text) vals.push([ 'Text', { value: segment.text } ]);
  if(segment.speaker) vals.push([ 'Speaker', { value: segment.speaker } ]);
  // console.log(segment);
  add_message_listitem('SegmentList', vals);
  add_callback(callback);
}

// The redaction path is save_redaction (below), which the redact dialog calls
// through segments.svelte. An earlier `redactf` here did the same thing plus a
// direct write to each node's store; nothing imported it — segments.svelte's
// `redactf` is a different function, from play.js — so it went with the other
// dead writes.

function delete_segments(ids, f){
  if(text_only_refuses('delete a segment')) return;
  for(let id of ids) add_message(id, 'delete', null);
  submit_form();
  if(f) add_callback(f);
}

function add_section(section, id, f){
  if(text_only_refuses('add a section')) return;
  let vals;
  const seg = ldc.segmap.get(id);
  vals = [
    [ 'Arc', { beg: seg.begi, end: seg.endi } ],
    [ 'Name', { value: section } ]
  ];
  add_message_listitem('SectionList', vals);
  // ldc_annotate.add_message(window.gdata('.SectionList').meta.id, 'add', null);
  // ldc_annotate.add_message('new.Section', 'change', { value: section });
  // ldc_annotate.add_message('new.BegSeg', 'change', { value: id });
  // ldc_annotate.submit_form();
  if(f) add_callback(f);
}

function close_section(h, f) {
  if(text_only_refuses('close a section')) return;
  extend_section(h, f);
}

function section_order_forced_close(hh){
  const h = get_open_section(hh.iid);
  if(h && h.id) set_pointer(h.eseg.meta.id, h.id);
}

function extend_section(hh) {
  const h = get_last_section(hh.iid);
  console.log(h);
  if(!h.sec) return;
  const src = { beg: h.sec.begi, end: h.seg.endi };
  add_message(h.sec.iid+1, 'change', src);
  submit_form();
  if(f) add_callback(f);
}

function close_section2(hh) {
  const h = get_open_section(hh.iid);
  if(h){
    if(h.same){
      if(h.id){
        set_pointer(h.eseg.meta.id, h.id, f);
      }
    }
    else{
      h.overlap = false;
      h.src = {
        beg: h.a.value.beg,
        end: h.b.value.end
      };
      const last_section = find_last_section(h);
      if(h.overlap) alert("sections can't overlap");
      else if(h.id) set_pointer(h.eseg.meta.id, h.id, f);
    }
  }
}

function set_pointer(pointer, segment, f) {
  console.log('setting pointer ' + pointer)
  add_message(pointer, 'change', { value: segment.toString() });
  submit_form();
  if(f) add_callback(f);
}

function delete_nodes_after(after, f){
  let anyDeletion = false;
  document.querySelectorAll(".Node").forEach(n=>{
    const data = $(n).data("meta");
    if (data === undefined) return;
    const id = Number(data.id);
    if (isNaN(id) || id < 4 || id <= after) return;
    add_message(id, 'delete', null);
    anyDeletion = true;
  });
  if (anyDeletion){
    submit_form();
    if(f) add_callback(f);
  }
}

function add_nodes1(n){
  for(let i = 0; i < n; i++){
    add_message('NList', 'add', null);
  }
}

function add_nodes2(docid, times){
  for(const x of times){
    add_message(x[0]+1, 'change', { docid: docid, beg: x[1], type: 'real' });
  }
}

function add_audio_to_list(docid, list_selector, audio_path, span){
  if(text_only_refuses('create a segment')) return;
  if(false) console.log(span);
  if (span.length === 0) {
    // this doesn't always make sense
    return alert('select a region first');
  } else {
    const etime = span.end || (span.offset + span.length);
    const src = {
      docid: docid,
      beg: round_to_3_places(span.offset),
      end: round_to_3_places(etime),
      type: 'real'
    };
    let b;
    b = ldc.obj.last_iid + 1;
    add_nodes1(2);
    if(false){// (this.debug) {
      console.log('list');
      // console.log(list_selector);
    }
    add_message($('.SegmentList').data().meta.id, 'add', null);
    // w = if w.active_channel is 0 then waveform else waveform2
    // src.play_head = src.beg;
    if (false) { //@debug
      console.log('adding line');
      console.log(src);
    }
    add_message('new.Arc', 'change', { beg: b, end: (b+2) });
    add_nodes2(docid, [ [ b, src.beg ], [ b+2, src.end ] ]);
    if (span.transcript) add_message('new.Text', 'change', { value: span.transcript });
    if (span.speaker) {
      add_message('new.Speaker', 'change', { value: span.speaker });
    } else {
      const speaker = ldc.vars.last_speaker_used;
      if(speaker) add_message('new.Speaker', 'change', { value: speaker });
    }
    return 'submit';
  }
}

// A comment on a stretch of audio: two anchors and a CommentList group, which
// is a span with one label and no part of the transcript.
//
// Same shape as add_audio_to_list — anchors first, then the group, then the
// Arc that points at them — because it is the same shape. What differs is the
// list it goes in, and that nothing here has a speaker or a text.
//
// Allowed in transcribe_text_only mode: a remark about the audio isn't the
// transcript's shape, so this is not one of the guarded operations.
function add_comment_to_list(docid, span, text){
  const beg = round_to_3_places(span.beg);
  const end = round_to_3_places(span.end);
  if(!(end > beg)) return alert('select a region first');
  const b = ldc.obj.last_iid + 1;
  add_nodes1(2);
  add_message($('.CommentList').data().meta.id, 'add', null);
  add_message('new.Arc', 'change', { beg: b, end: (b + 2) });
  add_nodes2(docid, [ [ b, beg ], [ b + 2, end ] ]);
  if(text) add_message('new.Comment', 'change', { value: text });
  return 'submit';
}

function add_audio_to_listq(f){
  submit_form();
  if(f) add_callback(f);
}

function add_audio_to_listp(docid, span, f){
  const r = add_audio_to_list(docid, null, null, span);
  if(r === 'submit'){
    add_audio_to_listq(null);
    if(f) add_callback(f);
  }
}

function delete_section(id, f){
  if(text_only_refuses('delete a section')) return;
  if (id) {
    if (id === 'all') {
      $('.SectionListItem').each(function(i, x) {
        const iid = $(x).data().meta.id;
        add_message(iid, 'delete', null);
      });
    } else {
      add_message(id, 'delete', null);
    }
    submit_form();
    if(f) add_callback(f);
  }
};

// set_text lived here: a change message plus a direct write to the node's
// store. Nothing called it — text edits go through change_value — so it went
// with the other dead writes.

function add_empty_segments(emptySegments){
  emptySegments.forEach( s => 
    add_message(s.value.id, 'change', {value: s.value.words.join(" ")})
  );
  if (emptySegments.length){
    submit_form();
    add_callback( () => ldc.main.refresh() );
  }
}

// Move one end of a segment: change the time on the anchor that end points at.
// The anchor's own iid is on the row (begi / endi, from the graph); the node
// carrying its time is the N child, one iid along. This used to read the same
// two numbers out of the Arc node's store value.
function update_node(docid, n, r, begend){
  if(text_only_refuses("move a segment's time")) return;
  const row = ldc.segmap.get(parseInt(n.split('-')[1]));
  const anchor = begend === 'beg' ? row.begi : row.endi;
  const v = { docid: docid, beg: r, type: 'real' };
  add_message(anchor + 1, 'change', v);
  submit_form();
}

// update_wave lived here: the legacy Segment shape's way of re-timing a
// segment, reached only through the branch that went with xlass_def_id.
// update_node does this now, by re-timing the anchor an edge points at.
function add_transcript_line_split(span, f2, f){ //add_transcript_line(aa, bb, 'split');
  const r = f2(span);
  if(r === 'submit'){
    submit_form();
    if(f) add_callback(f);
  }
}

function check_for_submit(r, f){
  if(r === 'submit'){
    submit_form();
    if(f) add_callback(f);
  }
}

function save_redaction(iid, redact_text, redact_iid, redact_edit, f){
  add_message(iid.toString(), 'change', { value: redact_text });
  if(redact_edit) add_message(redact_iid, 'change', { value: redact_edit });
  submit_form();
  if(f) add_callback(f);
}

function add_cb(f){ add_callback(f); }

export {
  set_ldc,
  done,
  broken,
  skip,
  change_value,
  change_value_src,
  delete_all,
  delete_all2,
  delete_all_sections,
  delete_last_section,
  create_test_segment,
  merge_with_following_segment,
  delete_transcript_line_based_on_segment_id,
  add_segment,
  add_section,
  delete_segments,
  change_values,
  close_section,
  delete_nodes_after,
  add_audio_to_list,
  add_comment_to_list,
  add_audio_to_listp,
  add_audio_to_listq,
  delete_section,
  add_empty_segments,
  update_node,
  // split_segment,
  check_for_submit,
  split_segment_at_cursor,
  save_redaction,
  add_cb
}
