// Every downloadable resource the app knows about. Imported by the Downloaded
// resources dialog, so each one is registered before anything has loaded it —
// add a new module's registration here, even before anything uses it.
//
// A new WASM module, for instance:
//
//   // resources/vad.js
//   import { define_wasm_module } from './registry';
//   export const vad = define_wasm_module({ id: 'vad', label: 'Voice activity detector',
//       description: 'Finds speech', files: { wasm: '/modules/vad-1.0.0.wasm' } });
//
// and `import './vad';` below. See registry.js.

import './speech';
import { define_wasm_module, register_resource, registered } from './registry';

export * from './registry';

// Reachable from the console and the browser harness (script/resources_auto.rb),
// which defines a stand-in module to show a new one works without a line of
// the dialog changing.
if(typeof window !== 'undefined') window.ldc_resources = { define_wasm_module, register_resource, registered };
