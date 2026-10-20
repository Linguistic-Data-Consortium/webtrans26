import { postp, postp_no_catch } from '../getp';
import { report_desync } from './desync.svelte';
const debug = false;
let messages = []; // message(s) to send to the annotate controller
const submissions = {}; // messages sent
let annotations_promise = Promise.resolve();
//this function adds a message to the queue for annotation
let ldc;
// The waveform installs this to keep its annotation graph in step with the
// messages; tools that don't hold one leave it unset.
function apply_to_graph(m, n, v){
    if(ldc && ldc.apply_to_graph) ldc.apply_to_graph(m, n, v);
}
function setldc(x){
  ldc = x;
}
function add_message(n, m, v){
    if(m == 'add'){
        // console.log('aaaaaaaaaaaaa')
        // console.log(n)
        // console.log(nodes[n])
        // console.log(ldc_nodes.get_node_class(nodes[n].meta.node_class_id))
        if(ldc && ldc.addf){
            // Where a new group's iids come from. The waveform allocates and
            // encodes it on the graph side; the node layer is then built to
            // match. Without a graph, addf allocates as it always did.
            v = ldc.allocate_group ? ldc.allocate_group(n) : null;
            v = ldc.addf(n, v);
            n = '0';
            apply_to_graph(m, n, v);
        }
        else{
            v = window.nodes[n].meta.node_class_id;
        }
    }
    if(m == 'change' && ldc && ldc.changef){
        // Resolve "new.Text" to the iid addf just allocated, tell the graph, and
        // only then update the node layer — in that order, because setting a
        // node's value notifies its subscribers, which re-sort the transcript,
        // which reads the graph rows. Applying afterwards renders one message
        // behind and makes every edit look like a disagreement.
        if(typeof(n) == 'string' && n.substring(0, 4) == 'new.' && ldc.resolve_new){
            const iid = ldc.resolve_new(n.substring(4));
            if(iid != null) n = iid;
        }
        apply_to_graph(m, n, v);
        // Where there's a graph, it holds the value and nothing reads the node
        // layer's copy — so don't write one. changef's other job, turning a
        // string iid into a number, still has to happen: the message carries it.
        if(ldc.apply_to_graph){
            if(typeof(n) == 'string') n = parseInt(n);
        }
        else{
            n = ldc.changef(n, v);
        }
    }
    if(m == 'delete' && ldc && ldc.deletef){
        apply_to_graph(m, n, v);
        ldc.deletef(n);
    }
    if(n == '0' && ldc) n = 0;
    messages.push( { node: n, message: m, value: v } );
}
function add_message_listitem(list, child_values_to_add){
    add_message_listitem_by_id($(`.${list}`).data().meta.id, child_values_to_add);
}
function add_message_listitem_by_id(id, child_values_to_add, callback, nosubmit = false) {
    add_message(id, 'add', null);
    $.each(child_values_to_add, function(i, x) {
      // x[0] is node name, x[1] is value
      add_message(`new.${x[0]}`, 'change', x[1]);
    });
    if (!nosubmit) {
      submit_form();
    }
    if (callback) {
      add_callback(callback);
    }
}

function submit_form(){
    var m = [];
    m = messages.slice();
    messages = [];
    annotations_promise = annotations_promise.then( function(){
        return submit_form_old(m);
    });
}

function add_callback(f){
    annotations_promise = annotations_promise.then(f);
}

let d;

//this is the function which actually submits annotations to the annotate action in the annotate controller
function submit_form_old(m){
    var messages = m;
    var promise = Promise.resolve();
    if(debug) console.log( 'SUBMIT' )
    var obj = {};
    obj.messages = messages;
    d = new Date();
    obj.client_time = d.getTime();
    obj.kit_uid = ldc.obj2._id
    if(messages.length > 0){
        if(ldc.obj2.read_only){
            var mmessage = 'read only, json request would have been: ' + JSON.stringify(obj);
            alert(mmessage);
        }
        else{
            var url = '/annotations';
            submissions[obj.client_time] = obj
            pending_save_before(messages);
            promise = postp_no_catch(url, { task_user_id: ldc.obj2.task_user_id, json: JSON.stringify(obj) }).then(function(data){ if(debug) console.time('annotate2'); annotate2(data, obj.client_time); if(debug) console.timeEnd('annotate2'); });
            obj.received = false;
            submissions[obj.client_time] = obj;
        }
        messages = [];
    }
    return promise;
}

  // Each response is checked against the message it answers. Pairing is by
  // position *within the request* — `submissions[client_time].messages` is what
  // went out, and the server replies in the same order.
  //
  // This used to pair through one monotonic counter across every request, which
  // worked until a request failed: those messages were recorded as sent and
  // never answered, so the counter fell permanently behind and every later
  // response was compared against the wrong message. The check didn't stop
  // working, which would have been noticeable — it started reporting mismatches
  // that weren't real, for the rest of the session.
  function confirm_message(m, sent, i) {
    var problem;
    if(debug) console.log('confirming');
    if(m.beg) m.type = 'real';
    if (sent) {
      if (m.message !== sent.message) {
        console.log(m);
        console.log(sent);
        report_desync(
          'The server answered a different change than the one sent.',
          { index: i, sent: sent, received: m }
        );
        if (m.error) {
          return alert(m.error);
        }
      } else {
        switch (m.message) {
          case 'change':
            if (m.old_id !== parseInt(sent.node)) {
              return report_desync(
                'A change was recorded against the wrong part of the transcript.',
                { index: i, sent: sent, received: m }
              );
            } else if (!node_value_compare(m.node.value, sent.value)) {
              // The server's value is its replay of the log, so this is the real
              // check: what was typed is not what was stored.
              return report_desync(
                "A change didn't save as typed.",
                { index: i, sent_value: sent.value, stored_value: m.node.value }
              );
            } else {
              if(debug) console.log(`message ${i} ok`);
              return;
            }
            break;
          case 'add':
            if (m.old_id !== parseInt(sent.node)) {
              return report_desync(
                'A new segment was recorded against the wrong list.',
                { index: i, sent: sent, received: m }
              );
            } else {
              problem = false;
              $.each(m.nodes, function(i, x) {
                var id, name;
                if (i === 0) {
                  id = x.iid;
                  name = x.name;
                } else {
                  id = x.meta.id;
                  name = x.meta.name;
                }
                if(ldc.obj){
                  for(let y of ldc.obj.nodes){
                    if(y.iid == id){
                      if (y.name !== name) {
                        console.log('problem')
                        console.log(x);
                        return problem = true;
                      }
                    }
                  }
                }
                else{
                  if ($(`#node-${id}`).data().meta.name !== name) {
                    return problem = true;
                  }
                }
              });
              if (problem) {
                // Previously called error_in_message(), which was never defined
                // anywhere — so this branch threw a TypeError instead of
                // reporting a divergence.
                return report_desync(
                  "A new segment's structure didn't match what the server stored.",
                  { index: i, sent: sent, received: m }
                );
              } else {
                if(debug){
                  console.log(sent);
                  console.log(`message ${i} ok`);
                }
                return;
              }
            }
            break;
          case 'delete':
            if(debug) console.log('delete');
            return;
          case 'done':
            return console.log('done');
          default:
            return report_desync(
              'The server replied with a change this page does not understand.',
              { index: i, sent: sent, received: m }
            );
        }
      }
    } else {
      return report_desync(
        'The server sent back more changes than were made.',
        { index: i, received: m }
      );
    }
  }
  function node_value_compare(x, y) {
    var b, k, v, yy;
    if (typeof x === 'undefined') {
      // console.log 'xxxx'
      // console.log typeof(x)
      // console.log x
      // console.log y
      return false;
    }
    if (x.value === "" && y.value === "") {
      // console.log 'xxx'
      // console.log x
      // console.log y
      return true;
    }
    if (x.value === "") {
      // console.log JSON.stringify({value: null})
      // console.log JSON.stringify(y)
      return JSON.stringify({
        value: null
      }) === JSON.stringify(y);
    } else {
      // alert(JSON.stringify(x))
      // alert(JSON.stringify(y));
      // alert(JSON.stringify(x) is JSON.stringify(y));
      // console.log 'xx'
      // console.log x
      // console.log y
      // console.log JSON.stringify(x)
      // console.log JSON.stringify(y)
      yy = {};
      for (k in y) {
        v = y[k];
        if (k !== 'level' && k !== 'node' && k !== 'timestamps') {
          yy[k] = v;
        }
      }
      if(x['type']) yy['type'] = x['type'];
      return JSON.stringify(x) === JSON.stringify(yy);
    }
    b = true;
    $.each(['value'], function(i, k) {
      if (x[k] !== y[k]) {
        return b = false;
      }
    });
    return b;
  }

function pending_save_before(messages){
  if(debug){
    console.log('pending_save_before');
    console.log(messages);
  }
    // Nothing to record here any more: the request itself is kept in
    // `submissions`, and that is what the responses are checked against. The
    // window.pending_save_* / after_annotate calls that used to sit here were
    // the pre-node-layer tool's way of updating its DOM; nothing renders that
    // way now.
}

function annotate2(messages, client_time){
    if(debug) console.log(client_time);
    submissions[client_time].received = true;
    if(!messages){
      // No reply at all. Whether the write landed is unknown, so the page
      // cannot be trusted either way. Replaces a bare alert() that said this
      // without saying what to do — and that blocked the page while it sat
      // there, including the scripted harnesses.
      return report_desync(
        'A change could not be saved — the server did not respond.',
        { client_time: client_time }
      );
    }
    if(messages.error){
        console.error(messages.error)
        if(messages.full_error) console.log(messages.full_error);
        return report_desync(
          'A change was refused by the server.',
          { error: messages.error, full_error: messages.full_error }
        );
    }
    if(debug){
      console.log("ANN2")
      console.log(messages)
    }
    // What went out, so each reply can be checked against the message it
    // answers. A redirect or a whole-batch error comes back as a single hash
    // that answers no particular message, which is why `sent` may be undefined
    // and confirm_message tolerates that.
    const sent_messages = submissions[client_time] ? submissions[client_time].messages : [];
    $.each(messages, function(i, hash){
      if(debug){
        console.log('getting message');
        console.log(hash);
      }
        confirm_message(hash, sent_messages[i], i);
        if(hash.hasOwnProperty('noop')){
            return;
        }
        if(hash.hasOwnProperty('error')){
            if(hash.error === 'This tree is locked.'){
                // Another session holds the tree's write lock, so this page's
                // changes are not being recorded. This used to add a class to
                // #tree_locked_modal, which no view has rendered since the
                // Svelte rewrite — so a lock collision was entirely silent.
                report_desync(
                  hash.current
                    ? 'This transcript is open in another window, and that one holds the lock.'
                    : 'Another session is editing this transcript, so changes here are not being saved.',
                  { error: hash.error, current: hash.current }
                );
            }
            else{
                $('#message_dialog').html(hash.error).dialog('option', 'title', 'Error').dialog('open');
            }
            return;
        }
        if(hash.hasOwnProperty('redirect')){
            if(hash.message === 'inactive'){
                $('.ann_pane').html('<h1>This tasks is inactive, redirecting.</h1>')
                setTimeout( function(){
                    window.location.href = hash.redirect;
                }, 3000);
                return;
            }
            else{
                $('.ann_pane').html('');
                window.location.href = hash.redirect;
                return;
            }
        }
        if(ldc && ldc.obj){
            $('#node-0-dummy').remove();
            return;
        }
    });
}


export { setldc, add_message, add_message_listitem, submit_form, add_callback }
