import { settings, spectrogram_settings } from './lib/ldcjs/waveform/stores';

// mostly copied from MDN
function setup(ldc){
  settings.subscribe( (x) => save_settings(ldc, x, 'settings') );
  spectrogram_settings.subscribe( (x) => save_settings(ldc, x, 'spectrogram') );
  let request = indexedDB.open('settings', 2);

  // onerror handler signifies that the database didn't open successfully
  request.onerror = function() {
    console.log('Database failed to open');
  };

  // onsuccess handler signifies that the database opened successfully
  request.onsuccess = function() {
    console.log('Database opened successfully');
    // Store the opened database object in the db variable. This is used a lot below
    ldc.vars.db = request.result;
    // create_settings();
    load_settings(ldc, 'settings');
    load_settings(ldc, 'spectrogram');
  };

  // Setup the database tables if this has not already been done
  request.onupgradeneeded = function(e) {
    // Grab a reference to the opened database
    let db = e.target.result;
    // Create an objectStore to store our notes in (basically like a single table)
    // including a auto-incrementing key
    if(e.oldVersion < 1){
      let objectStore = db.createObjectStore('spectrogram', { keyPath: 'id', autoIncrement:true });
      // Define what data items the objectStore will contain
      objectStore.createIndex('key', 'key', { unique: true });
    }
    if(e.oldVersion < 2){
      let objectStore = db.createObjectStore('settings', { keyPath: 'id', autoIncrement:true });
      // Define what data items the objectStore will contain
      objectStore.createIndex('key', 'key', { unique: true });
    }
    console.log('Database setup complete');
  };
}

// Define the create_settings() function
function create_settings(ldc, name) {
  // grab the values entered into the form fields and store them in an object ready for being inserted into the DB
  let newItem = { key: 'settings' };
  // open a read/write db transaction, ready for adding the data
  let transaction = ldc.vars.db.transaction([name], 'readwrite');
  // call an object store that's already been added to the database
  let objectStore = transaction.objectStore(name);
  // Make a request to add our newItem object to the object store
  let request = objectStore.add(newItem);

  request.onsuccess = function() {
    // Clear the form, ready for adding the next entry
    console.log('success')
  };

  // Report on the success of the transaction completing, when everything is done
  transaction.oncomplete = function() {
    console.log('Transaction completed: database modification finished.');
    load_settings(ldc, name);
  };

  transaction.onerror = function() {
    console.log('Transaction not opened due to error');
  };

}

function load_settings(ldc, name) {
  let found = false;
  let s;
  if(name == 'settings')         s = settings;
  else if(name == 'spectrogram') s = spectrogram_settings;
  // Open our object store and then get a cursor - which iterates through all the
  // different data items in the store
  let objectStore = ldc.vars.db.transaction(name).objectStore(name);
  objectStore.openCursor().onsuccess = function(e) {
    // Get a reference to the cursor
    let cursor = e.target.result;
    // If there is still another data item to iterate through, keep running this code
    if(cursor) {
        console.log(cursor.value);
        if(cursor.value.key == 'settings'){
            found = true;
            ldc.vars[name + '_id'] = cursor.value.id;
            s.update( (x) => {
                for(let k in cursor.value){
                    x[k] = cursor.value[k];
                }
                x.loaded = true;
                return x;
            })
        }
      // Iterate to the next item in the cursor
      cursor.continue();
    } else {
      // if there are no more cursor items to iterate through, say so
      console.log('Notes all displayed');
    }
  };
  if(!found) create_settings(ldc, name);
}

function save_settings(ldc, x, name){
    if(!x.loaded) return;
    const objectStore = ldc.vars.db.transaction([name], "readwrite").objectStore(name);
    const request = objectStore.get(ldc.vars[name + '_id']);
    request.onerror = event => {
      // Handle errors!
    };
    request.onsuccess = event => {
      // Get the old value that we want to update
      const data = event.target.result;

      // update the value(s) in the object that you want to change
      if(name == 'settings'){
        data.open = x.open;
        data.sections_open = x.sections_open;
        data.spectrogram_open = x.spectrogram_open;
        data.experimental = x.experimental;
      }
      else if(name == 'spectrogram'){
        data.spectrogram_open = x.spectrogram_open;
        data.wave_canvas_height = x.wave_canvas_height;
        data.height = x.height;
        data.fft_size = x.fft_size;
        data.frame_time = x.frame_time;
        data.time_step = x.time_step;
      }

      // Put this updated object back into the database.
      const requestUpdate = objectStore.put(data);
      requestUpdate.onerror = event => {
         // Do something with the error
      };
      requestUpdate.onsuccess = event => {
         // Success - the data is updated!
      };
    };
}

export { setup }
