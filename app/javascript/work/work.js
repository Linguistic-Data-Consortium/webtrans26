import { init } from './init'
import { setup } from '../settings'
import { getp } from '../lib/ldcjs/getp';

// import { sources_object_add_node } from '../lib/ldcjs/waveform/sources_stores';
// const debug = false;
// function wait_for_f1_f2(f1, f2) {
//   if (f1() === true) {
//     return f2();
//   } else {
//     return setTimeout(function() {
//       return wait_for_f1_f2(f1, f2);
//     }, 100);
//   }
// }
// function wait_for(sel, f2) {
//   var f1;
//   f1 = function() {
//     return document.querySelectorAll(sel).length !== 0;
//   };
//   return wait_for_f1_f2(f1, f2);
// }
// window.wait_for = wait_for;

// window.gdata = function(sel) {
//   if(sel == '.Root') return window.ldc.obj2;
//   else return window.nodes[document.querySelector(sel).getAttribute('id').split('-')[1]];
// };

// window.gdataw = function(sel) {
//   return wait_for(sel, function() {
//     return window.gdata(sel);
//   });
// };

// window.gdatap = function(sel) {
//   return new Promise(function(r) {
//     return wait_for(sel, function() {
//       return r(window.gdata(sel));
//     });
//   });
// };

// // window.sources_object = new Sources('blah');
// window.sources_object_add_node = function(node, data){
//   sources_object_add_node(node, data);
// }

// let nnodes = {};

let node_classes;
let node_classes_by_name;
// var indexOf = [].indexOf;
// const array2html = function(a) {
//   var children, i, name, s;
//   if (a === null) {
//     return '';
//   }
//   name = a[0];
//   children = a[a.length - 1];
//   s = '<' + name;
//   i = 1;
//   while (a.length > i + 1) {
//     s += ` ${a[i]}=\"${a[i + 1]}\"`;
//     i += 2;
//   }
//   if (children instanceof Array) {
//     if (children.length > 0) {
//       s += '>';
//       $.each(children, function(x, y) {
//         return s += array2html(y);
//       });
//       return `${s}</${name}>`;
//     } else {
//       return `${s}/>`;
//     }
//   } else {
//     return `${s}>${children}</${name}>`;
//   }
// };


let workflow = null;
  // one waveform has multiple channels, but there could be multiple waveforms
  const waveforms = [];
    function work(hash) {
      // document.getElementById('spinner').remove();
      document.getElementById('main').insertAdjacentHTML(
        'beforeend',
        '<div class=ann_pane><div class="Root" id="node-0"></div></div>'
      );
      if(!window.ldc) window.ldc = {};
      if(!window.ldc.vars) window.ldc.vars = {};
      window.ldc.permissions = hash;
      window.ldc.resources = {};
      window.ldc.resources.manifest = hash.manifest;
      window.ldc.get_constraint = window.get_constraint;
      window.ldc.services_init = window.services_init;
      window.ldc.$ = window.$;
      const kit = hash.initt;
      console.log(kit)
      if(kit.refresh == true){
        let t = 3;
        setInterval(function(){
          if(t == 0){
            window.location.reload();
          }
          else {
            document.querySelector('body').innerHTML = "restarting in " + String(t) + " seconds";
            t -= 1;
          }
        }, 1000);
        return;
      }
      let url;
      if(kit.read_only == true){
          url = '/kits/get?uid=' + kit._id + '&task_user_id=readonly';
      }
      else{
          url = '/kits/get?uid=' + kit._id + '&task_user_id=' + kit.task_user_id;
      }
      url += '&mode=two'
      // The kit loads through the graph shape by default. ?payload=log on the
      // work page asks for the annotation log directly instead, and
      // ?payload=graph_stored for what the last snapshot wrote — same tree,
      // different routes to it.
      const payload = new URLSearchParams(window.location.search).get('payload');
      if(payload) url += '&payload=' + encodeURIComponent(payload);
      console.log("HERE")
      workflow = {};
      getp(url).then( function(obj) {
        console.log(obj);
        obj.workflow_id = kit.workflow_id;
        obj.read_only = kit.read_only;
        obj.parent = kit.parent;
        obj.task_user_id = kit.task_user_id;
        obj.quality_control = kit.quality_control;
        // obj.node_url = url + '&iid='

        window.ldc.vars.user_id = obj.user_id;
        window.ldc.vars.task_id = obj.task_id;
        window.ldc.vars.kit_id = obj.kit_id;
        // document.getElementById('task_name').innerText = obj.task_name;
        if (obj.task_id && obj.source) obj.source.task_id = obj.task_id;
        window.source = obj.source;
        // add_nodes(obj.tree, null);
        // ldc.obj is the payload the node layer is built from, so the test is
        // whether there's a tree in it. It used to test xlass_def_id, a flag
        // that means something else entirely — which tool to mount.
        if(obj.nodes) window.ldc.obj = obj;
        window.ldc.obj2 = obj;
        window.$('.Root').data().obj = obj;
        workflow_open(window.ldc);
        return obj;
    
      } );
  }

//   function add_nodes(node, parent) {
//     var that = this;
//     var n = node.meta.id;
//     nnodes[n] = node;
//     node.meta.parent = parent;

//     //            alert(jsonsp(node.meta))
//     if(node.children){
//         $.each(node.children, function(x,y){
//             add_nodes(node.meta.list ? y : node[y], node);//list children need special handling
//         });
//     }
//   }

//     function initg() {
//     }

//     function init_node2(node, parent, location) {
//       var a, children, children_iids, classes, i, n, node_class, p, pp, ref1, selector, source, ss, style, tabs1, tabs2, that, type, types, value, x;
//       that = this;
//       // console.log "top #{node.meta.name}"
//       // console.log node
//       // console.log parent
//       node.meta.id = `${node.meta.id}`;
//       n = node.meta.id;
//       if (!location) {
//         location = `#node-${parent.meta.id}`;
//       }
//       // console.log("initting #{n}")
//       selector = `#node-${n}`;
//       node_class = node_classes[node.meta.node_class_id];
//       types = node_class.types;
//       node.meta.types = types;
//       if (node_class.style === void 0) {
//         node_class.style = {
//           style: {
//             css: {}
//           }
//         };
//       }
//       style = node_class.style.style || node_class.style.style_test;
//       if (style.classes === void 0) {
//         style.classes = '';
//       }
//       if (node_class.c.classes && (ref1 = node_class.c.classes.split(' ')[0], indexOf.call(style.classes.split(' '), ref1) < 0)) {
//         style.classes += ` ${node_class.c.classes}`;
//       }
//       node.meta.css = style.css;
//       node.meta.extra_classes = style.classes;
//       node.meta.horiz = style.horizontal ? true : false;
//       node.meta.inline = style.inline ? true : false;
//       node.meta.logic = 0;
//       classes = (function() {
//         var j, len, results;
//         results = [];
//         for (j = 0, len = types.length; j < len; j++) {
//           type = types[j];
//           if (type.match(/:/)) {
//             results.push(type.split(':')[1]);
//           } else {
//             results.push(type);
//           }
//         }
//         return results;
//       })();
//       if (parent && parent.meta.list) {
//         classes.push('ListItem');
//       }
//       if (classes.join('').match(/Ref/)) {
//         classes.push('Ref');
//       }
//       if (style.hide === true) {
//         classes.push('hidden');
//       }
//       if (indexOf.call(classes, 'Audio') >= 0) {
//         classes.push('Leaf');
//       }
//       if (indexOf.call(classes, 'Text') >= 0) {
//         classes.push('Leaf');
//       }
//       if (!(node_class.c.add_to_top || node_class.c.reverse_order)) {
//         if (node_class.c.reverse === false) {
//           node.meta['reverse'] = false;
//         }
//       }
//       if (n === '0') {
//         $.each(classes, function(i, x) {
//           return $("#node-0").addClass(x);
//         });
//       } else {
//         ss = array2html(['div', 'class', classes.join(' '), 'id', `node-${n}`, '']);
//         if (node.added === true) {
//           if (parent.meta.reverse === false) {
//             $(location).append(ss);
//           } else {
//             $(location).prepend(ss);
//           }
//           node.added = false;
//         } else {
//           $(location).append(ss);
//         }
//       }
//       $(selector).addClass(node.meta.extra_classes);
//       node.refs = {};
//       window.nodes[n] = node;
//       $(selector).data(node);
//       // $(selector).data(node)
//       if (indexOf.call(classes, 'Leaf') >= 0) {
//         if (node_value_empty(node) === true) {
//           $(selector).addClass('empty'); //.removeClass('nonempty')
//         } else {
//           $(selector).addClass('nonempty'); //.removeClass('empty')
//         }
//       }
//       $(selector).addClass('refresh');
//       switch (false) {
//         case indexOf.call(types, 'List') < 0:
//           if (node_class.c.table_columns) {
//             node.meta.table_columns = node_class.c.table_columns.trim().split(/\s+/);
//             node.meta.table_scrollY = node_class.c.table_scrollY || '200px';
//           }
//           if (node.children) {
//             if (node_class.c.reverse === false) {
//               if (node_class.c.reverse_order === true) {
//                 children = node.children.reverse();
//                 children_iids = node.children_iids.reverse();
//               } else {
//                 children = node.children;
//                 children_iids = node.children_iids;
//               }
//             } else {
//               children = node.children.reverse();
//               children_iids = node.children_iids.reverse();
//             }
//             return $.each(children, function(x, y) {
//               return init_node2(y, node, `#node-${node.meta.id}`);
//             });
//           }
//           break;
//         case indexOf.call(types, 'Coref') < 0:
//           return ldc_annotate.init_node_coref_helper(node.value, n);
//         // when 'Upload' in types
//         //     ldc_nodes.upload(node);
//         case indexOf.call(types, 'Audio') < 0:
//           // console.log 'AUDIO'
//           // console.log node_class.c
//           if (!node.value.docid) {
//             x = window.ldc.resources;
//             if (x) {
//               x = x.manifest;
//               if (x) {
//                 x = x.audio_list;
//                 if (x) {
//                   p = node.meta.parent;
//                   pp = p.meta.parent;
//                   i = pp.children.indexOf(p);
//                   x = x[i];
//                   if (x) {
//                     $(selector).data().value = {
//                       docid: x.original_id,
//                       beg: that.round_to_3_places(x.btime),
//                       end: that.round_to_3_places(x.etime)
//                     };
//                   }
//                 }
//               }
//             }
//           }
//           if ($(selector).hasClass('ChannelA')) {
//             source = $('.Root').data().obj.source;
//             $(selector).data().value = {
//               // docid: 6177876
//               docid: source.id,
//               beg: that.round_to_3_places(source.btime),
//               end: that.round_to_3_places(source.etime)
//             };
//           }
//           if ($(selector).hasClass('ChannelB')) {
//             source = $('.Root').data().obj.source;
//             $(selector).data().value = {
//               // docid: 6177876
//               docid: source.id.replace(/A$/, 'B'),
//               beg: that.round_to_3_places(source.btime),
//               end: that.round_to_3_places(source.etime)
//             };
//           }
//           // it seems like the following is never executed because classes get added later
//           if ($(selector).hasClass('Waveform')) {
//             return that.init_waveform(selector);
//           } else if (node_class.value.timestamps === true) {
//             value = node_class.value;
//             $(selector).addClass('Timestamps');
//             return ;
//           }
//           break;
//         case indexOf.call(types, 'Label') < 0:
//           if (node_class.children) {
//             node_class.value = {
//               label: node_class.children
//             };
//             node_class.children = null;
//           }
//           return node.value = node_class.value['label'];
//         case indexOf.call(types, 'Button') < 0:
//           return node.value = node_class.value;
//         case indexOf.call(types, 'ButtonGroupRadio') < 0:
//           return $.each(node_class.value, function(x, y) {
//             return node.value[x] = y;
//           });
//         case indexOf.call(types, 'Text') < 0:
//           return that.init_node2_text(node, n, selector);
//         case indexOf.call(types, 'CheckboxGroup') < 0:
//           if (node.value == null) {
//             node.value = {
//               value: []
//             };
//           }
//           if (node.value === '{[]}') {
//             return node.value = {
//               value: []
//             };
//           }
//           break;
//         case indexOf.call(types, 'Tabs') < 0:
//           tabs1 = [];
//           tabs2 = [];
//           a = ['ul', 'class', 'nav-tabs', tabs1];
//           // b = [ 'div', 'class', 'tab-content', tabs2 ]
//           if (node.children) {
//             $.each(node.children, function(i, c) {
//               var active1, active2, cc;
//               active1 = i === 0 ? 'active' : '';
//               active2 = i === 0 ? 'tab-pane active' : 'tab-pane';
//               cc = node[c];
//               // tabs1.push [ 'li', 'class', active1, [ [ 'a', 'href', "#node-#{cc.meta.nid}-tab", 'data-toggle', 'tab', cc.meta.name ] ] ]
//               // tabs2.push [ 'div', 'class', active2, 'id', "node-#{cc.meta.nid}-tab", '' ]
//               return tabs1.push(['li', 'class', 'tab-header-and-content', [['a', 'href', "javascript:void(0)", 'class', 'tab-link', cc.meta.name], ['div', 'class', 'tab-content', 'id', `node-${cc.meta.nid}-tab`, '']]]);
//             });
//           }
//           $(selector).append(array2html(a));
//           // $(selector).append array2html b
//           ldc_lui.tabs1(`${selector} .nav-tabs`);
//           if (node.children) {
//             return $.each(node.children, function(x, c) {
//               var cc;
//               cc = node[c];
//               return init_node2(cc, node, `#node-${cc.meta.nid}-tab`);
//             });
//           }
//           break;
//         default:
//           // when 'Ref' in types
//           //     $(selector).text 'empty node ref'
//           if (node.children) {
//             return $.each(node.children, function(x, y) {
//               return init_node2(node[y], node, `#node-${node.meta.id}`);
//             });
//           }
//       }
//     }

    function workflow_open(ldc) {
      return set_node_classes3().then(function(r) {
        whelper01(null, null);
        after_node_classes_features();
        namespace(ldc);
      });
    }

  function after_node_classes_features() {
      var c, obj, params, root, sel, that, tool, vars;
      that = this;
      root = $('.Root').data();
      obj = root.obj;
      c = obj.meta.constraints;
      tool = obj.workflow;
      vars = window.ldc.vars;
      // if (c.show_source) {
        // if (c.web_audio) {
          // The transcription tool. Which tool a kit gets used to be decided
          // here by class def; that mechanism went with the flag, and a kit_type
          // based one will replace it.
          let s = '<div class="view" data-svelte-component="maintranscription" data-props="{}" />'
          $('.Root').prepend(s);
          sel = `.${vars.add_from_waveform_list}Item`;
          // current_hide_show(sel, '#noop');
          // ldc_source.add_audio_object obj.source
        // }
      // }
    }
    function whelper01(w, current_display) {
      var d1, d2, obj;
      obj = $('.Root').data().obj;
      if (!current_display) {
        current_display = obj.current_display;
      }
      window.nodes = {}
    }

    function set_node_classes3() {
      var that;
      // Was: getp('/class_defs_index2?kit_uid=...') — controller has been removed.
      // The endpoint already returned an empty `{ node_classes: {} }`, so inline it.
      return Promise.resolve({ node_classes: {} }).then( function(obj) {
        node_classes = obj.node_classes;
        node_classes_by_name = {};
        $.each(node_classes, function(i, x) {
          x.virtual = [];
          node_classes_by_name[x.name.split(':')[1]] = x;
          return node_classes_by_name[x.name.split(':')[1]].id = parseInt(i);
        });
        $.each(node_classes_by_name, function(name, x) {
          var c, label_node, r, sel, y;
          // if x.c.labels
          //     $.each x.c.labels, (i, pat) ->
          //         x.small = pat.small
          //         x.where = pat.where
          //         $.each pat.target, (i, nc) ->
          //             if node_classes_by_name[nc]
          //                 node_classes_by_name[nc].label_node = x
          if (x.c.containers) {
            $.each(x.c.containers, function(i, pat) {
              return $.each(pat.root, function(i, nc) {
                if (node_classes_by_name[nc]) {
                  return node_classes_by_name[nc].virtual.push([x, pat.target]);
                }
              });
            });
          }
          // node_classes_by_name[nc].virtual_node_selector = pat.target
          if (x.value) {
            if (x.value.label) {
              label_node = node_classes_by_name[x.value.label];
              if (label_node) {
                x.label_node = label_node;
              }
            }
          }
          if (name.match(/Virtual/)) {
            y = name.replace('Virtual', '');
            if (node_classes_by_name[y]) {
              node_classes_by_name[y].virtual_node = x;
            }
          }
          if (x.c.messages) {
            $.each(x.c.messages, function(i, m) {
              if (m.add) {
                $('.Root').on('click', '.' + name, function(e) {
                  var parents, target;
                  parents = $(this).parents('.ListItem, .Root');
                  if (parents.length > 0) {
                    target = $(parents[0]).find('.' + m.target)[0];
                    if (target) {
                      ldc_annotate.add_message($(target).data().meta.id, 'add', null);
                      return ldc_annotate.submit_form();
                    }
                  }
                });
              }
            });
          }
          c = x.c.selected_entity;
          if (c) {
            sel = `.${name}Table tbody tr`;
            $('.Root').on('click', sel, function() {
              var id;
              if ($('#selected_entity').length === 0) {
                $(`.${name} .dataTables_wrapper`).before("<div id=\"selected_entity\">none selected</div>");
              }
              id = $(this).find('td:first').text();
              if (selected_entity !== id && id !== '-') {
                selected_entity = id;
                selected_entity_row = $(this);
                $('#selected_entity').text(id);
                return that.selected_entity_helper(selected_entity, selected_entity_row);
              } else {
                selected_entity = null;
                $('#selected_entity').text('none selected');
                return $('#summaryv').html('');
              }
            });
          }
          r = x.c.now;
          if (x.c.add_from_waveform_list === true) {
            window.ldc.vars.add_from_waveform_list = name;
          }
          if (x.c.add_from_waveform_audio === true) {
            window.ldc.vars.add_from_waveform_audio = name;
          }
          if (x.c.add_from_waveform_text === true) {
            return window.ldc.vars.add_from_waveform_text = name;
          }
        });
        // that.init_node2 kit.tree
        return console.log(node_classes_by_name);
      });
    }

//     function node_value_empty(x) {
//       // console.log 'checking empty'
//       if ($.inArray('CheckboxGroup', x.meta.types) !== -1) {
//         // console.log 'checkbox'
//         // console.log JSON.stringify({value: []})
//         // console.log JSON.stringify(x.value);
//         // console.log JSON.stringify({value: []}) is JSON.stringify(x.value);
//         return JSON.stringify({
//           value: []
//         }) === JSON.stringify(x.value);
//       }
//       if ($.inArray('Set', x.meta.types) !== -1 || $.inArray('MegaMenu', x.meta.types) !== -1) {
//         if (x.value.value === null) {
//           return true;
//         }
//         if (x.value.value.length === 0) {
//           return true;
//         }
//         return false;
//       }
//       if ($.inArray('Entry', x.meta.types) !== -1) {
//         if (x.value.value === null) { //JSON.stringify({value: null}) is JSON.stringify(x.value)
//           return true;
//         }
//         if (x.value.value === '') { //JSON.stringify({value: ""}) is JSON.stringify(x.value)
//           return true;
//         }
//         return false;
//       }
//       if ($.inArray('Textarea', x.meta.types) !== -1) {
//         if (JSON.stringify({
//           value: null
//         }) === JSON.stringify(x.value)) {
//           return true;
//         }
//         if (JSON.stringify({
//           value: ""
//         }) === JSON.stringify(x.value)) {
//           return true;
//         }
//         return false;
//       }
//       if ($.inArray('Menu', x.meta.types) !== -1) {
//         if (x.value.value === null || x.value.value === "") {
//           // if JSON.stringify({value: null}) is JSON.stringify(x.value)
//           //     return true;
//           // if JSON.stringify({value: ""}) is JSON.stringify(x.value)
//           //     return true;
//           // why did I bother stringify?  am I missing somethting?
//           return true;
//         }
//         return false;
//       }
//       if ($.inArray('Radio', x.meta.types) !== -1) {
//         return x.value.hasOwnProperty('value') && x.value.value === null;
//         return JSON.stringify({
//           value: null
//         }) === JSON.stringify(x.value);
//       }
//       if ($.inArray('Ref', x.meta.types) !== -1) {
//         return x.value.hasOwnProperty('value') && (x.value.value === null || x.value.value === '');
//       }
//       if ($.inArray('Text', x.meta.types) !== -1) {
//         return (!x.value.hasOwnProperty('docid')) || x.value.docid === null;
//       }
//       if ($.inArray('Media', x.meta.types) !== -1) {
//         return x.value.hasOwnProperty('value') && (x.value.value === null || x.value.value === '');
//       }
//       if ($.inArray('Leaf', x.meta.types) !== -1) {
//         return x.value.hasOwnProperty('value') && (x.value.value === null || x.value.value === '');
//       }
//     }
//     function logic(workflow, global_object) {
//       var ns, nss, obj, that;
//       that = this;
//       $('.tooltip-item .tooltip').remove();
//       $('.tooltip-item').removeClass('tooltip-item');
//       $('.Node').each(function(i, x) {
//         return $(x).data().errors = [];
//       });
//       $('.focusable').attr('tabindex', 0);
//       if ($('.Root').length === 0) {
//         return;
//       }
//       // obj = $('.Root').data().obj;
//       // nss = $('.Root').data().obj.grammar_lookup.Root;
//       // ns = $('.Root').data().obj.inverted_grammar[nss].name.split(':')[0];
//       $('.Leaf').each(function(i, x) {
//         const node = $(x);
//         const data = node.data();
//         if (node_value_empty(data) === true) {
//           node.addClass('empty').removeClass('nonempty');
//         } else {
//           node.addClass('nonempty').removeClass('empty');
//         }
//         window.sources_object_add_node(node, data);
//       });
//     }

//     function pending_save_delete(m) {
//       var sel, selector;
//       selector = `#node-${m.node}`;
//       $(selector).remove();
//       // need to improve this, maybe have default list mode enforced somehow?
//       sel = `${selector}-table`;
//       // return $(sel).parents('table').DataTable().row(sel).remove().draw();
//     }
//     let last_added_listitem;
//     function pending_save_change(m) {
//       var n, node, obj, that, value;
//       that = this;
//       obj = $('.Root').data().obj;
//       n = m.node;
//       if (typeof n === 'string' && n.match(/^new\./)) {
//         if(debug) console.log(last_added_listitem);
//         n = last_added_listitem[n.split('.')[1]].meta.id;
//         m.node = `${n}`;
//       }
//       node = `#node-${n}`;
//       $(node).data().value = m.value;
//       $(node).data().meta.user = obj.user_id;
//       $(node).data().meta.task = obj.task_id;
//       nnodes[n].meta.user = obj.user_id;
//       nnodes[n].meta.task = obj.task_id;
//       nnodes[n].value = m.value;
//       value = nnodes[n].value;
//     }
//     function pending_save_add(m) {
//       var a, first, g, listitem, node, obj, that;
//       that = this;
//       obj = $('.Root').data().obj;
//       g = obj.inverted_grammar;
//       first = g[m.value].children[0];
//       a = [first];
//       a = a.concat(g[first].children);
//       listitem = null;
//       $.each(a, function(i, x) {
//         var n, name;
//         if(debug){
//           console.log(m);
//           console.log(g[x]);
//         }
//         name = g[x].name.split(':')[1];
//         obj.last_iid += 1;
//         n = {
//           meta: {
//             name: name,
//             id: obj.last_iid,
//             user: obj.user_id,
//             task: obj.task_id,
//             list: g[x].level === 1,
//             node_class_id: x
//           },
//           value: {
//             value: null
//           }
//         };
//         if (i === 0) {
//           n.children = [];
//           return listitem = n;
//         } else {
//           listitem.children.push(name);
//           return listitem[name] = n;
//         }
//       });
//       // console.log "NODE"
//       // console.log n
//       last_added_listitem = listitem;
//       add_nodes(listitem, nnodes[m.node]);
//       if(debug){
//         console.log('annotate3');
//         console.log(nnodes);
//         console.log(m);
//       }
//       if (nnodes[m.node].children === void 0) {
//         nnodes[m.node].children = [];
//       }
//       if (nnodes[m.node].children_iids === void 0) {
//         nnodes[m.node].children_iids = [];
//       }
//       nnodes[m.node].children.push(listitem);
//       nnodes[m.node].children_iids.push(listitem.meta.id);
//       listitem.meta.parent = nnodes[m.node];
//       listitem.added = true;
//       init_node2(listitem, nnodes[m.node]);
//       return null;
//     }
//     function after_annotate(messages, workflow, global_object) {
//       var m;
//       ////reset this flag to false if it was set for the last group of annotations
//       // if(changing_list_item) changing_list_item = false;
//       if(debug){
//         console.log('AFTER');
//         console.log(messages);
//       }
//       if ($('.Root').length === 0) {
//         return;
//       }
//       logic(workflow, global_object);
//       if ($('.log').length !== 1) {
//         $('.Root').after('<div class="log hidden"></div>');
//       }
//       m = [];
//       $.each(messages, function(i, x) {
//         return m.push(['div', 'class', 'message', JSON.stringify(x)]);
//       });
//       return $('.log').append(array2html(['div', 'class', 'messages', m]));
//     }

//     window.pending_save_add = pending_save_add;
//     window.pending_save_change = pending_save_change;
//     window.pending_save_delete = pending_save_delete;
//     window.after_annotate = after_annotate;

  window.get_constraint = function(k) {
      return $('.Root').data().obj.meta.constraints[k];
    }
//     let promises;
//     const services = {};
//     const servicesn = {};
//     let create_promises_url;
    window.services_init = function() {
      return null;
      return getp_simple(endpoint).then(function(data) {
        console.log('SERVICES');
        console.log(data); //data.jsonapi.meta.types
        promises = data.promises;
        create_promises_url = `${endpoint}${promises.create_promise.uri}`;
        return $.each(data.promises.create_promise.schema, function(i, x) {
          return $.each(x, function(k, v) {
            return window.wait_for('.middle', function() {
              var ii;
              ii = `${i + 1}`;
              $('.middle').append(array2html(['div', `${ii} ${k}`]));
              services[k] = v;
              servicesn[ii] = k;
              if (k === 'sad') {
                console.log(`${endpoint}${v}`);
                return getp_simple(`${endpoint}${v}`).then(function(data) {
                  console.log('here');
                  console.log(data);
                  return $.each(data.required, function(i, x) {
                    return console.log(data.properties[x]);
                  });
                });
              }
            });
          });
        });
      });
    }
//     window.align = function(data2, f22) {
//       var f3, url;
//       f3 = function(url3) {
//         var o;
//         console.log('BIGDaA');
//         console.log(data2);
//         o = {
//           type: "alignment",
//           data: {
//             // wav: "/NIEUW02/promises/sad_in/#{w.wave_docid}.wav",
//             audio: data2.audio,
//             transcript: url3
//           }
//         };
//         console.log('thisurl');
//         console.log(url3);
//         return postp(create_promises_url, o).then( function(oo) {
//           var f, url2;
//           url2 = oo.promiseStatusUrl;
//           url2 = `${create_promises_url}/${oo.id}`;
//           f = function() {
//             console.log(url2);
//             return getp(url2).then( function(data) {
//               console.log("ALIGN");
//               console.log(data);
//               $('.waiting').append('*');
//               if (data.status === 'resolved') {
//                 console.log('ALIGNDONE');
//                 $('.waiting').remove();
//                 // $.get data.result, (data) ->
//                 //     f2 data
//                 // , 'text'
//                 return data2.f22(data.result);
//               } else {
//                 return setTimeout(function() {
//                   return f();
//                 }, 1000);
//               }
//             });
//           };
//           return f();
//         });
//       }
//       return $.ajax({
//         type: 'POST',
//         url: url,
//         data: data2.text,
//         contentType: 'text/plain',
//         success: f3
//       });
//     }

function namespace(ldc){
  setup(ldc);
  init(ldc);
  // .then( () => {
  //   const s = localStorage.getItem('script')
  //   if(s){
  //     if(s.match(/local/)){
  //       console.log("SCRIPT")
  //       cd.waveform.set_times_then_draw(0, 3);
  //     }
  //   }
  // });
}

function main(){
  if(window.ldc_work_work){
    work(window.ldc_work_work);
  }
  else{
    setTimeout( main, 500 );
  }
}

export { main }
