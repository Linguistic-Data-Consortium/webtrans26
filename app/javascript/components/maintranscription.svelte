<script>
    import { onMount } from 'svelte';
    import Waveform from '../lib/ldcjs/waveform/waveform.svelte';
    import { btn } from '../lib/ldcjs/work/buttons';
    import { activeo } from '../lib/ldcjs/waveform/shared.svelte';
    import TranscriptionGuide from '../lib/transcription_guide.svelte';
    let { ldc } = $props();
    // window.ldc.vars.user_id is populated by work.js during workflow init.
    const guide_user_id = (typeof window !== 'undefined' && window.ldc?.vars?.user_id) || 'anon';
    const width = window.$('.view')[0].offsetWidth
    const permissions = ldc.permissions;
    const constraint_export_transcript = ldc.get_constraint('export_transcript');
    const constraint_export_transcript_to_task_admin = ldc.get_constraint('export_transcript_to_task_admin');
    const constraint_import_transcript = ldc.get_constraint('import_transcript');
    const constraint_import_transcript_auto = ldc.get_constraint('import_transcript_auto');
    const constraint_rtl = ldc.get_constraint('rtl');
    const constraint_speakers = ldc.get_constraint('speakers');
    const constraint_sections = ldc.get_constraint('sections');
    const constraint_section_order_forced = ldc.get_constraint('section_order_forced');
    const constraint_add_asr_segments = ldc.get_constraint('add_asr_segments');
    const constraint_asr_korean = ldc.get_constraint('asr_korean');
    const constraint_audit = ldc.get_constraint('audit');
    let source_uid = $derived(activeo.docid && activeo.docid.match(/\.(wav)$/) ? activeo.docid : null);
    const waveform = {
        wave_audio: {},
        play_head: 0,
        playheads: new Map()
    };
    ldc.waveforms = [ waveform ];
    // ns.waveform = waveform;
    const redact_task = ldc.obj2.task_meta.redact;
    let w = $state();
    setInterval(() => ldc.wc = w, 1000);
    // onMount( () => ldc.wc = w );
    export function update_segments(){
        setTimeout( () => {
            if(w) w.update_segments_with();
            else  update_segments();
        }, 500 );
    }
    ldc.speakers = new Map();
    ldc.sections = new Map();
    window.$('.Speaker').each(function(i, y) {
      ldc.speakers.set(window.$(y).data().value.value, true);
    });
    window.$('.Section').each(function(i, y) {
      ldc.sections.set(window.$(y).data().value.value, true);
    });
    update_segments();
    // export function set_mode(x){ w.set_mode(x) }
    // export function get_mode(x){ return w.get_mode() }
    // export function set_times_then_draw(x, y){ if(w) w.set_times_then_draw(x, y) }
    // export function move_cursor(x, factor) { w.move_cursor(x, factor) }
    // export function move_cursor_lstep1(){ w.move_cursor_lstep1(); }
    // export function move_cursor_lstep2(){ w.move_cursor_lstep2(); }
    // export function move_cursor_lstep3(){ w.move_cursor_lstep3(); }
    // export function move_cursor_lstep4(){ w.move_cursor_lstep4(); }
    // export function move_cursor_rstep1(){ w.move_cursor_rstep1(); }
    // export function move_cursor_rstep2(){ w.move_cursor_rstep2(); }
    // export function move_cursor_rstep3(){ w.move_cursor_rstep3(); }
    // export function move_cursor_rstep4(){ w.move_cursor_rstep4(); }
    // export function move_selection_lstep1(){ w.move_selection_lstep1(); }
    // export function move_selection_lstep2(){ w.move_selection_lstep2(); }
    // export function move_selection_lstep3(){ w.move_selection_lstep3(); }
    // export function move_selection_lstep4(){ w.move_selection_lstep4(); }
    // export function move_selection_rstep1(){ w.move_selection_rstep1(); }
    // export function move_selection_rstep2(){ w.move_selection_rstep2(); }
    // export function move_selection_rstep3(){ w.move_selection_rstep3(); }
    // export function move_selection_rstep4(){ w.move_selection_rstep4(); }
    // export function move_window_lstep1(){ w.move_window_lstep1(); }
    // export function move_window_lstep2(){ w.move_window_lstep2(); }
    // export function move_window_lstep3(){ w.move_window_lstep3(); }
    // export function move_window_lstep4(){ w.move_window_lstep4(); }
    // export function move_window_rstep1(){ w.move_window_rstep1(); }
    // export function move_window_rstep2(){ w.move_window_rstep2(); }
    // export function move_window_rstep3(){ w.move_window_rstep3(); }
    // export function move_window_rstep4(){ w.move_window_rstep4(); }
    // export function set_current_selection(x, factor) { w.set_current_selection(x, factor) }
    // export function show_src(src, beg) { w.show_src(src, beg) }
    // export function toggle_zoom() { w.toggle_zoom() }
    // export function zoom_in() { w.zoom_in() }
    // export function zoom_out() { w.zoom_out() }
    // export function update(){                  w.update() }

    // export function show_help_screen_main(x){  w.show_help_screen_main(x) }
    // export function upload_transcript(){       w.upload_transcript() }

    // export function play_current_span_or_play_stop(){ w.play_current_span_or_play_stop(); }
    // export function play_current_span(){ w.play_current_span(); }

    // export function play_from_cursor(){ w.play_from_cursor(); }
    // export function play_from_selection_beg(){ w.play_from_selection_beg(); }
    // export function play_from_selection_end(){ w.play_from_selection_end(); }
    // export function cursor_time(){ return w.cursor_time() }
    // export function split_segment_at_cursor() { return w.split_segment_at_cursor() }
    // export function find_active_id(){ return t.find_active_id() }


    // let u;
    // export function undo(){ u.undo() }
    // export function refresh() { t.refresh() }
    export function use_transcript(t, x){
    }
    function userf(e){
        let f = e.detail.userf
        if(f == 'delete_all_confirmx'){
            // dispatch('userf', o);
        }
        else{
            if(w[f]) w[f](e.detail.e);
            else  console.log(`no function ${f}`)
        }
    }

    // active_docid.subscribe( (x) => {
        // source_uid = x && x.match(/\.(wav)$/) ? x : null;
    // });
    let e = document.querySelector('.Header');
    if(e) e.remove();
    e = document.querySelector('body');
    if(e){
        e.classList.add('pt-4');
        e.classList.remove('pt-20');
    }
</script>

{#if false}
<div class="flex">
<button class="{btn} w-full" onclick={one}>one</button>
<button class="{btn} w-full" onclick={two}>two</button>
</div>
{/if}
<!-- source {source_uid} -->
<!-- <Undo bind:this={u} /> -->
<TranscriptionGuide user_id={guide_user_id} />

{#key source_uid}
    {#if source_uid}
        <Waveform
            bind:this={w}
            on:userf={userf}
            {ldc}
            {width}
            set_urls={ldc.set_urlsx}
            {source_uid}
            source_uid_channels={ldc?.maino?.channels}
            {redact_task}
            {permissions}
            {constraint_export_transcript}
            {constraint_export_transcript_to_task_admin}
            {constraint_import_transcript}
            {constraint_import_transcript_auto}
            {constraint_rtl}
            {constraint_speakers}
            {constraint_sections}
            {constraint_section_order_forced}
            {constraint_add_asr_segments}
            {constraint_asr_korean}
            {constraint_audit}
        />
    {/if}
{/key}
