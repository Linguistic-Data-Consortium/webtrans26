<script>
    import { tick, createEventDispatcher, onMount, onDestroy } from 'svelte';
    import * as DropdownMenu from "$lib/components/ui/dropdown-menu"
    import { event } from '../../../guides/guide';
    import { mark_transcription } from '../../guide_state';
    import Channel from './channel.svelte';
    import { times, round_to_3_places, round_to_6_places } from './times';
    import { create_action } from '../../../work/controllers';
    import { settings, mouse, key } from './stores';
    import { activeo, sourceso, sourcesor } from './shared.svelte';
    import { mode_palette } from './bindings';
    import {
        update_node
    } from './modification1';
    import { set_audio_id_to_channel } from '../audio/main';
    let {
        ldc,
        nchannels,
        underline,
        wave_canvas_height,
        width,
        create_audio_hash_from_docid,
        create_audiok_from_docid,
        docids,
        debug,
        redact_task,
        set_current_selection,
        controls,
        wave_active_transcript_line,
        set_active_transcript_line_helper,
        duration,
        play_head,
        wmap,
        source_uid_channels,
        segmentsc,
    } = $props();
    let channels = $state([null, null, null, null]);
    // function draw_waveformi(i){ if(channels[i]) channels[i].draw_waveformi(i); }
    let nchannelsa = $derived(Array.from({ length: nchannels }, (_, i) => i));
    let step = $derived(wave_display_length / 40);
    let ww = $derived(wave_display_length / width);
    let ticks = $derived.by(() => {
        // let step = Math.floor(wave_scale*8000) / 200; // part of this operation is scaling, and part is arbitrary step frequency
        // let step = 
        // step1 = wave_scale;
        // step2 = step;
        // step3 = step2 * 2;
        // step4 = step3 * 3;
        // step2 = step * 2 / 5;
        const a = [];
        // const ww = wave_display_length / width;
        for(let i = 1; i < 40; i++){
            let ii = round_to_6_places(i*step);
            let x = ii / ww;
            if(x >= 0 && x <= width){
                let o = { x: x };
                if(i % 2 == 0){
                    o.time_x = x;
                    o.text = '123.4';
                }
                a.push(o);
            }
        }
        if(a.length){
            for(let i = 1; i < 40; i++){
                let ii = round_to_3_places(i*step+wave_display_offset);
                if(i % 2 == 0){
                    a[i-1].text = ii.toString();
                }
            }
        }
        return a;
    });

    let draw_underlines_flag = $state(true);
    // let underline_height = $state(5);
    let cursor_class = $state("cursor-auto");

    // movement mode
    // move cursor, window, beg (of selction), or end (of selection)
    let mode = $state('window');

    let active_channeln = $state(0); // 0 or 1
    // let active_top = $state(0); // the top of divs that can be on either channel, like the cursor

    // define the viewable portion of the waveform
    let wave_display_offset = $derived(activeo.wave_display_offset);
    let wave_display_length = $derived(activeo.wave_display_length);
    let wave_scale = $derived(wave_display_length / width);
    // define the selected portion of the waveform
    let wave_selection_offset = $derived(activeo.wave_selection_offset);
    let wave_selection_length = $derived(activeo.wave_selection_length);
    let wave_selection_end = $derived(round_to_3_places(activeo.wave_selection_offset + activeo.wave_selection_length));
    let wave_selection_src = $derived({
        beg: activeo.wave_selection_offset,
        end: activeo.wave_selection_offset + activeo.wave_selection_length
    });
    let selection_beg_x = $derived(convert_seconds_to_pixels_by_offset(wave_selection_offset));
    let selection_end_x = $derived(convert_seconds_to_pixels_by_offset(wave_selection_end));
    // let selection_widthx = selection_end_x - selection_beg_x;
    // let ww = convert_seconds_to_pixels(wave_selection_length);
    // if (selection_widthx!=ww && ww!=0) event.dispatch(selection_rect, 'drew_selection');

    // let wave_scale;
    // let wave_buffer_sample_rate;
    // step1 is a fixed 0.1s so selection-edge / smallest cursor nudges
    // are a consistent, predictable increment regardless of zoom level.
    const step1 = 0.1;
    let step2 = $derived(step * 2 / 5);
    let step3 = $derived(step2 * 2);
    let step4 = $derived(step3 * 3);

    // Visual mode banner: shows current mode and the per-key step durations.
    // Palette is shared with the cheat sheet via bindings.js.
    let mode_meta = $derived(mode_palette[mode] || mode_palette.cursor);
    let mode_keys_a = $derived.by(() => {
        if (mode === 'window') {
            const wl = wave_display_length;
            return [
                { key: 'a', s: wl * 2,   dir: 'left' },
                { key: 's', s: wl * 1,   dir: 'left' },
                { key: 'd', s: wl * 0.5, dir: 'left' },
                { key: 'f', s: step3,    dir: 'left' },
                { key: 'j', s: step3,    dir: 'right' },
                { key: 'k', s: wl * 0.5, dir: 'right' },
                { key: 'l', s: wl * 1,   dir: 'right' },
                { key: ';', s: wl * 2,   dir: 'right' }
            ];
        }
        if (mode === 'selection') {
            // Only 4 keys are bound in selection mode: d/f for the begin
            // edge, j/k for the end edge. All at the smallest step.
            return [
                { key: 'd', s: step1, dir: 'left',  edge: 'beg' },
                { key: 'f', s: step1, dir: 'right', edge: 'beg' },
                { key: 'j', s: step1, dir: 'left',  edge: 'end' },
                { key: 'k', s: step1, dir: 'right', edge: 'end' }
            ];
        }
        // cursor: full 8-key span using step1..step4
        return [
            { key: 'a', s: step4, dir: 'left' },
            { key: 's', s: step3, dir: 'left' },
            { key: 'd', s: step2, dir: 'left' },
            { key: 'f', s: step1, dir: 'left' },
            { key: 'j', s: step1, dir: 'right' },
            { key: 'k', s: step2, dir: 'right' },
            { key: 'l', s: step3, dir: 'right' },
            { key: ';', s: step4, dir: 'right' }
        ];
    });
    function format_step(s) {
        if (!isFinite(s) || s <= 0) return '–';
        if (s < 0.1)  return Math.round(s * 1000) + 'ms';
        if (s < 1)    return (Math.round(s * 100) / 100).toFixed(2) + 's';
        if (s < 10)   return (Math.round(s * 10) / 10).toFixed(1) + 's';
        return Math.round(s) + 's';
    }

    function convert_seconds_to_pixels(seconds){ return seconds / wave_scale; }
    function convert_pixels_to_seconds(pixels){ return pixels * wave_scale; }
    function convert_seconds_to_pixels_by_offset(seconds){
        const diff = seconds - wave_display_offset;
        if(diff <= 0) return 0;
        if(diff > wave_display_length) return convert_seconds_to_pixels(wave_display_length);
        else                           return convert_seconds_to_pixels(diff);
    }


        // selection_beg_x = convert_seconds_to_pixels_by_offset(wave_selection_offset);
        // selection_end_x = convert_seconds_to_pixels_by_offset(wave_selection_end);

    // all the divs have to match this width for calculations to make sense
    // let width;
    let time_height = $state(0);
    let ew = $derived(width / duration);
    let scrollbar_x = $derived(wave_display_offset * ew);
    let scrollbar_width = $derived(wave_display_length * ew);
    // the x position of these events, in real time
    let mousedown_x = $state();
    let mouseup_x = $state();
    let mousemove_x = $state();

    let mousedown_b = $state();
    let cursor_x = $derived(mousemove_x === 0 ? 0 : (mousemove_x || mousedown_x));
    let cursortime = $derived(convert_pixels_to_seconds(cursor_x) + wave_display_offset);
    let text = $derived(round_to_3_places(cursortime).toString());

    // let samples_per_pixel = $state();
    // const samples_per_pixel_threshold = 200; // for deciding whether to draw an envelope or a graph

    let line = false;
    let max_only = true;
    let sample_skip = 1;
    let disable_waveform = $state(false);

    let wave_adjust_btime = $state(false);
    let wave_adjust_etime = $state(false);
    let wave_adjust_time = $state(false);
    let wave_adjust_scroll = $state(false); // update waveform based on scrolling on mouse move
    let wave_autoscroll = $state(false);

    let selection_rect;
    // let selection_beg_x = $state(0);
    // let selection_end_x = $state(0);
    let selection_beg_text = $derived(round_to_3_places(convert_pixels_to_seconds(selection_end_x)+wave_display_offset).toString());
    let selection_end_text = $derived(round_to_3_places(convert_pixels_to_seconds(selection_beg_x)+wave_display_offset).toString());

    // Readouts surfaced in the top status strip. Always 3 decimal places so
    // the numbers don't twitch in width as they change.
    function fmt_time(t){ return (t == null || isNaN(t)) ? '–' : Number(t).toFixed(3); }
    let t_cursor  = $derived(fmt_time(cursortime));
    let t_play    = $derived(fmt_time(play_head));
    let t_sel_beg = $derived(fmt_time(wave_selection_offset));
    let t_sel_end = $derived(fmt_time(wave_selection_end));
    let t_sel_dur = $derived(fmt_time(wave_selection_length));
    let t_win_beg = $derived(fmt_time(wave_display_offset));
    let t_win_end = $derived(fmt_time(wave_display_offset + wave_display_length));
    let has_selection = $derived(wave_selection_offset != null && wave_selection_length > 0);

    let redacted_selection_x = $state(0);
    let redacted_selection_width = $state(0);
    let redacted_selection_height = $derived(wave_canvas_height * nchannels);
    let redacted_selection_beg_text = $state('');
    let redacted_selection_end_text = $state('');
    let all_redactions = $state([]);
    // let visible_redactions = $state([]);

    let playheadx = $state();
    let playheadtext = $state('123.456');

    export function set_all_redactions(x){
        all_redactions = x;
        // visible_redactions = find_redactions();
    }

    let visible_redactions = $derived.by(() => {
        const some = [];
        for(const r of all_redactions){
            let wave_display_end = wave_display_offset + wave_display_length;
            if(r.beg < wave_display_end && r.beg > wave_display_offset){
                let x = r.beg < wave_display_offset ? wave_display_offset : r.beg;
                let y = r.end > wave_display_end ? wave_display_end : r.end;
                some.push({
                    redacted_selection_x: convert_seconds_to_pixels(x - wave_display_offset),
                    redacted_selection_width: convert_seconds_to_pixels(y - x),
                    redacted_selection_beg_text: x,
                    redacted_selection_end_text: y
                });
            }
        }
        return some;
    });

    // const un3 = times.subscribe( (x) => {
    //     wave_display_offset = x.wave_display_offset;
    //     wave_display_length = x.wave_display_length;
    //     wave_scale = wave_display_length / width;
    //     // if(width != x.width && wave_display_length){
    //     //     width = x.width;
    //     // }
    //     // draw_ticks();
    //     let ew = width / duration;
    //     scrollbar_x = wave_display_offset * ew;
    //     scrollbar_width = wave_display_length * ew;
    //     // event.dispatch(this, 'drew_scroll_cursor');
    //     if(wave_display_length){
    //         for(let i = 0; i < nchannels; i++) draw_waveformi(i);
    //     }
    //     // srcs_update(srcso);
    //     visible_redactions = find_redactions();

    //     selection_beg_x = convert_seconds_to_pixels_by_offset(wave_selection_offset);
    //     selection_end_x = convert_seconds_to_pixels_by_offset(wave_selection_end);

    // } );
    // const un4 = selection.subscribe( (x) => {
    //     wave_selection_offset = x.wave_selection_offset;
    //     wave_selection_length = x.wave_selection_length;
    //     wave_selection_end = x.wave_selection_end;
    //     wave_selection_src = {
    //         beg: wave_selection_offset,
    //         end: wave_selection_offset + wave_selection_length
    //     };
    //     selection_beg_x = convert_seconds_to_pixels_by_offset(wave_selection_offset);
    //     selection_end_x = convert_seconds_to_pixels_by_offset(wave_selection_end);
    //     let selection_widthx = selection_end_x - selection_beg_x;
    //     let ww = convert_seconds_to_pixels(wave_selection_length);
    //     if (selection_widthx!=ww && ww!=0) event.dispatch(selection_rect, 'drew_selection');
    //     // selection_width = ww;
    // } );

    // onDestroy( () => {
    //     un3();
    //     un4();
    // } );
    let active_top = $derived.by(() => {
        let x = 0;
        for(let i = 0; i < activeo.channel; i++){
            x += wave_canvas_height + underlines[i].u.height;
        }
        return x;
    });

    export function activate(active_channel){
        if(active_channeln != active_channel){
            activeo.channel = active_channel;
            let i = active_channel;
            let s = source_uid_channels.length > 1 ? source_uid_channels[i] : source_uid_channels[0];
            set_audio_id_to_channel(s, i);
            active_channeln = active_channel;
            return true;
        }
        return false;
    }
    class Underline {
        docid = $state();
        u = $derived(create_underlines(
            this.docid,
            sourceso.srcs,
            sourcesor.srcs,
            activeo.wave_display_length,
            activeo.wave_display_offset,
            width,
            5
        ));
        constructor(docid){
            this.docid = docid;
        }
    }
    let underlines = [];
    for(let i = 0; i < 4; i++) underlines.push(new Underline(docids[i]));
    function create_underlines(docid, srcs, srcsr, wave_display_length, wave_display_offset, width, underline_height){
        srcs = srcsr;
        // const docid = docids[i];
        // const srcs = sourceso.srcs;
        // const srcsr = sourcesor.srcs;
        // const wave_display_length = activeo.wave_display_length;
        // const wave_display_offset = activeo.wave_display_offset;
        const wave_scale = wave_display_length / width;
        let max_level = 0;
        // if(srcs[docid] == undefined) return false; // No underlines: force refresh
        //cycle through the sources and find the maximum level
        // for(const k in srcs[docid]){
        //     let src = srcs[docid][k];
        //     if(src.level > max_level){
        //         max_level = src.level;
        //     }
        // }
        // console.log max_level
        const line_obj = {}
        // data.line_obj = line_obj;
        // line_obj.underlines_width = width;
        // line_obj.underlines_selector = '.waveform-underlines';
        //cycle through the sources for this line, compute the width and offset, and draw the underline
        // console.log('U1');
        // console.log(srcs);
        const wave_display_end = wave_display_offset + wave_display_length;
        line_obj.a = [];
        let uoffset;
        let uwidth;
        for(const k in srcs[docid]){
            // console.log('U2');
            let src = srcs[docid][k];
            // console.log(src.end >= wave_display_offset )
            if(src.end >= wave_display_offset && src.beg <= wave_display_end){
                // console.log 'U3'
                if(src.level > max_level) max_level = src.level;
                if(src.beg > wave_display_offset){
                    uoffset = src.beg - wave_display_offset;
                    uwidth = (src.end > wave_display_end ? wave_display_end : src.end) - src.beg;
                }
                else{
                    uoffset = 0;
                    uwidth = src.end > wave_display_end ? width : src.end - wave_display_offset;
                }
                uoffset /= wave_scale;
                uwidth /= wave_scale;
                if(debug){
                    console.log("DEBUG");
                    console.log(src);
                    console.log(uoffset);
                    console.log(uwidth);
                }
                // console.log "U4 #{uoffset} #{uwidth} #{src.node}" if @debug
                let underline_color = 'blue';
                let aa = {
                    node_id: src.node,
                    class: `node-${src.node}`,   // Necessary to match underlines with segments in tutorial
                    width: uwidth,
                    // height: @underline_height
                    x: uoffset,
                    // depth = depth * ( underline_height * 2 + 1 )
                    y: (src.level * ( underline_height + 5 + 1 )), // instead of doubling, just add 5
                    fill: underline_color
                }
                line_obj.a.push(aa);
            }
        }
        //calculate the height based on the maximum level, width based on the line width
        line_obj.height = (max_level + 1) * (underline_height * 2 + 1);
        // underlinesa = line_obj.a;
        // underlinesheight = line_obj.height;
        return line_obj;
    }

    // sets an endpoint for the selection
    // actually just sets the mousedown flag, but logically sets the start point
    function set_mousedown_true(){
        mousedown_b = true;
        mouseup_x = false;
        mousemove_x = false;
        wave_adjust_time = wave_adjust_btime || wave_adjust_etime;
        if(debug){
          console.log('updatedown');
          console.log(wave_adjust_btime)
        }
        return true;
    }

    export function get_mode(){ return mode }
    export function set_mode(x){
        if (x === mode) return;
        mode = x;
        // If switching into selection mode without any selection yet, create
        // a zero-width selection at the cursor so the edge-move keys have
        // something to act on.
        if (x === 'selection' && wave_selection_offset == null && mousemove_x != null) {
            set_current_selection(convert_pixels_to_seconds(mousemove_x) + wave_display_offset, 0);
        }
    }
    
    export function set_times_then_draw(x, y){
        set_times(x, y);
    }
    function set_times(x, y){
        // if(!wave_buffer_sample_rate) delay(w,x,y);
        if(x < 0) x = 0;
        if(y > duration) y = duration;
        if(x + y > duration) x = duration - y;
        // times.update( (t) => {
            activeo.wave_display_offset = x;
            activeo.wave_display_length = y;
            // wave_scale = y / width;
            // sample_calculations(x, y);
            // return t;
        // } );
        if(debug) console.log(`update set wave display offset ${x} length ${y} and ${samples_per_pixel}`);
        // w.update_cursor = true;
        // w.update_scrollbar = true;
        // w.update_underlines = true;
        // w.update_play_head = true;
        // w.update_tick_times = true;
        // w.update_waveform = true;
        // this.draw_wave_display()
    }

    // sets a selection in concert with set_mousedown_true
    // only function that calls wave_update
    function set_mousedown_false() {
        // var b, e, length, mouseup_time, offset, p2s, w;
        // w = this;
        console.log('a');
        if(!mousedown_b){ return; }
        console.log('b');
        console.log(wave_adjust_time);
        if(wave_adjust_time){
            if(mousemove_x){
                const mouseup_time = convert_pixels_to_seconds(mouseup_x) + wave_display_offset;
                if(wave_adjust_btime){
                    if(mouseup_time < wave_selection_end){
                        wave_update(mouseup_time, wave_selection_end - mouseup_time);
                    }
                }
                else{
                    if(wave_selection_offset < mouseup_time){
                        wave_update(wave_selection_offset, mouseup_time - wave_selection_offset);
                    }
                }
                // Notify the transcription guide's "Adjust the selection"
                // step — fires only on the edge-drag path, not on
                // fresh-selection drags.
                mark_transcription('selection_adjusted');
            }
        }
        else{
            let b;
            let e;
            // the user can make the selection in either direction,
            // so here we normalize so begin is always less than end
            if(mouseup_x > mousedown_x){
                b = mousedown_x;
                e = mouseup_x;
            }
            else{
                b = mouseup_x;
                e = mousedown_x;
            }
            const p2s = convert_pixels_to_seconds; // only relative to visible region
            // the following only works if the displayed region didn't change,
            // in other words scrolling didn't occur during selection
            const offset = convert_pixels_to_seconds(b) + wave_display_offset;
            const length = convert_pixels_to_seconds(e - b);
            wave_update(offset, length);
        }
        if(debug){
            console.log('updateup');
        }
        mousedown_b = false;
        wave_adjust_time = false;
        wave_adjust_scroll = false;
        return controls.keyboard_focus();
    }

    // current selection == internal selection times
    // normally there's no difference between the visible selection and the "current" selection
    // when the mouse is down, there is a distinction, and this function syncs them back up,
    // changing the current selection to match the visible selection.
    // optionally modifies a transcript line as well to match this "current" selection (if there's an active line)
    // sets wave_selection_offset wave_length and wave_selection_end, and adjusts transcript line timestamps
    function wave_update(span_offset, span_length) {
        span_offset = round_to_3_places(span_offset);
        span_length = round_to_3_places(span_length);
        if (debug) { //@debug
            console.log('update');
            console.log(span_offset);
            console.log(span_length);
            console.log(wave_selection_offset);
            console.log(wave_selection_length);
        }
        const span_end = round_to_3_places(span_offset + span_length);
        if (debug) {
            if (wave_active_transcript_line) {
                console.log("active line before is " + wave_active_transcript_line.replace('node-', ''));
            } else {
                console.log("no active line");
            }
        }
        // this section handles updating a transcript line
        if (wave_selection_offset !== span_offset && wave_selection_end !== span_end) {
            console.log('setting to null');
            set_active_transcript_line_helper(null);
            // if(ldc.active_channel()){
                segmentsc.set_active_transcript_line(null);
            // }
        }
        if ((wave_selection_offset !== span_offset || wave_selection_length !== span_length) && wave_active_transcript_line) {
            let n = wmap.get(wave_active_transcript_line);
            console.log(n);
            // Dragging an edge re-times the anchor that edge points at.
            if(wave_selection_offset !== span_offset) update_node(docids[activeo.channel], n, span_offset, 'beg');
            if(wave_selection_end !== span_end)       update_node(docids[activeo.channel], n, span_end,    'end');
        }
        // end section
        set_current_selection(span_offset, span_length);
        if (debug) {
            if (wave_active_transcript_line) {
                return console.log("active line before is " + wave_active_transcript_line.replace('node-', ''));
            } else {
                return console.log('no active line');
            }
        }
    }

    function set_move_params(){
        if(
            (Math.abs(mousemove_x - convert_seconds_to_pixels(wave_selection_offset - wave_display_offset)) < 20) ||
            (Math.abs(mousemove_x - convert_seconds_to_pixels(wave_selection_end - wave_display_offset)) < 20)
        ){
            cursor_class = "col-resize";
        }
        else{
            cursor_class = "auto";
        }
        // return unless that.check_channel this
        wave_adjust_scroll = false;
        if(!wave_adjust_time){
            wave_adjust_btime = false;
            wave_adjust_etime = false;
            // if w.mousedown_x and w.mousedown_x isnt w.mouseup_x
            if(wave_selection_length !== null && wave_selection_length !== 0){
                if(true){ //Math.abs(e.clientY - rect.top - wave_canvas_height / 2) < 20
                    if(Math.abs(mousemove_x - convert_seconds_to_pixels(wave_selection_offset - wave_display_offset)) < 20){
                        wave_adjust_btime = true;
                    }
                    if(Math.abs(mousemove_x - convert_seconds_to_pixels(wave_selection_end - wave_display_offset)) < 20){
                        wave_adjust_etime = true;
                        wave_adjust_btime = false; // so they can't both be true
                    }
                }
            }
        }
        if(debug){
            let time = round_to_3_places(convert_pixels_to_seconds(mousemove_x) + wave_display_offset).toString();
            console.log(`updatemove ${time} seconds`);
        }
        if(mousedown_x && !(wave_autoscroll || mouseup_x)){
            autoscroll_jump();
        }
        // return w.update_cursor = true;
    }

    export function move_cursor(x, factor){
        console.log('helping1');
        console.log(x);
        const step = convert_seconds_to_pixels(x * factor);
        mousemove_x = cursor_x + step;
        set_move_params();
        // selection.update( (x) => x );
    }


    export function move_window(x, factor){
        // set_times_then_draw protects against out of range
        set_times_then_draw(wave_display_offset + (x * factor), wave_display_length);
        event.dispatch(null,"moved_window");
    }
    let zoom;
    // keep center point the same, but toggle between step size of .5s and .2s
    export function toggle_zoom() {
        zoom = !zoom;
        let z;
        if (zoom) {
            z = 0.005;
        } else {
            z = 0.0125;
        }
        let c;
        if (wave_selection_offset) {
            c = wave_selection_offset + wave_selection_length / 2;
        } else {
            c = wave_display_offset + wave_display_length / 2;
        }
        const ww = z * width;
        set_times_then_draw(c - ww / 2, ww);
    }

    export function zoom_in() {
        const q = wave_display_length / 4;
        let r;
        if (wave_selection_offset) {
            r = set_times_then_draw(wave_selection_offset + wave_selection_length / 2 - q, q * 2);
        } else {
            r = set_times_then_draw(wave_display_offset + q, q * 2);
        }
        event.dispatch(null,'zoomed_in');
    }

    export function zoom_out() {
        let r;
        if (wave_selection_offset) {
            r = set_times_then_draw(wave_selection_offset + wave_selection_length / 2 - wave_display_length, wave_display_length * 2);
        } else {
            r = set_times_then_draw(wave_display_offset - wave_display_length / 2, wave_display_length * 2);
        }
        event.dispatch(null,'zoomed_out');
    }

  function mousemove(e){
        const x = e.clientX - this.getBoundingClientRect().left;
        // mouse.update( (m) => {
            mousemove_x = x;
            set_move_params();
            set_selection_from_mouse();
            // return m;
        // } );
        // Notify the transcription guide's "Position the cursor" step —
        // any mouse motion over the waveform moves the red cursor. The
        // guide's effect is idempotent, so re-firing on every mousemove
        // is fine.
        mark_transcription('cursor_positioned');
    }

    function mousedown(e){
        mousedown_helper(e, this);
    }
    
    function mousedown_helper(e, that){
        // state.set('mousedown_waveform');
        create_action('down');
        const x = (e.clientX - that.getBoundingClientRect().left);
        // mouse.update( (m) => {
            mousedown_x = x;
            set_mousedown_true();
            // return m;
        // } );
    }


    function mouseup(e){
            const x = e.clientX - this.getBoundingClientRect().left;
            const was_drag = mousedown_x !== false && mousedown_x !== x;
            mouseup_helper(x);
            // If the click-drag-release left a non-empty selection, notify
            // the transcription guide ("Make a selection" step advances on
            // this milestone). Plain clicks (no drag → length 0) don't fire.
            if (wave_selection_length > 0) {
                mark_transcription('selection_drawn');
                // Also count any drag on the waveform as "adjustment" for
                // the "Adjust the selection" step. Firing on any drag —
                // not just the edge-detection path — makes the slide
                // advance even if the user's click landed a few pixels
                // outside the 20px edge-detection window.
                if (was_drag) mark_transcription('selection_adjusted');
            }
    }

    function mouseup_helper(x){
        // mouse.update( (m) => {
            mouseup_x = x;
            set_mousedown_false();
            // return m;
        // } );
    }

    mouse.subscribe( x => { if(x) mouseup_helper(x.x) } );

    export function cursor_time(){
        return cursortime;
    }

    function set_selection_from_mouse(){
        if(mousedown_x && ! mouseup_x){
            if(mousemove_x && ( mousedown_x != mousemove_x )){
                let epix;
                if(wave_adjust_time){
                    if(wave_adjust_btime){
                        // epix = selection_beg_x + selection_width;
                        if(mousemove_x > selection_end_x) selection_beg_x = selection_end_x;
                        else                              selection_beg_x = mousemove_x;
                        // selection_width = epix - selection_beg_x;
                        // epix = convert_seconds_to_pixels(wave_selection_end-wave_display_offset);
                    }
                    else{
                        // selection_beg_x = convert_seconds_to_pixels(wave_selection_offset-wave_display_offset);
                        // epix = mousemove_x;
                        if(mousemove_x < selection_beg_x) selection_end_x = selection_beg_x;
                        else                              selection_end_x = mousemove_x;
                    }
                    event.dispatch(null,'adjusted_time');
                    // Also notify the transcription guide's "Adjust the
                    // selection" step during the drag — fires on every
                    // adjust-mousemove, but the guide effect is
                    // idempotent, so re-fires are harmless. This
                    // supplements the fire in set_mousedown_false so a
                    // brief nudge still advances the slide even if
                    // wave_adjust_time somehow clears before mouseup.
                    mark_transcription('selection_adjusted');
                    // const ww = epix - selection_beg_x;
                    // if (selection_width!=ww && ww!=0)
                    event.dispatch(selection_rect, 'drew_selection');
                    // selection_width = ww;
                }
                else{
                    if(mousedown_x < mousemove_x){
                        selection_beg_x = mousedown_x;
                        selection_end_x = mousemove_x;
                    }
                    else{
                        selection_beg_x = mousemove_x;
                        selection_end_x = mousedown_x;
                    }
                    const ww = selection_end_x - selection_beg_x;
                    // if (selection_width!=ww && ww!=0) event.dispatch(selection_rect, 'drew_selection');
                    if (ww!=0) event.dispatch(selection_rect, 'drew_selection');
                    // selection_width = ww;
                }
            }
        }
    }

    function draw_play_head(){
        // if(!active) return;
        // width = width;
        // height = wave_canvas_height;
        const draw_time = true; // i == 0;
        // adds 50 ms or more to draw play head
        playheadx = convert_seconds_to_pixels(play_head - wave_display_offset);
        // canvas = $(selector)[0]
        // ctx = canvas.getContext "2d"
        // ctx.clearRect 0, 0, canvas.width, canvas.height
        // ctx.beginPath()
        // @draw_waveform_line @selector_play_head, x, 'green', draw_time


        if(playheadx < 0 || playheadx > width){
            return;
        }
        if(draw_time){
            playheadtext = round_to_3_places(convert_pixels_to_seconds(playheadx)+wave_display_offset).toString();
        }
    }
    const playheads = new Map();
    playheads.set(0, draw_play_head);
    export function draw_play_heads(){
        for( const [ k, v ] of playheads) v();
    }

   
    function mousemove_underlines(e){
        wave_adjust_scroll = false;
    }

    function mousemove_ticks(e){
        wave_adjust_scroll = false;
    }

    // this function wraps center_display_at_time, but determines the
    // location based on the scrollbar as a representation for the full file
    function scrollf(x) {
        let noffset = round_to_3_places(x / width * duration);
        let max = round_to_3_places(duration - wave_display_length / 2);
        if(noffset > max){
            noffset = max;
        }
        let min = round_to_3_places(wave_display_length / 2);
        if(noffset < min){
            noffset = min;
        }
        center_display_at_time(noffset);
        return console.log(`scroll ${wave_adjust_scroll}`);
    };
    // this handler would enable true scrolling, rather than just jumping
    // $(w.selector).on 'mousemove', '.waveform-scrollbar', (e) ->
    //     # return unless that.check_channel this
    //     return unless wave_adjust_scroll
    //     # selector = '.waveform-scrollbar'
    //     # rect = $(selector)[w.active_channel].getBoundingClientRect()
    //     rect = this.getBoundingClientRect()
    //     w.mousemove_x = e.clientX - rect.left
    //     scrollf w.mousemove_x
    function mousedown_scrollbar(e){
        mark_transcription('scrollbar_click');
        return wave_adjust_scroll = true;
    }
    function mouseup_scrollbar(e) {
        if(debug){
            console.log("mousemove_x");
        }
        // return unless that.check_channel this
        if(!wave_adjust_scroll){
            return;
        }
        // selector = '.waveform-scrollbar'
        // rect = $(selector)[w.active_channel].getBoundingClientRect()
        const rect = this.getBoundingClientRect();
        mouseup_x = e.clientX - rect.left;
        scrollf(mouseup_x);
        wave_adjust_scroll = false;
        controls.keyboard_focus();
    }

    export function center_display_at_time(c){
        // console.log 'centering at ' + c
        // console.log 'display length: ' + wave_display_length
        if(debug){
            console.log(`center ${c}`);
        }
        let b = c - wave_display_length / 2;
        set_times_then_draw(b, wave_display_length);
    }

    export function move_cursor_lstep1(){ move_cursor(step1, -1); }
    export function move_cursor_lstep2(){ move_cursor(step2, -1); }
    export function move_cursor_lstep3(){ move_cursor(step3, -1); }
    export function move_cursor_lstep4(){ move_cursor(step4, -1); }
    export function move_cursor_rstep1(){ move_cursor(step1, 1); }
    export function move_cursor_rstep2(){ move_cursor(step2, 1); }
    export function move_cursor_rstep3(){ move_cursor(step3, 1); }
    export function move_cursor_rstep4(){ move_cursor(step4, 1); }
    // Keyboard edge adjustment for unified selection mode. d/f move beg,
    // j/k move end. Each press steps by `step1` (smallest), clamped so the
    // edges can't cross or leave the audio.
    //
    // Route through wave_update (not set_current_selection) so the new extent is
    // persisted to the active transcript line, exactly like the mouse edge-drag
    // path in set_mousedown_false. set_current_selection only moves the on-screen
    // selection and never saves, so keyboard edge edits were silently discarded.
    // A single-edge move only changes one boundary, so wave_update's "both edges
    // moved -> deselect" guard never trips here; it saves the changed edge and
    // then syncs the selection itself.
    function move_selection_edge(edge, factor){
        if (wave_selection_offset == null) return;
        const delta = step1 * factor;
        let beg = wave_selection_offset;
        let end = wave_selection_end;
        if (edge === 'beg') beg = Math.max(0, Math.min(end, beg + delta));
        else                end = Math.max(beg, Math.min(duration, end + delta));
        wave_update(round_to_3_places(beg), round_to_3_places(end - beg));
    }
    export function move_beg_left()  { move_selection_edge('beg', -1); }
    export function move_beg_right() { move_selection_edge('beg', +1); }
    export function move_end_left()  { move_selection_edge('end', -1); }
    export function move_end_right() { move_selection_edge('end', +1); }
    export function move_window_lstep1(){ move_window(step3, -1); }
    export function move_window_lstep2(){ move_window(wave_display_length, -0.5); }
    export function move_window_lstep3(){ move_window(wave_display_length, -1); }
    export function move_window_lstep4(){ move_window(wave_display_length, -2); }
    export function move_window_rstep1(){ move_window(step3, 1); }
    export function move_window_rstep2(){ move_window(wave_display_length, 0.5); }
    export function move_window_rstep3(){ move_window(wave_display_length, 1); }
    export function move_window_rstep4(){ move_window(wave_display_length, 2); }

    function autoscroll_jump() {
        const ww = width / 100;
        const jump = ww * 50;
        const s = convert_pixels_to_seconds(jump);
        if(mousemove_x < ww && mousedown_x > ww){
            if(s < wave_display_offset){
               mousedown_x += jump;
               set_times_then_draw(wave_display_offset - s, wave_display_length);
            }
            wave_autoscroll = true;
        }
        else if(width - mousemove_x < ww && width - mousedown_x > ww){
            if(s + wave_display_offset + wave_display_length < duration){
                mousedown_x -= jump;
                set_times_then_draw(wave_display_offset + s, wave_display_length);
            }
            wave_autoscroll = true;
        }
        else{
            wave_autoscroll = false;
        }
        if(wave_autoscroll){
            setTimeout(function() {
                autoscroll_jump();
            }, 1000);
        }
    }

    let mode_menu_open = $state(false);
    function open_mode_menu(){
        mode_menu_open = true;
    }
    function mode_keydown(e){
        const k = e.detail.originalEvent.key;
        if(k == 'c'){
            set_mode('cursor');
        }
        else if(k == 'w'){
            console.log('w')
            set_mode('window');
        }
        else if(k == 'b' || k == 'e'){
            set_mode('selection');
        }
        if(['c', 'w', 'b', 'e'].includes(k)){
            mode_menu_open = false;
            event.dispatch('drew_mode');
        }
    }

    export function draw_underlines(o){
        for(let i = 0; i < nchannels; i++){
            // if(channels[i]) channels[i].draw_underlines(docids[i], o);
        }
    }

</script>

<!-- <div class="mode text-center col-span-3 float-left" use:event.dispatch={'drew_mode'}>
    <DropdownMenu.Root bind:open={mode_menu_open} closeFocus={".keyboard"} closeOnEscape={false}>
        <DropdownMenu.Trigger>{mode}</DropdownMenu.Trigger>
        <DropdownMenu.Content on:keydown={mode_keydown}>
            <DropdownMenu.Group>
                <DropdownMenu.Label>Command Mode</DropdownMenu.Label>
                <DropdownMenu.Separator />
                <DropdownMenu.RadioGroup bind:value={mode}>
                <DropdownMenu.RadioItem value="cursor">
                    <div class="flex items-center">
                        Cursor
                    </div>
                    <div class="ml-auto flex items-center gap-px">
                        <kbd class="inline-flex size-5 items-center justify-center rounded-button border border-dark-10 bg-background-alt text-[10px] text-muted-foreground shadow-kbd">
                            Esc
                        </kbd>
                        <kbd class="inline-flex size-5 items-center justify-center rounded-button border border-dark-10 bg-background-alt text-[10px] text-muted-foreground shadow-kbd">
                            C
                        </kbd>
                    </div>
                </DropdownMenu.RadioItem>
                <DropdownMenu.RadioItem value="window">
                    <div class="flex items-center">
                        Window
                    </div>
                    <div class="ml-auto flex items-center gap-px">
                        <kbd class="inline-flex size-5 items-center justify-center rounded-button border border-dark-10 bg-background-alt text-[10px] text-muted-foreground shadow-kbd">
                            Esc
                        </kbd>
                        <kbd class="inline-flex size-5 items-center justify-center rounded-button border border-dark-10 bg-background-alt text-[10px] text-muted-foreground shadow-kbd">
                            W
                        </kbd>
                    </div>
                </DropdownMenu.RadioItem>
                <DropdownMenu.RadioItem value="beg">
                    <div class="flex items-center">
                        Begin
                    </div>
                    <div class="ml-auto flex items-center gap-px">
                        <kbd class="inline-flex size-5 items-center justify-center rounded-button border border-dark-10 bg-background-alt text-[10px] text-muted-foreground shadow-kbd">
                            Esc
                        </kbd>
                        <kbd class="inline-flex size-5 items-center justify-center rounded-button border border-dark-10 bg-background-alt text-[10px] text-muted-foreground shadow-kbd">
                            B
                        </kbd>
                    </div>
                </DropdownMenu.RadioItem>
                <DropdownMenu.RadioItem value="end">
                    <div class="flex items-center">
                        End
                    </div>
                    <div class="ml-auto flex items-center gap-px">
                        <kbd class="inline-flex size-5 items-center justify-center rounded-button border border-dark-10 bg-background-alt text-[10px] text-muted-foreground shadow-kbd">
                            Esc
                        </kbd>
                        <kbd class="inline-flex size-5 items-center justify-center rounded-button border border-dark-10 bg-background-alt text-[10px] text-muted-foreground shadow-kbd">
                            E
                        </kbd>
                    </div>
                </DropdownMenu.RadioItem>
                </DropdownMenu.RadioGroup>
            </DropdownMenu.Group>
        </DropdownMenu.Content>
    </DropdownMenu.Root>
</div> -->

{#snippet time_readout()}
    <div class="flex items-center gap-3 font-mono tabular-nums">
        <div class="flex items-center gap-1.5">
            <span class="w-3 h-2 rounded-sm bg-blue-500/60" title="window"></span>
            <span>{t_win_beg}–{t_win_end}s</span>
        </div>
        <div class="flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-full bg-red-500" title="cursor"></span>
            <span>{t_cursor}s</span>
        </div>
        <div class="flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-full bg-green-500" title="playhead"></span>
            <span>{t_play}s</span>
        </div>
        {#if has_selection}
            <div class="flex items-center gap-1.5">
                <span class="w-3 h-2 rounded-sm bg-red-500/60" title="selection"></span>
                <span>{t_sel_beg}–{t_sel_end}s</span>
                <span class="opacity-70">({t_sel_dur}s)</span>
            </div>
        {/if}
    </div>
{/snippet}

<div
    class="mode-banner w-full flex items-center h-6 px-2 gap-3 text-[11px] leading-none select-none shadow-sm {mode_meta.bg} {mode_meta.text}"
    use:event.dispatch={'drew_mode_banner'}
>
    <div class="font-semibold uppercase tracking-wide">{mode_meta.label}</div>
    <div class="flex-1 flex items-center justify-center gap-1 text-[10px]">
        {#each mode_keys_a as { key, s, dir }, idx}
            {#if idx === mode_keys_a.length / 2}
                <div class="w-px h-3 bg-current/30 mx-1"></div>
            {/if}
            <div class="flex items-center gap-0.5">
                <kbd class="inline-flex items-center justify-center min-w-[14px] h-[14px] px-1 rounded border border-current/40 bg-white/60 font-mono">{key === ';' ? ';' : key}</kbd>
                <span class="tabular-nums opacity-80">{dir === 'left' ? '←' : '→'}{format_step(s)}</span>
            </div>
        {/each}
    </div>
    {@render time_readout()}
</div>

<!-- <div bind:this={div} id="node-00" class="ChannelA Waveform active_channel" use:watchResize={resize}> -->
<div id="node-00" class="ChannelA Waveform active_channel relative" use:event.dispatch={'drew_waveform'} style="width: {width}px" >
    {#each nchannelsa as i}
        <Channel
            bind:this={channels[i]}
            {ldc}
            {i}
            {mousedown_helper}
            {mousemove_underlines}
            {underline}
            {wave_canvas_height}
            {width}
            {wave_display_length}
            {line}
            {sample_skip}
            {max_only}
            {create_audio_hash_from_docid}
            {create_audiok_from_docid}
            {docids}
            {debug}
            {activate}
            u={underlines[i].u}
        />
    {/each}
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div
        class="z-10 absolute w-full"
        style="height: {wave_canvas_height}px; top: {active_top}px; cursor: {cursor_class}"
        onmousemove={mousemove}
        onmousedown={mousedown}
        onmouseup={mouseup}
        onmouseleave={mouseup}
        onclick={()=>{ event.dispatch(null,'clicked_on_waveform'); mark_transcription('waveform_click'); }}
    ></div>
    <div class="cursor bg-red-300 absolute w-px" style="left: {cursor_x}px; top: {active_top}px; height: {wave_canvas_height}px"></div>
    <div
        class="selection bg-red-500/50 absolute {redact_task ? "redact-opacity" : ""}"
        style="left: {selection_beg_x}px; width: {selection_end_x-selection_beg_x}px; top: {active_top}px; height: {wave_canvas_height}px"
        bind:this={selection_rect}
    ></div>
    {#each visible_redactions as x}
        <div
            class="bg-red-500 absolute"
            style="left: {x.redacted_selection_x}px; width: {x.redacted_selection_width}px; top: 0px; height: {redacted_selection_height}px"
        ></div>
        <div class="time-text absolute" style="left: {x.redacted_selection_x}px; top: 5px">{x.redacted_selection_beg_text}</div>
        <div class="time-text absolute" style="left: {x.redacted_selection_x+x.redacted_selection_width}px; top: 5px">{x.redacted_selection_end_text}</div>
        <div class="absolute text-center" style="left: {x.redacted_selection_x}px; width: {x.redacted_selection_width}px; top: {redacted_selection_height/2}px">REDACTED</div>
    {/each}

    <div class="play-head bg-green-300 absolute" style="left: {playheadx}px; top: {active_top}px; height: {wave_canvas_height}px; width: 1px"></div>

    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <!-- Time readout aligned with positions on the waveform above. Each value
         sits at the x-coordinate of its line, so it lines up with the ticks. -->
    <div class="w-full relative h-5 text-[11px] bg-gray-50 border-y border-gray-200 font-mono tabular-nums overflow-hidden">
        <!-- window bounds at the left and right edges -->
        <span class="absolute top-1 left-0 pl-1 text-blue-700">{t_win_beg}</span>
        <span class="absolute top-1 right-0 pr-1 text-blue-700">{t_win_end}</span>
        {#if has_selection}
            <span class="absolute top-1 -translate-x-1/2 text-red-700" style="left: {selection_beg_x}px">{t_sel_beg}</span>
            <span class="absolute top-1 -translate-x-1/2 text-red-700" style="left: {selection_end_x}px">{t_sel_end}</span>
        {/if}
        <span class="absolute top-1 -translate-x-1/2 text-red-500 font-bold" style="left: {cursor_x}px">{t_cursor}</span>
        <span class="absolute top-1 -translate-x-1/2 text-green-700 font-bold" style="left: {playheadx}px">{t_play}</span>
    </div>

    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="w-full waveform-ticks relative"  style="height: 20px" onmousemove={mousemove_ticks} use:event.dispatch={'drew_ticks'}>
        {#each ticks as x}
            {#if x.time_x}
                <div class="bg-black absolute" style="left: {x.x}px; width: 1px; top: 0px; height: 10px"></div>
                <div class="time-text absolute" style="left: {x.time_x}px; top: {time_height+10}px">{x.text}</div>
            {:else}
                <div class="bg-black absolute" style="left: {x.x}px; width: 1px; top: 5px; height: 5px"></div>
            {/if}
        {/each}
    </div>

    {#if scrollbar_x || scrollbar_x == 0}
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div
            class="w-full waveform-scrollbar relative bg-red-100"
            style="height: 20px"
            onmousedown={mousedown_scrollbar}
            onmouseup={mouseup_scrollbar}
            onmouseleave={mouseup_scrollbar}
            use:event.dispatch={'drew_scrollbar'}
        >
            <div class="bg-red-300 absolute h-full" style="left: {scrollbar_x}px; width: {scrollbar_width}px"></div>
        </div>
    {/if}

</div>

<style>
    .time-text {
        font: 8px sans-serif;
        text-anchor: left;
        user-select: none;
    }
</style>
