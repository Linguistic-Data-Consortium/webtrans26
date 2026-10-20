<script>
    import { tick, createEventDispatcher, onMount, onDestroy } from 'svelte';
    const dispatch = createEventDispatcher();
    import { ArrowUpFromLine, ArrowDownToLine, Check, X } from '@lucide/svelte';
    import { event } from '../../../guides/guide';
    import { mark_transcription } from '../../guide_state';
    import { settings } from './stores';
    import { transcript } from './transcript.svelte';
    import { add_source_audio_collision } from './sources_stores';
    import { play_src_with_audio_id, redactions, redactf } from './play';
    import { btn, cbtn, dbtn, btn1 } from '../work/buttons';
    import {
        add_audio_to_list,
        add_audio_to_listp,
        add_audio_to_listq,
        delete_segments,
        save_redaction,
        delete_transcript_line_based_on_segment_id,
        change_value,
        split_segment_at_cursor,
        merge_with_following_segment
    } from './modification1';
    import {
        three_way_split,
        fmap_helper_suserf,
        wait_for,
        display_docid,
        pad
    } from './helpers';
    import { times, round_to_3_places, round_to_6_places } from './times';
    import { RedactDialog } from './dialogs';
    import { asro } from './asr.svelte';
    import { bulko } from './bulk.svelte';
    import { activeo, get_reference_text } from './shared.svelte';
    import { text_only_forbidden } from './bindings';
    let {
        ldc,
        debug,
        docids,
        set_active_transcript_line_helper,
        play_head,
        constraint_rtl,
        index_segments_by_id,
        segmap,
        secmap,
        update_segments,
        set_speaker,
        open_mode_menu,
        show_sections,
        open_section,
        close_section,
        validate_transcript,
        play_head_menu,
        generic_next,
        play_current_span,
        play_current_span_and_add_transcript_line_and_activate,
        wmap,
        index2,
        index_sections_by_name,
        create_section_index,
        create_section_index2,
        split_line_margin,
        controls,
        channelsc,
        // transcribe_text_only: the segments came from an imported graph and
        // their shape isn't the annotator's to change. The affordances for
        // changing it go, rather than staying visible and doing nothing.
        text_only = false
    } = $props();

    let rtl = $derived(constraint_rtl);

    const segs = $derived(transcript.segments);
    let vsegs = [];
    let vvsegs = $state([]);
    const undef = $derived(transcript.undefined_segments);
    // let active_channeln = $state(0);
    // const un1 = active_channel.subscribe( x => active_channeln = x );
    // Was a subscription that also redacted; the redaction is the side effect,
    // so it's the only part that needs an effect.
    $effect(() => {
        if(debug){
            console.log('SEGMENTS');
            console.log(segs);
        }
        redactf(segs);
    });


    // const index = new Map();
    // let set_playing_transcript_line_index;
    // const index2 = new Map();
    // const index_segments_by_id = new Map();
    // const wmap = new Map();
    // const wrmap = new Map();
    // const segmap = new Map();
    // const secmap = new Map();
    // ldc.index = index;
    // ldc.index2 = index2;
    // ldc.index_segments_by_id = index_segments_by_id;
    // ldc.wmap = wmap;
    // ldc.wrmap = wrmap;
    // ldc.segmap = segmap;
    // ldc.secmap = secmap;
    // const nmap = new Map();
    // ldc.nmap = nmap;
    const gmap = new Map();

    // let index_sections_by_segment_id;
    // let index_sections_by_name;


    export function index_segments(segments){
        let aactive2 = aactive;
        // set_playing_transcript_line_index = index;
        index2.clear();
        index_segments_by_id.clear();
        wmap.clear();
        // active = set_active_transcript_line null
        // let aactive = null;
        let aaactive = null;
        if(debug) console.log(activeo.active)
        // let active_node_id2 = activeo.active && index_segments_by_id.get(activeo.active) ? index_segments_by_id.get(activeo.active).iid : null;
        // if(active_node_id2 !== null) aactive = String(active_node_id2);
        let i;
        let j;
        let ref;
        let c1;
        for (i = j = 0, ref = segments.length; (0 <= ref ? j < ref : j > ref); i = 0 <= ref ? ++j : --j) {
            c1 = segments[i];
            c1.id = `segment-${i}`;
            index_segments_by_id.set(c1.id, c1);
            // that.index_segments_by_id[id] = c1
            let node_id = `node-${c1.iid}`;
            wmap.set(c1.id, node_id);
            index2.set(String(i), c1);
            if (aactive2 === String(c1.iid)) {
                // active = id if active is wmap[id]
                aaactive = c1.id;
            }
            c1.section = null;
        }
        if (document.querySelectorAll('.SectionList').length === 1) {
            let sss = null;
            create_section_index2();
            const all = Object.values(index_sections_by_name).sort( (a, b) => a.begr - b.begr );
            for(let i = 0; i < all.length; i++){
                let ss = all[i];
                if(!ss.endr){
                    if(i < all.length - 1) ss.endr = all[i+1].begr;
                    else                   ss.endr = 9999999;
                }
            }
            let l;
            let ref1;
            for (i = l = 0, ref1 = segments.length; (0 <= ref1 ? l < ref1 : l > ref1); i = 0 <= ref1 ? ++l : --l) {
                c1 = segments[i];
                // let ss = that.index_sections_by_segment_id[c1.id];
                // if (ss) {
                //   sss = ss;
                // }
                // c1.section = sss;
                // if (ss && ss.end === c1.id) {
                //   sss = null;
                // }
                for(let ss of all){
                    if(c1.beg >= ss.begr && c1.end <= ss.endr){
                        c1.section = ss;
                    }
                }
            }
        }
        add_source_audio_collision(docids[0]);
        set_active_transcript_line_helper(aaactive);
        if(debug) console.log('this active', aaactive)
        set_active_transcript_line(aaactive, true);
        if(debug){
            console.log('HERE');
            console.log(aactive);
            console.log(index2);
        }
    }






    // let active = $state(null);
    // let active_node_id = $derived(activeo.active && index_segments_by_id.get(activeo.active) ? index_segments_by_id.get(activeo.active).iid : null);
    // let aactive = $derived(active_node_id !== null ? String(active_node_id) : null);
    let aactive = $derived.by(() => {
        let active_node_id = activeo.active && index_segments_by_id.get(activeo.active) ? index_segments_by_id.get(activeo.active).iid : null;
        return active_node_id !== null ? String(active_node_id) : null;
    });
    // export function get_active_node_id(){ return active_node_id; }
    // let last_active_segment = $state();
    // let current_segment_iid = $derived(parseInt(index_segments_by_id.get(last_active_segment).iid) + 2);
    // let current_segment_iid = $derived(parseInt(index_segments_by_id.get(activeo.active).iid) + 2);
    // let current_segment_iidh = $derived(index_segments_by_id.get(activeo.last_active_segment));
    // let current_segment_iid = $derived(current_segment_iidh ? parseInt(current_segment_iidh.iid) + 2 : null);
    let current_segment_iid = $derived.by(() => {
        let x = index_segments_by_id.get(activeo.last_active_segment);
        return x ? parseInt(x.iid) + 2 : null;
    });
    export function set_active_transcript_line(id, dont_focus){
        activeo.last_active_segment = activeo.active || id;
        console.log('setting ', activeo.last_active_segment, id)
        activeo.active = id;
        // console.log(id);
        // if(id) active_node_id = index_segments_by_id.get(id).iid;
        // last_active_segment = id;
        if(true){
            console.log(`last: ${activeo.last_active_segment}, active: ${activeo.active}`);
        }
        return activeo.last_active_segment;
    }
    // Tab from the waveform: put the text window back in focus.
    //
    // Re-activating the same row is what focuses its textarea (t_init focuses
    // on mount), so this drops the active row and restores it. With nothing
    // active — the waveform was clicked before any segment was — there was
    // nothing to restore and Tab appeared dead. Pick a row in that case.
    export function refocus(){
        let a = activeo.active ?? segment_at_cursor();
        if(a == null) return; // no segments yet: nothing to put focus in
        activeo.active = null;
        setTimeout( () => {
            set_active_transcript_line(a);
            // What a click does beyond setting the row: selects the row's
            // audio on the waveform, and sets ldc.crnt, which is what split
            // and merge act on. Without it, tabbing onto a row left the
            // waveform showing whatever was selected before and those two
            // keys doing nothing. Re-activating the row it's already on is a
            // no-op inside the helper.
            set_active_transcript_line_helper(a);
        }, 100);
    }

    // The segment the cursor is in, else the next one after it, else the last.
    // Where someone who has just clicked the waveform expects to end up.
    function segment_at_cursor(){
        if(!segs.length) return null;
        const t = channelsc && channelsc.cursor_time && channelsc.cursor_time();
        if(t == null) return segs[0].id;
        const containing = segs.find( (x) => x.beg <= t && x.end >= t );
        if(containing) return containing.id;
        const after = segs.find( (x) => x.beg >= t );
        return (after || segs[segs.length - 1]).id;
    }
    function find_active_i(){
        let found = null;
        for(let i = 0; i < segs.length; i++){
            if(segs[i].id === activeo.active){
                found = i;
                break;
            }
        }
        return found;
    }
    export function find_active_id(){
        let found = find_active_i();
        let h = { id: segs[found].id }
        h.prev = found && found > 0 ? segs[found - 1].id : null;
        h.next = (found || found == 0) && found < segs.length - 1 ? segs[found + 1].id : null;
        return h;
    }
    export function set_active_transcript_line_to_next(){
        if(segs.length == 0){
            return;
        }
        let found = find_active_i();
        let set = null;
        if(found || found == 0){
            if(found < segs.length - 1){
                set = found + 1;
            }
        }
        else{
            set = 0;
        }
        return set_active_transcript_line_wrapper(set, found);
    }
    export function set_active_transcript_line_to_prev(){
        if(segs.length == 0){
            return null;
        }
        let found = find_active_i();
        let set = null;
        if(found || found == 0){
            if(found > 0){
                set = found - 1;
            }
        }
        else{
            set = segs.length - 1;
        }
        return set_active_transcript_line_wrapper(set, found);
    }
    function set_active_transcript_line_wrapper(set, found){
        let h = {}
        if(set || set == 0){
            h.id = segs[set].id;
            h.last = set_active_transcript_line(h.id, false);
        }
        else{
            h.id = segs[found].id;
            h.last = h.id;
        }
        return h;
    }

    // these also set it on the waveform
    function set_active_transcript_line_to_next_and_play_current_span(){
        // if(!ldc.active_channel()){
        //     return;
        // }
        // Need a timeout otherwise next line is overwritten with (formerly) active transcript!
        setTimeout(function() {
            const ids = set_active_transcript_line_to_next();
            set_active_transcript_line_helper(ids.id);
            play_current_span();
        }, 200);
    }

    // The list item of the group addf just built is the first pair in its group
    // string. (The old path waited for a DOM node to appear and read its id.)
    export function set_active_transcript_line_to_last_created(){
        let id = ldc.last_children[0];
        if(!id) return;
        id = segmap.get(parseInt(id.split(':')[0]));
        if(!id) return;
        set_active_transcript_line(id.id, false);
        return id;
    }

    function click_transcript_line(e){
        if(debug){
            console.log(e);
            console.log(this.id);
        }
        set_active_transcript_line(this.id);
        if(debug) console.log(this.dataset.iid);
        set_active_transcript_line_helper(this.id);
        // Notify the transcription guide's "Click a transcription line"
        // step so it can advance.
        mark_transcription('transcript_line_clicked');
    }
    const params = new URLSearchParams(window.location.search);
    let format = params.has('format');

    function remove_virtual(segment){
        vsegs.splice(vsegs.indexOf(segment), 1);
    }

    function virtual_no(segment){
        remove_virtual(segment);
        sort_segments();
    }

    function virtual_yes(segment){
        remove_virtual(segment);
        const f = () => {
            // asr_segments.delete(segment.speaker);
            // ldc_nodes.add_message_listitem('SegmentList', vals);
            // const id = parseInt(ldc.last_children[0].split(':')[0]);
            // const idd = ldc.segmap.get(id).id;
            // set_active_transcript_line(idd);

            const ids = set_active_transcript_line_to_last_created();
            // const ids = set_active_transcript_line_to_next();
            set_active_transcript_line_helper(ids.id);
            // play_current_span();
            update_segments();
        };
        add_audio_to_listp(segment.docid, segment, f);
    }

    export function sort_segments(){
        const tsegs = [];
        const tundef = [];
        for(const [k, v] of segmap){
            if(!v.beg && v.beg != 0){
                tundef.push(k);
            }
            else{
                tsegs.push(v);
            }
        }
        for(const x of vsegs){
            console.log(x)
            tsegs.push(x);
        }
        tsegs.sort( (x, y) => x.beg - y.beg );
        index_segments(tsegs);
        transcript.segments = tsegs;
        transcript.undefined_segments = tundef;
    }

    let ttextarea = $state();
    let t_previous = new Map();
    let t_iid;
    let t_value = $state();
    let t_readonly = $state();
    let t_timeout;
    let t_rows = $derived(t_value ? Math.ceil(t_value.length / 70) : 1);
    function t_blur(){
        if(t_timeout){
            clearTimeout(t_timeout);
            t_patch(t_iid, t_value);
        }
    }
    function t_keydown(e, x){
        if(e.key == '/') e.preventDefault();
        if(t_readonly){
            if(e.key == 'y') virtual_yes(x);
            if(e.key == 'n'){ virtual_no(x); return; }
        }
        fmap_helper_suserf(e, x, suserf);
    }
    function suserf(e, x){
        if(text_only && text_only_forbidden.has(e.detail.userf)) return;
        const o = { userf: e.detail.userf, e: e.detail.e };
        const h = { iid: x.iid };
        h.nodes = x.nodes;
        h.speaker = x.speaker;
        // if(ldc.nodes && e.detail.userf.match(/section/)){
        //     alert('the section feature is broken');
        //     return;
        // }
        if(e.detail.userf == 'set_speaker')        set_speaker(x);
        else if(e.detail.userf == 'open_mode_menu') open_mode_menu();
        else if(e.detail.userf == 'show_sections')  show_sections();
        else if(e.detail.userf == 'open_section')  open_section(x);
        else if(e.detail.userf == 'close_section') close_section(h, update_segments);
        else if(e.detail.userf == 'validate_transcript') validate_transcript();
        else if(e.detail.userf == 'play_head_menu')      play_head_menu(h);
        else if(e.detail.userf == 'delete_active_transcript_line') control_d(x);
        else if(e.detail.userf == 'generic_next')                  generic_next(x);
        else if(e.detail.userf == 'tag_redact')                    insert_surrounding_tags('redact');
        else if(e.detail.userf == 'tag_unintelligible')            insert_surrounding_tags('unintelligible');
        // else if(e.detail.userf == 'tag_laugh')                     insert_laugh();
        else if(e.detail.userf == 'tag_laugh')                     insert_surrounding_tags('laugh');
        else if(e.detail.userf == 'tag_sing')                     insert_surrounding_tags('sing');
        else if(e.detail.userf == 'split_segment_at_cursor')            { split_segment_at_cursor(channelsc.cursor_time(), split_line_margin, update_segments); mark_transcription('segment_split'); }
        else if(e.detail.userf == 'merge_with_following_segment')            { merge_with_following_segment(find_active_id(), wmap, update_segments); mark_transcription('segment_merged'); }
        else if(e.detail.userf == 'play_current_span') play_current_span();
        else if(e.detail.userf == 'set_active_transcript_line_to_prev') { set_active_transcript_line_helper(set_active_transcript_line_to_prev().id); mark_transcription('segment_navigated'); }
        else if(e.detail.userf == 'set_active_transcript_line_to_next') { set_active_transcript_line_helper(set_active_transcript_line_to_next().id); mark_transcription('segment_navigated'); }
        else if(e.detail.userf == 'set_active_transcript_line_to_next_and_play_current_span') { set_active_transcript_line_to_next_and_play_current_span(); mark_transcription('transcript_committed'); }
        else if(e.detail.userf == 'play_current_span_and_add_transcript_line_and_activate') play_current_span_and_add_transcript_line_and_activate();
        else if(e.detail.userf == 'keyboard_focus') { controls.keyboard_focus(); mark_transcription('focus_to_keyboard'); }
        // else                                                       dispatch('userf', o);
        else console.error('bad event')
    }
    // The textarea edits the segment's Text node, two iids along from the list
    // item. Finding it used to mean waiting for a DOM node and reading jQuery
    // data off it; there's no DOM to wait for now.
    function t_init(input, x){
        if(t_timeout) clearTimeout(t_timeout);
        input.focus();
        t_readonly = x.virtual || x.readonly || x.text == "REDACTED";
        t_iid = x.iid + 2;
        t_previous.set(t_iid, x.text);
        t_value = x.text;
        if(t_readonly) console.log('readonly ' + x.text);
    }
    // let t_first = true;
    function t_update(x){
        // if(t_first) return;
        if(t_timeout) clearTimeout(t_timeout);
        t_timeout = setTimeout( () => t_patch(t_iid, x) , 1000 );
        console.log('text updated')
    }
    $effect(() => t_update(t_value));
    function t_patch(iid, v){
        const value = v?.replace(/\r|\n/g, '');
        if(t_timeout) clearTimeout(t_timeout);
        // if(ldc.nodes) transcription.nodes.get('Transcription').node_value.set( { value: value } );
        if(value != t_previous.get(iid)){
            change_value(iid, value, update_segments);
            t_previous.set(iid, value);
        }
    }
    // if(t_readonly) t_value = x.text;

    let deleteb = $state(false);
    function control_d(){
        // console.log('d');
        deleteb = true;
        setTimeout( () => deleteb = false, 3000 );
    }
    function delete_active_transcript_line(){
        const x = set_active_transcript_line(null);
        // dispatch something
        if(x) delete_transcript_line_based_on_segment_id(wmap, x, true, update_segments);
        deleteb = false;
        // Notify the transcription guide's "Delete the duplicate" step.
        if(x) mark_transcription('segment_deleted');
    }

    setInterval(()=>{
        let nnn = document.querySelector('.playing-transcript-line');
        if(nnn) nnn = nnn.offsetTop;
        else return;
        let mmm = document.getElementById('segments').scrollTop;
        if(nnn-mmm > 500) document.getElementById('segments').scrollTop = nnn - 400;
    },1000);

    function insert_surrounding_tags(type){
        const input = ttextarea; // e.detail.e.target;
        let i = input.selectionStart;
        while(i > 0 && t_value[i-1] != ' ') i--;
        const a = i;
        i = input.selectionEnd;
        while(i < t_value.length && t_value[i] != ' ') i++;
        const b = i;
        const { x, y, z } = three_way_split(t_value, a, b);
        let extra = 4;
        if(type == 'unintelligible'){
            t_value = `${x}((${y}))${z}`;
        }
        else if(type == 'laugh'){
            t_value = y.length ? `${x}<laugh>${y}</laugh>${z}` : `${x}{laugh}${z}`;
            extra = 15;
        }
        else if(type == 'sing'){
            t_value = y.length ? `${x}<sing>${y}</sing>${z}` : `${x}{sing}${z}`;
            extra = 13;
        }
        else if(type == 'redact'){
            const span = {
                offset: activeo.wave_selection_offset,
                length: activeo.wave_selection_length,
                transcript: y,
                speaker: 'redacted'
            };
            add_audio_to_list(docids[activeo.channel], null, null, span);
            t_value = `${x}<redact>${y}</redact>${z}`;
            extra = 17;
        }
        // if(ldc.nodes){
        //     console.log('here')
        //     console.log(ldc.segmap.get(x.iid));
        //     const text = ldc.obj2.xlass_def_id == 2 ? 'Text' : 'Transcription';
        //     ldc.segmap.get(x.iid).nodes.get(text).node_value.set( { value: edit } );
        //     waveform.component.set_active_transcript_line(null);
        //     segs = segs;
        // }
        // change_value(iid, edit, f);
        setTimeout( () => {
            input.selectionStart = input.selectionEnd = x.length + y.length + extra;
        }, 100);

    }

    // function insert_laugh(){
    //     const input = ttextarea;
    //     const { x, y, z } = three_way_split_on_selection(input);
    //     t_value = `${x}${y}{laugh}${z}`;

    //     setTimeout( () => {
    //         input.selectionStart = input.selectionEnd = x.length + y.length + 7;
    //     }, 100);
    // }

    // asr_store.subscribe(x => {
    // $effect(() => {
    //     if(asro.status == 'init'){
    //         run_init();
    //     }
    // });

    // set_cb(() => xasr(active_channeln == 1, docids, ldc) );
    // set_cb(() => Promise.resolve(1) )

    // function xasrr(o){
    //     // asro = o;
    //     // xasrrr(0, o.vvsegs);
    //     return o;
    // }

    let redact;
    export function redactcb(x){ redact.redactcb(x); }
    function save_redactionf(value, redact_iid, redact_edit){
        // dialog.close();
        // const value = redact_text;
        // redact_text = "";
        activeo.active = null;
        if(debug){
            console.log(current_segment_iid);
            console.log(redact_iid);
        }
        save_redaction(current_segment_iid, value, redact_iid, redact_edit, update_segments);
        // if(ldc.nodes){
        //     ldc.segmap.get(iid-2).nodes.get('Transcription').node_value.set( { value: value } );
        //     if(redact_edit) ldc.segmap.get(parseInt(redact_iid)-2).nodes.get('Transcription').node_value.set( { value: redact_edit } );
        //     segs = segs;
        // }
    }

    // An operation that rewrites the whole transcript — an ASR run, deleting
    // every segment, replacing a speaker label everywhere — issues its changes
    // in batches, each a server round trip, and the list re-renders between
    // them. Left visible that shows rows appearing or vanishing in front of the
    // annotator with no way to tell a run still going from one that stalled. So
    // hide the rows while one is in flight and say what is happening instead.
    //
    // bulk.svelte.js holds the state; whichever operation is running reports
    // into it. See its comment for why this isn't ASR-specific.
    const bulk_running = $derived(!!bulko.label);
    const bulk_label = $derived(bulko.label);
    const bulk_total = $derived(bulko.total);
    const bulk_count = $derived(bulko.done);
</script>

<style>
    .rtl {
        direction: rtl;
    }
    
    .ch1 {
        background-color: Azure;
    }
    
    .ch2 {
        background-color: Lavender;
    }

    .ch3 {
        background-color: LightYellow;
    }

    .ch4 {
        background-color: MistyRose;
    }

    .playing-transcript-line {
        background-color: LightGreen;
    }

    input, textarea {
        border-width: 0px;
        border: none;
    }
    .cursor {
        width: 1px;
    }
    .opacity-50 {
        opacity: 0.5;
    }
    .col-span-5 {
        grid-column: span 5 / span 5;
    }
    .col-span-4 {
        grid-column: span 4 / span 4;
    }
    .col-span-3 {
        grid-column: span 3 / span 3;
    }

</style>

<RedactDialog
    bind:this={redact}
    {index_segments_by_id}
    {segs}
    {save_redactionf}
/>


{#if undef.length}
    <div class="w-96 mx-auto">
        {undef.length} undefined segments found
        <button class="{btn}" onclick={ () => delete_segments(undef, update_segments) }>Delete?</button>
    </div>
{/if}

{#if bulk_running}
    <div class="h-full flex flex-col items-center justify-center text-gray-500 select-none">
        <div class="text-sm">
            {#if bulk_total}
                {bulk_label} — {bulk_total} segment{bulk_total === 1 ? '' : 's'}…
            {:else}
                {bulk_label}…
            {/if}
        </div>
        <!-- Changes go out in batches, so an operation over fewer items than one
             batch has nothing to report until it is done, and a bar pinned at
             zero reads as stuck. Show the count only once it means something. -->
        {#if bulk_total && bulk_count > 0}
            <div class="text-xs mt-1 tabular-nums">{bulk_count} of {bulk_total}</div>
            <div class="w-48 h-1 mt-2 bg-gray-200 rounded overflow-hidden">
                <div class="h-full bg-indigo-500 transition-all" style="width: {Math.round(100 * bulk_count / bulk_total)}%"></div>
            </div>
        {/if}
    </div>
{:else}
<div id="segments" class="h-48 mt-6 pt-1 overflow-auto {rtl ? 'rtl' : ''} font-mono v-align-middle text-gray-700" use:event.dispatch={'drew_segments'}>
    {#each segs as x, i}
        {@const reference = get_reference_text(x.beg, x.end)}
        {#if reference}
            <!-- Reference transcript: what was supposed to be said, shown above
                 the empty segment the annotator types into, matched to it by
                 timestamp. A rule above each one separates a prompt and its
                 line from the pair before — without it the two run together
                 down a page of them. -->
            <div class="reference-text grid grid-cols-12 gap-2 text-xs italic text-sky-600 {i > 0 ? 'border-t border-gray-300 pt-1 mt-1' : ''}">
                <div class="col-span-2"></div>
                <div class="col-span-6 pl-1 whitespace-pre-wrap">{reference}</div>
                <div class="col-span-4"></div>
            </div>
        {/if}
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <!-- The ch1..ch4 tint tells two channels apart. Where the segments came
             from an imported transcript there's one document and nothing to
             tell apart, so the line the annotator types into is left plain. -->
        <div
            id={x.id}
            class="
                grid grid-cols-12 gap-2
                segment
                segment-{x.iid}
                flex justify-around
                mx-auto
                text-sm
                {x.id === activeo.active ? 'active-segment text-red-500' : '' }
                {!text_only && x.docid == docids[0] ? 'ch1' : ''}
                {!text_only && x.docid == docids[1] ? 'ch2' : ''}
                {!text_only && x.docid == docids[2] ? 'ch3' : ''}
                {!text_only && x.docid == docids[3] ? 'ch4' : ''}
                {x.docid == docids[activeo.channel] && x.beg <= play_head && x.end >= play_head ? 'playing-transcript-line' : ''}
            "
            data-iid={x.iid}
            onclick={click_transcript_line}
            onkeydown={() => 1}
            use:event.dispatch={'created_segment'}
        >
            <div class="col-span-2 grid grid-cols-3 justify-items-end">
                {#if format}
                    <span class=Label>{x.speaker}</span>
                {:else if x.virtual}
                    <div></div>
                    <div>
                        <button class="{dbtn}" onclick={() => virtual_no(x)}><X size=10/></button>
                    </div>
                    <div>
                        <button class="{cbtn}" onclick={() => virtual_yes(x)}><Check size=10/></button>
                    </div>
                {:else}
                    <div class="col-span-1 min-w-0 w-full">
                        <div class="truncate text-left" title={display_docid(x.docid)}>{display_docid(x.docid)}</div>
                    </div>
                    <div class="btime">
                        <div>{pad(x.beg)}</div>
                    </div>
                    <div class="etime">
                        <div>{pad(x.end)}</div>
                    </div>
                {/if}
            </div>
            <div class="col-span-6 text-sm">
                {#if x.id === activeo.active}
                    <textarea
                        bind:this={ttextarea}
                        rows={t_rows}
                        class="ann-segment pl-1 p-0 w-full text-sm focus:ring-2 focus:ring-red-500 flex-1 block rounded { t_value == "REDACTED" ? "bg-red-500" : ""}"
                        type="text"
                        bind:value={t_value}
                        readonly={t_readonly}
                        onblur={t_blur}
                        onkeydown={ (e) => t_keydown(e, x) }
                        use:t_init={x}
                    ></textarea>
                {:else}
                    <div class="pl-1 transcript">{x.text}</div>
                {/if}
            </div>
            <div class="col-span-3">
                <div class="flex justify-around">
                    <div class="speaker float-left col-6">
                        {#if !format}
                            <span class="{x.speaker ? '' : 'opacity-50'}">{x.speaker || 'empty'}</span>
                        {/if}
                    </div>
                    {#if x.section}
                        <div class="section Label
                            {x.section.end ? "" : ""}
                            height-fit
                        ">
                            {x.section.name}
                        </div>
                    {:else}
                        <div class="Label"></div>
                    {/if}
                </div>
            </div>
        </div>
        {#if x.id === activeo.active && deleteb && !text_only}
            <div class="flex justify-end">
                <button class="{dbtn}" onclick={delete_active_transcript_line}>delete</button>
            </div>
        {/if}
        {#if x.error?.size}
            <div class="text-center bg-red-100"> {[...x.error.keys()].join(', ')} </div>
        {/if}
    {/each}
</div>
{/if}
