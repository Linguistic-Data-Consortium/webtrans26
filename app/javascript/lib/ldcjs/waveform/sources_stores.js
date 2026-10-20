import { writable } from 'svelte/store'
// const srcs = writable({});
// const sources = writable({});
const srcs = writable({});
import { sourcesor } from './shared.svelte';
const nodemap = {};
function sources_object_add_node(node, data){
  const uid = data.value.docid;
  if(uid){
    const src = data.value;
    nodemap[data.meta.id] = src;
    src.node = data.meta.id;
    if(!src.level) src.level = 0;
    add_source(data.meta.id, src);
  }
  else{
    if(nodemap[data.meta.id]) delete nodemap[data.meta.id];
  }
}

//this function adds a new source (Text widget) works for Audio as well
// node has to have a src as value
// src has to have docid
// src.node overrides div id if present
// src color is applied to node
// srcs[docid][node] = src
function add_source(node, src) {
  // if (this.debug === true) {
  //   console.log('add source');
  // }
  // if (this.debug) {
  //   console.log("HELPER");
  //   console.log(src);
  //   console.log(node);
  // }
  if (src.docid === null || src.docid === void 0) {
    return;
  }
  const x = sourcesor.srcs;
    if(!x.hasOwnProperty(src.docid)){
      x[src.docid] = {};
    }
    if(src.node){
      x[src.docid][src.node] = src;
    }
    else{
      x[src.docid][node] = src;
    }
    return x;
  // if (this.first_src === null) {
  //   this.first_src = src;
  // }
  // if (src.color) {
  //   $(node).css('color', src.color);
  // }
  // if (this.debug === true) {
  //   return console.log(srcs);
  // }
}

function add_source_audio_collision(docid) {
  const all = [];
  const x = sourcesor.srcs;
    add_source_audio_collision_helper(x, all, docid);
    return x;
}

function add_source_audio_collision_helper(srcs, all, docid) {
  if(!srcs[docid]) return;
  for(const [node_id, src] of Object.entries(srcs[docid])){
    while(collides_set(src, all)) src.level += 1;
    all.push(src);
  }
}

//function checks a set of sources to see if they overlap with a provided source
function collides_set(src1, srcs){
  var collision, i, j, ref;
  for (i = j = 0, ref = srcs.length; (0 <= ref ? j < ref : j > ref); i = 0 <= ref ? ++j : --j) {
    if(collides(src1, srcs[i])){
      collision = srcs[i];
      return true;
    }
  }
  return false;
}

//function checks two sources to see if they overlap with each other
function collides(src1, src2){
  if(src1.end < src2.beg) return false;
  if(src2.end < src1.beg) return false;
  if(src1.level !== src2.level) return false;
  return true;
}


export {
  sources_object_add_node,
  add_source,
  srcs,
  add_source_audio_collision
}
