// The tool's event bus: components announce what they drew or did, as
// event.dispatch(node, 'drew_waveform') or as the Svelte action
// use:event.dispatch={'drew_waveform'}, and the action form announces
// 'destroy_<type>' when the node goes. Nothing in the tool itself listens;
// the calls are there for whatever does, such as a guided tour.
export const event = new EventTarget();
event.dispatch = function(node, type){
  event.dispatchEvent(new CustomEvent(type, { detail: node }));
  return {
    destroy() {
      event.dispatchEvent(new CustomEvent('destroy_' + type, { detail: node }));
    }
  };
};
