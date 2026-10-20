// Which letter opens which entry in the speaker and section menus.
//
// Those menus mix two kinds of row. A few are functions of the menu itself and
// have fixed letters people know: N for "new section" / "new speaker", R for
// "replace speaker". The rest are the speakers or sections in play, which are
// handed letters in order as they appear — arbitrary, and different from one
// kit to the next.
//
// The arbitrary ones have to give way to the fixed ones. Counting a, b, c…
// straight through meant the fourteenth name landed on N and quietly replaced
// "new section" in the keymap: the menu then listed two rows under N and the
// only way to name a section that wasn't in the list had gone. Sections are
// numerous enough for fourteen to be an ordinary afternoon.
//
// Kept apart from helpers.js, which can't be imported without most of the
// waveform coming with it, so this can be tested on its own.

export const LETTERS = Array.from({ length: 26 }, (_, i) => String.fromCharCode(97 + i));

// One letter per name, skipping any the menu has already bound to a function of
// its own. `taken` is the keymap as it stands — whatever is in it is spoken
// for. Names past the end of the alphabet come back with `key: null`: there is
// no letter to give them, and saying so beats binding them to `undefined`,
// which is what running off the end used to do.
export function assign_menu_keys(names, taken = {}, alphabet = LETTERS) {
  const free = alphabet.filter((letter) => !(letter in taken));
  return names.map((name, i) => ({ name, key: i < free.length ? free[i] : null }));
}
