import { writable } from 'svelte/store'
const t = {
  wave_display_offset: 0,
  wave_display_length: 0
};
const times = writable(t);
const s = {
  wave_selection_offset: null,
  wave_selection_length: 0,
  wave_selection_end: null
};
const selection = writable(s);

const round_to_1_place = (num) => Math.round(num * 10) / 10;
const round_to_2_places = (num) => Math.round(num * 100) / 100;
const round_to_3_places = (num) => Math.round(num * 1000) / 1000;
const round_to_6_places = (num) => Math.round(num * 1000000) / 1000000;
function delay(w,x,y){
  setTimeout( () => {
    set_times(w,x,y);
  }, 1000);
}

export {
  times,
  selection,
  round_to_1_place,
  round_to_2_places,
  round_to_3_places,
  round_to_6_places
}
