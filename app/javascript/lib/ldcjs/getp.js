import { local_file_for, read_local_range } from './local_audio';
function get_init(){
    return {
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
      },
      credentials: 'same-origin'
    };
  };
  function get_init_simple(){
    return {
      headers: {
        'Accept': 'application/json'
      }
    };
  };
  function get_init_wav(b, e){
    return {
      headers: {
        range: `bytes=${b}-${e}`,
        "Cache-Control": "no-cache, no-store"
      }
    };
  };
  function jsons(obj){
    return JSON.stringify(obj);
  }
  function post_init(o){
    const h = get_init();
    h.method = 'POST';
    h.body = jsons(o);
    return h;
  }
  function post_initf(o){
    const h = get_init();
    delete h.headers['Content-Type'];
    h.method = 'POST';
    h.body = o; // form data
    return h;
  }
  function patch_init(o){
    const h = get_init();
    h.method = 'PATCH';
    h.body = jsons(o);
    return h;
  }
  function delete_init(o){
    const h = get_init();
    h.method = 'DELETE';
    return h;
  }
  // A failed response, saying why where that matters to the caller: the
  // session ended (the server's 401, or a redirect that landed on the sign-in
  // form) as against anything else. modification2.js holds unsaved edits for
  // the first, and reports the second.
  function response_error(r){
    const e = new Error('response error');
    e.status = r.status;
    let landed = '';
    try { landed = new URL(r.url).pathname; } catch(_) {}
    e.session_expired = r.status === 401 || (r.redirected && landed === '/session/new');
    return e;
  }

  function responsef(r){
    const failure = response_error(r);
    // An ok status after a redirect to the sign-in form is still a failure.
    if(r.ok && !failure.session_expired) {
      const type = r.headers.get("content-type");
      if (type && type.includes("application/json")) {
        return r.json();
      } else if (type && type.includes("text/xml")) {
        return r.text();
      } else if (type && type.includes("text/plain")) {
        return r.text();
      } else if (type && type.includes("text/tab-separated-values")) {
        return r.text();
      } else if (type && type.includes("audio/wav")) {
        return r.arrayBuffer();
      } else if (type && type.includes("audio/x-wav")) {
        return r.arrayBuffer();
      }
    }
    throw failure;
  }
  
  function getp(url){
    return fetch(url, get_init()).then(responsef).catch(function(e) {
      return console.error('Error:', e);
    });
  }
  function getp_no_catch(url){
    return fetch(url, get_init()).then(responsef);
  }
  function postp(url, o){
    return fetch(url, post_init(o)).then(responsef).catch(function(e) {
      return console.error('Error:', e);
    });
  }
  function postp_no_catch(url, o){
    return fetch(url, post_init(o)).then(responsef);
  }
  function postpf_no_catch(url, o){
    return fetch(url, post_initf(o)).then(responsef);
  }
  function patchp(url, o){
    return fetch(url, patch_init(o)).then(responsef).catch(function(e) {
      return console.error('Error:', e);
    });
  }
  function deletep(url, o){
    return fetch(url, delete_init(o)).then(responsef).catch(function(e) {
      return console.error('Error:', e);
    });
  }
  function getp_wav(url, b, e) {
    // A local_audio kit's file: read the range off disk rather than fetch the
    // blob: url, whose Range support differs between browsers.
    const file = local_file_for(url);
    if(file) return read_local_range(file, b, e).catch(function(e) {
      return console.error('Error reading local audio:', e);
    });
    return fetch(url, get_init_wav(b, e)).then(responsef).catch(function(e) {
      return console.error('Error:', e);
    });
  }
  function getp_simple(url) {
    return fetch(url, get_init_simple()).then(responsef).catch(function(e) {
      return console.error('Error:', e);
    });
  };
  export {
    getp,
    postp,
    patchp,
    deletep,
    getp_wav,
    getp_simple,
    getp_no_catch,
    postp_no_catch,
    postpf_no_catch
  }
  
