// Single source of truth for keyboard bindings AND cheat-sheet content.
//
// Every binding is an object: { action, desc, group, label? }
//   action: function name returned by fmap_helper
//   desc:   human-readable description (shows in the cheat sheet)
//   group:  cheat-sheet section: 'home' | 'mode' | 'system' | 'global'
//   label:  optional display key (defaults to the actual key, e.g. ' ' → 'space')
//   dir, size: extra positional metadata for home-row keys
//
// The cheat sheet (MainHelpDialog.svelte) iterates these maps and shows
// every entry. The keymaps (waveform/input/playback) are consumed by
// fmap_helper, which extracts `.action`.

// ─── Mode metadata (shared with the channels.svelte mode banner) ───────────

const modes = [
    { id: 'cursor',    name: 'Cursor',    key: 'c', bg: 'bg-red-100',     text: 'text-red-900',     desc: 'Home keys move the red cursor line.' },
    { id: 'window',   name: 'Window',    key: 'w', bg: 'bg-blue-100',    text: 'text-blue-900',    desc: 'Home keys scroll the waveform window.' },
    { id: 'selection', name: 'Selection', key: 'b', bg: 'bg-emerald-100', text: 'text-emerald-900', desc: 'd/f move begin edge; j/k move end edge (smallest step).' }
];

const mode_palette = Object.fromEntries(
    modes.map(m => [m.id, { label: m.name, bg: m.bg, text: m.text }])
);

// Home-row positions, outer→inner→inner→outer.
const home_keys = [
    { k: 'a', size: 'largest'  },
    { k: 's', size: 'large'    },
    { k: 'd', size: 'medium'   },
    { k: 'f', size: 'smallest' },
    { k: 'j', size: 'smallest' },
    { k: 'k', size: 'medium'   },
    { k: 'l', size: 'large'    },
    { k: ';', size: 'largest'  }
];

// ─── Waveform keymap (cursor / window / selection + ctrl submap) ──────────

const waveform_map = {
    cursor: {
        Escape: { action: 'open_mode_menu', desc: 'Open mode menu',                                 group: 'system', label: 'esc' },
        '/':    { action: 'open_mode_menu', desc: 'Open mode menu',                                 group: 'system' },
        c:      { action: 'command',        desc: 'Open command palette',                           group: 'global' },
        Tab:    { action: 'focus_input',    desc: 'Focus the text input box',                       group: 'global', label: 'tab' },
        ' ':    { action: 'play_current_span_or_play_stop', desc: 'Play / stop (plays selection if one exists)', group: 'global', label: 'space' },
        Enter:  { action: 'play_current_span_and_add_transcript_line_and_activate', desc: 'Create segment from selection', group: 'global', label: 'enter' },
        '0':    { action: 'open_spectrogram',          desc: 'Open spectrogram',                    group: 'global' },
        z:      { action: 'toggle_zoom',               desc: 'Toggle zoom in & out',                group: 'global' },
        i:      { action: 'zoom_in',                   desc: 'Zoom in',                             group: 'global' },
        o:      { action: 'zoom_out',                  desc: 'Zoom out',                            group: 'global' },
        p:      { action: 'play_head_menu',            desc: 'Open playback menu',                  group: 'global' },
        r:      { action: 'refresh_waveform',          desc: 'Refresh waveform',                    group: 'global' },
        q:      { action: 'settings',                  desc: 'Open settings',                       group: 'global' },
        h:      { action: 'show_help_screen_main',     desc: 'Show this cheat sheet',               group: 'global' },
        '@':    { action: 'not_sure',                  desc: '(placeholder — not_sure)',            group: 'system' },
        D:      { action: 'delete_all_confirm',        desc: 'Delete all (confirm)',                group: 'global' },
        w:      { action: 'set_mode_to_window',        desc: 'Switch to Window mode',               group: 'mode' },
        b:      { action: 'set_mode_to_selection',     desc: 'Switch to Selection mode',            group: 'mode' },
        e:      { action: 'set_mode_to_selection',     desc: 'Switch to Selection mode',            group: 'mode' },
        // Home keys: left hand moves backward, right hand moves forward.
        f:   { action: 'move_cursor_lstep1', desc: 'Cursor backward (smallest)', group: 'home', dir: 'left',  size: 'smallest' },
        d:   { action: 'move_cursor_lstep2', desc: 'Cursor backward (medium)',   group: 'home', dir: 'left',  size: 'medium' },
        s:   { action: 'move_cursor_lstep3', desc: 'Cursor backward (large)',    group: 'home', dir: 'left',  size: 'large' },
        a:   { action: 'move_cursor_lstep4', desc: 'Cursor backward (largest)',  group: 'home', dir: 'left',  size: 'largest' },
        j:   { action: 'move_cursor_rstep1', desc: 'Cursor forward (smallest)',  group: 'home', dir: 'right', size: 'smallest' },
        k:   { action: 'move_cursor_rstep2', desc: 'Cursor forward (medium)',    group: 'home', dir: 'right', size: 'medium' },
        l:   { action: 'move_cursor_rstep3', desc: 'Cursor forward (large)',     group: 'home', dir: 'right', size: 'large' },
        ';': { action: 'move_cursor_rstep4', desc: 'Cursor forward (largest)',   group: 'home', dir: 'right', size: 'largest' },
        x:   { action: 'speaker_test',                 desc: 'Speaker test',                        group: 'global' },
        ',': { action: 'split_segment_at_cursor',      desc: 'Split active segment at cursor',      group: 'global' },
        m:   { action: 'merge_with_following_segment', desc: 'Merge active segment with following', group: 'global' },
        ArrowUp:   { action: 'set_active_transcript_line_to_prev', desc: 'Active segment: previous', group: 'global', label: '↑' },
        ArrowDown: { action: 'set_active_transcript_line_to_next', desc: 'Active segment: next',     group: 'global', label: '↓' },
        n:   { action: 'set_active_transcript_line_to_next', desc: 'Active segment: next',          group: 'global' },
        u:   { action: 'upload_transcript',            desc: 'Upload transcript',                   group: 'global' }
    },
    window: {
        Escape: { action: 'open_mode_menu',        desc: 'Open mode menu',           group: 'system', label: 'esc' },
        '/':    { action: 'open_mode_menu',        desc: 'Open mode menu',           group: 'system' },
        c:      { action: 'set_mode_to_cursor',    desc: 'Switch to Cursor mode',    group: 'mode' },
        b:      { action: 'set_mode_to_selection', desc: 'Switch to Selection mode', group: 'mode' },
        e:      { action: 'set_mode_to_selection', desc: 'Switch to Selection mode', group: 'mode' },
        f:   { action: 'move_window_lstep1', desc: 'Window backward (smallest)', group: 'home', dir: 'left',  size: 'smallest' },
        d:   { action: 'move_window_lstep2', desc: 'Window backward (medium)',   group: 'home', dir: 'left',  size: 'medium' },
        s:   { action: 'move_window_lstep3', desc: 'Window backward (large)',    group: 'home', dir: 'left',  size: 'large' },
        a:   { action: 'move_window_lstep4', desc: 'Window backward (largest)',  group: 'home', dir: 'left',  size: 'largest' },
        j:   { action: 'move_window_rstep1', desc: 'Window forward (smallest)',  group: 'home', dir: 'right', size: 'smallest' },
        k:   { action: 'move_window_rstep2', desc: 'Window forward (medium)',    group: 'home', dir: 'right', size: 'medium' },
        l:   { action: 'move_window_rstep3', desc: 'Window forward (large)',     group: 'home', dir: 'right', size: 'large' },
        ';': { action: 'move_window_rstep4', desc: 'Window forward (largest)',   group: 'home', dir: 'right', size: 'largest' }
    },
    selection: {
        Escape: { action: 'open_mode_menu',        desc: 'Open mode menu',           group: 'system', label: 'esc' },
        '/':    { action: 'open_mode_menu',        desc: 'Open mode menu',           group: 'system' },
        c:      { action: 'set_mode_to_cursor',    desc: 'Switch to Cursor mode',    group: 'mode' },
        w:      { action: 'set_mode_to_window',    desc: 'Switch to Window mode',    group: 'mode' },
        // d/f move the begin edge; j/k move the end edge. Outer keys (d, k)
        // expand the selection, inner keys (f, j) shrink it.
        d:   { action: 'move_beg_left',  desc: 'Begin edge ← (expand)', group: 'home', dir: 'left',  size: 'smallest', edge: 'beg' },
        f:   { action: 'move_beg_right', desc: 'Begin edge → (shrink)', group: 'home', dir: 'right', size: 'smallest', edge: 'beg' },
        j:   { action: 'move_end_left',  desc: 'End edge ← (shrink)',   group: 'home', dir: 'left',  size: 'smallest', edge: 'end' },
        k:   { action: 'move_end_right', desc: 'End edge → (expand)',   group: 'home', dir: 'right', size: 'smallest', edge: 'end' }
    },
    control: {
        // Modifier-key bindings. The modifier itself is configurable in the
        // settings dialog; labels here are just the bare key.
        cursor: {
            Enter: { action: 'play_current_span_and_add_transcript_line_and_activate', desc: 'Create segment from selection', group: 'global', label: 'enter' },
            i:     { action: 'info',        desc: 'Info',         group: 'global' },
            s:     { action: 'spectrogram', desc: 'Spectrogram',  group: 'global' },
            h:     { action: 'header',      desc: 'Header',       group: 'global' }
        }
    }
};

// ─── Text-input keymap (active when input box is focused) ─────────────────

const input_map = {
    Escape: { action: 'open_mode_menu',                                   desc: 'Return to waveform / open mode menu', group: 'global', label: 'esc' },
    '/':    { action: 'open_mode_menu',                                   desc: 'Return to waveform / open mode menu', group: 'global' },
    Enter:  { action: 'set_active_transcript_line_to_next_and_play_current_span', desc: 'Jump to next line and play',  group: 'global', label: 'enter' },
    Tab:    { action: 'keyboard_focus',                                   desc: 'Focus the keyboard icon (leave input)', group: 'global', label: 'tab' },
    ArrowUp:   { action: 'set_active_transcript_line_to_prev', desc: 'Active line: previous', group: 'global', label: '↑' },
    ArrowDown: { action: 'set_active_transcript_line_to_next', desc: 'Active line: next',     group: 'global', label: '↓' },
    control: {
        // Modifier-key bindings. The modifier itself is configurable in the
        // settings dialog; labels here are just the bare key.
        j: { action: 'add_to',                       desc: 'Add to existing segment',             group: 'global' },
        s: { action: 'set_speaker',                  desc: 'Set speaker',                         group: 'global' },
        ' ': { action: 'play_current_span',          desc: 'Play current span',                   group: 'global', label: 'space' },
        d: { action: 'delete_active_transcript_line',desc: 'Delete current line',                 group: 'global' },
        ',': { action: 'split_segment_at_cursor',    desc: 'Split active segment at cursor',      group: 'global' },
        m: { action: 'merge_with_following_segment', desc: 'Merge active segment with following', group: 'global' },
        '[': { action: 'open_section',               desc: 'Open section',                        group: 'global' },
        ']': { action: 'close_section',              desc: 'Close section',                       group: 'global' },
        '\\':{ action: 'show_sections',              desc: 'Show sections',                       group: 'global' },
        v: { action: 'validate_transcript',          desc: 'Validate transcript',                 group: 'global' },
        p: { action: 'play_head_menu',               desc: 'Open playback menu',                  group: 'global' },
        n: { action: 'generic_next',                 desc: 'Generic next',                        group: 'global' },
        r: { action: 'tag_redact',                   desc: 'Tag: redact',                         group: 'global' },
        u: { action: 'tag_unintelligible',           desc: 'Tag: unintelligible',                 group: 'global' },
        l: { action: 'tag_laugh',                    desc: 'Tag: laugh',                          group: 'global' },
        g: { action: 'tag_sing',                     desc: 'Tag: sing',                           group: 'global' }
    }
};

// ─── Playback-menu keymap (active inside the playback menu, opened with `p`) ─

const playback_map = {
    c:   { action: 'play_from_cursor',              desc: 'Play from cursor',                      group: 'global' },
    '[': { action: 'play_from_selection_beg',       desc: 'Play from beginning of selection',      group: 'global' },
    ']': { action: 'play_from_selection_end',       desc: 'Play from end of selection',            group: 'global' },
    s:   { action: 'stop_playing',                  desc: 'Stop playback',                         group: 'global' },
    '.': { action: 'center_and_play_current_span',  desc: 'Center waveform on current span and play', group: 'global' }
};

// ─── Modifier keys (configurable) ────────────────────────────────────────
//
// The keymap's `.control` submap is triggered by a single modifier key. The
// user picks which one in the settings dialog; the choice is stored in the
// settings store as `modifier` (one of 'ctrl' | 'alt' | 'shift' | 'meta').

const is_mac = typeof navigator !== 'undefined' && /Mac|iPhone|iPad/.test(navigator.platform);
const is_win = typeof navigator !== 'undefined' && /Win/.test(navigator.platform);
const meta_label = is_mac ? '⌘' : is_win ? 'win' : 'super';
const meta_name  = is_mac ? 'Cmd' : is_win ? 'Win' : 'Super';

const modifiers = [
    { id: 'ctrl', name: 'Ctrl',    label: 'ctrl',     event_key: 'ctrlKey' },
    { id: 'alt',  name: 'Alt',     label: 'alt',      event_key: 'altKey'  },
    { id: 'meta', name: meta_name, label: meta_label, event_key: 'metaKey' }
];

const default_modifier = 'ctrl';

function modifier_label(id) {
    return modifiers.find(m => m.id === id)?.label ?? 'ctrl';
}
function modifier_event_key(id) {
    return modifiers.find(m => m.id === id)?.event_key ?? 'ctrlKey';
}

// ─── transcribe_text_only ────────────────────────────────────────────────
//
// Actions that change the transcript's *shape* rather than its text: what
// segments exist, where they begin and end, and who or which section they
// belong to. In transcribe_text_only mode all of that came from an imported
// graph and isn't the annotator's to change, so these don't run — and the
// cheat sheet greys them out rather than listing keys that do nothing.
//
// Named by action rather than by key on purpose: one action reaches several
// keys (',' in the waveform map and ctrl+',' in the input map are the same
// split), and a new binding for an existing action is covered without
// anyone remembering to come back here.
//
// Comments have no binding at all — they're made from the button on their own
// panel — but they're a permission of their own either way: a remark about a
// stretch of audio isn't the transcript's shape, so the message guard lets
// them through where the transcript is locked.
const text_only_forbidden = new Set([
    'play_current_span_and_add_transcript_line_and_activate', // create a segment
    'split_segment_at_cursor',
    'merge_with_following_segment',
    'delete_active_transcript_line',
    'delete_all_confirm',
    'add_to',                                                 // extend a segment to the selection
    'set_speaker',
    'open_section', 'close_section', 'show_sections',
    'upload_transcript'
]);

export {
    modes, mode_palette, home_keys,
    waveform_map, input_map, playback_map,
    modifiers, default_modifier, modifier_label, modifier_event_key,
    text_only_forbidden
};
