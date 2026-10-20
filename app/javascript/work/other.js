import { writable } from 'svelte/store'
import { groups } from '../lib/ldcjs/waveform/groups';
import { getp } from '../lib/ldcjs/getp';
import { done } from '../lib/ldcjs/waveform/modification1';
let ldc;
function set_ldc(x){
  ldc = x;
}
function get_templates(templates_url, full){
  return getp(`/sources/media?uid=${templates_url}&type=text`).then( (x) => {
    let templates = new Map();
    if(full) return templates;
    if(typeof(x) != 'string') return templates;
    template_helper(x, templates);
    return templates;
  } );
}
function template_helper(x, templates){
  let y = x.split("\n");
  for(let i = 0; i < y.length; i++){
      let a = y[i].split("\t");
      templates.set(a.slice(0,4).join(' '), a[4]);
  }
}
function get_templates2(templates_url, full){
  return getp(`/sources/media?uid=${templates_url}&type=text`).then( (x) => {
    let templates = new Map();
    // if(full) return templates;
    let templates_arr = [];
    let rows;
    if (x.split) rows = x.split("\n");
    else         rows = [];
    // removes empty rows if any
    rows = rows.filter(Boolean);
    if(rows.length == 0) return templates;
    let headers = rows[0].split("\t");
    for(let i = 1; i < rows.length; i++){
        let a = rows[i].split("\t");
        let o = {};
        for(let j = 0; j < a.length; j++){
            o[headers[j]] = a[j];
        }
        templates_arr.push(o);
    }
    for (let t of templates_arr){
        let key = [t.topic_value, t.subtopic_value].join(" ");
        if (key == " ")
            key = [t.supertype_value, t.type_value, t.subtype_value, t.subsubtype_value].join(" ");
        templates.set(key, t);
    }
    return templates;
  } );
}
function add_validate_next_btn(f){
  let work1 = document.querySelector('#work1');
  // let next_btn = document.querySelector('#next');
  // if(next_btn) next_btn.remove();
  let validate_next_btn = document.createElement('button');
  validate_next_btn.className = "BtnGroup-item btn btn-sm btn-outline";
  validate_next_btn.id = "validate_next";
  validate_next_btn.innerText = "NEXT";
  validate_next_btn.disabled = true;
  work1.appendChild(validate_next_btn);
  let validate_next = document.querySelector('#validate_next');
  validate_next.addEventListener('click', f);
}
function add_next_kit_btn(){
  let work1 = document.querySelector('#work1');
//   let next_btn = document.querySelector('#next');
//   next_btn.remove();
  let b = document.createElement('button');
  b.className = "BtnGroup-item btn btn-sm btn-outline";
  b.id = "next_kit_btn";
  b.innerText = "Next Kit";
  work1.appendChild(b);
  const next_kit_btn = document.querySelector('#next_kit_btn');
  next_kit_btn.addEventListener('click', () => done(null));
  return next_kit_btn;
}
function add_validate_next_btn_start_disabled(f){
  add_validate_next_btn(f);
  let validate_next = document.querySelector('#validate_next');
  validate_next.disabled = true;
}
function fullf(){
  window.open(window.location + '?full=true', '_blank', "toolbar=yes");
}
function iffullf(full, ns){
  if(full){
    document.querySelector('.Header').remove();
    document.body.style = 'padding: 0px';
    document.querySelector('#main-wrapper').style = 'height: 100%';
    document.querySelector('#main').style = 'height: 100%';
    document.querySelector('.ann_pane').style = 'height: 100%';
    document.querySelector('.Root').style = 'height: 100%';
    ldc_source.append_all_media('#full', ns.manifest.files, true, "Full Doc", false);
  }
}
function get_sources_from_child(child_uid, sourcedocs){
    return Object.entries(sourcedocs).find( ([k,v]) => Object.values(v).flat().includes(child_uid) );
}
function range(start, end){
  return Array(end - start + 1).fill().map((_, idx) => start + idx);
}
function replace_array_item_at_index(array, index, ...items){
  return [ ...array.slice(0, index), ...items, ...array.slice(index + 1) ];
}
  // sort arr of objs by property 'p'
function obj_arr_alpha_sort_helper(a, p){
    a.sort((o1, o2) => {
        let x = o1[p].toUpperCase();
        let y = o2[p].toUpperCase();

        if(x < y) return -1;
        if(x > y) return 1;
        return 0;
    });
}
// sets up each object in arr of objects with an integer value
// representing its position in the array on property `seq_id`
// if obj already has `seq_id`, it's overwritten by current index.
function set_obj_arr_seq_id(a){
  let i = 0;
  for(const x of a){
      if(x?.seq_id) x.seq_id = i;
      else x['seq_id'] = i;
      i++;
  }
}
// Note: this fn may return negative integers
function get_hash_code(str){
    let hash = 0;
    if(str.length === 0) return hash;
    for(let i = 0; i < str.length; i++){
        let chr = str.charCodeAt(i);
        hash = ( ( hash << 5 ) - hash ) + chr;
        hash |= 0; // convert to 32bit integer
    }
    return hash;
}

function jdata(sel) {
  return $(sel).data();
};

function jdataw(sel) {
  return window.wait_for(sel, function() {
    return $(sel).data();
  });
};

function jdatap(sel) {
  return new Promise(function(r) {
    return window.wait_for(sel, function() {
      return r($(sel).data());
    });
  });
};

// The tool folds the payload into an annotation graph and renders from that, so
// the tree's values live there. What this builds is the structure — one node per
// iid, children hung off their list item — which addf extends and deletef prunes.
// There are no per-node stores and no copy of the payload's values: nothing
// reads them.

function init2(x){
  const v = {
    name: x.xode.name,
    iid: x.xode.iid,
    parent_iid: x.xode.parent_iid,
    level: x.xode.level
  }
  ldc.nodes.set(v.iid, v);
  if(v.level == 2){
    v.children = [];
    v.nodes = new Map();
  }
  else if(v.level == 3){
    v.node_value_id = x.xode.annotation_id;
  }
}

function init3(k, v){
  if(v.level == 3){
    let p = ldc.nodes.get(v.parent_iid);
    if(!p) return;
    p.children.push(v);
    p.nodes.set(v.name, v);
  }
}

function init4(n){
  let list_items = new Map();
  for(const [k, v] of ldc.nodes){
    if(v.name == `${n}Item`){
      list_items.set(k, v);
    }
  }
  ldc.node_lists.set(n, writable(list_items));
}

// Builds the node objects for a new list item and its children.
//
// `group` is the group string — "5:SegmentListItem,6:Arc,7:Text,8:Speaker" —
// when the caller has already allocated it, which is what the waveform does so
// that a new segment starts in its annotation graph rather than here. Without
// one, this allocates as it always did, for the tools that have no graph.
function addf(n, group){
  const allocated = group
    ? String(group.value || group).split(',').map( (pair) => {
        const [ iid, name ] = pair.split(':');
        return { iid: parseInt(iid), name: name };
      } )
    : null;
  if(allocated) ldc.obj.last_iid = Math.max(ldc.obj.last_iid, ...allocated.map( (x) => x.iid ));

  const list_item_iid = allocated ? allocated[0].iid : ++ldc.obj.last_iid;
  const nn = {
    name: allocated ? allocated[0].name : `${n}Item`,
    iid: list_item_iid,
    parent_iid: null,
    level: 2,
    node_value_id: 0
  };
  init2( { xode: nn } );
  const a = [ `${nn.iid}:${nn.name}` ];
  nn.parent_iid = nn.iid;
  nn.level = 3;
  const children = allocated
    ? allocated.slice(1)
    : groups[n].children.map( (name) => ({ name: name, iid: null }) );
  for(const x of children){
    nn.name = x.name;
    nn.iid = x.iid == null ? ++ldc.obj.last_iid : x.iid;
    init2( { xode: nn } );
    init3(nn.iid, ldc.nodes.get(nn.iid));
    a.push(`${nn.iid}:${nn.name}`);
  }
  ldc.node_lists.get(n).update( (x) => {
    x.set(list_item_iid, ldc.nodes.get(list_item_iid));
    return x;
  } );
  ldc.last_children = a;
  // return a.join(',');
  return { value: a.join(',') };
}

// "new.Text" names a child of the group addf just built, by name rather than by
// iid — the caller doesn't know the iids, addf allocated them. Everything that
// has to act on a message before the node layer does needs the same lookup, so
// it lives here rather than inside changef.
function resolve_new(name){
  for(const y of ldc.last_children || []){
    const z = y.split(':');
    if(z[1] == name) return parseInt(z[0]);
  }
  return null;
}

// Resolves the node a change names — "new.Text" against the group addf just
// built, or a bare iid — and hands it back for the message. There is nothing to
// write here any more: the value goes to the graph and to the server.
function changef(n, v){
  if(typeof(n) == 'string' && n.substring(0, 4) == 'new.'){
    const iid = resolve_new(n.substring(4));
    if(iid != null) n = iid;
  }
  else if(typeof(n) == 'string') n = parseInt(n);
  return n;
}

function deletef(n){
  n = parseInt(n);
  const v = ldc.nodes.get(n);
  ldc.nodes.delete(n);
  ldc.node_lists.get(v.name.replace(/Item$/, '')).update( (x) => {
    x.delete(n);
    return x;
  } );
  for(let x of v.children) ldc.nodes.delete(x.iid);
}

function init_nodes(){
  ldc.nodes = new Map();
  for(const x of ldc.obj.nodes) init2({ xode: x });
  for(const [k, v] of ldc.nodes) init3(k, v);
  ldc.node_lists = new Map();
  const nodes = Object.keys(groups).sort();
  for(let i = 1; i <= nodes.length; i++){
    let n = nodes[i-1]
    $('.Root').append(`<div class="${n}" />`)
    $('.Root').data( { meta: {} } );
    $(`.${n}`).data( { meta: { id: `${n}` } } );
    init4(n);
  }
  // ldc.add = add;
  ldc.last_iid = parseInt(ldc.obj.last_iid);
  ldc.addf = addf;
  ldc.changef = changef;
  ldc.deletef = deletef;
  ldc.resolve_new = resolve_new;
}

function get_lang_labels(labels, lang){
  let lang_labels = {};
  for(let [k, v] of Object.entries(labels)){
      if(lang == 'cmn' && k.startsWith('CMN')){
          lang_labels[`${k.replace('CMN', '')}`] = v;
      } else if(lang == 'spa' && k.startsWith('SPA')){
          lang_labels[`${k.replace('SPA', '')}`] = v;
      }
  }
  return lang_labels;
}

export {
  get_templates,
  get_templates2,
  add_validate_next_btn,
  add_validate_next_btn_start_disabled,
  add_next_kit_btn,
  fullf,
  iffullf,
  get_sources_from_child,
  range,
  replace_array_item_at_index,
  obj_arr_alpha_sort_helper,
  set_obj_arr_seq_id,
  get_hash_code,
  jdata,
  jdataw,
  jdatap,
  set_ldc,
  init_nodes,
  get_lang_labels
}
