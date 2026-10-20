<script>
    import { SvelteMap } from 'svelte/reactivity';
    import { asro } from './asr.svelte';
  import { run } from 'svelte/legacy';

    import { Toaster } from "$lib/components/ui/sonner";
    import { toast } from "svelte-sonner";
    import * as DropdownMenu from "$lib/components/ui/dropdown-menu"
    import * as Dialog from "$lib/components/ui/dialog"
    import * as Card from "$lib/components/ui/card"
    import { Label } from "$lib/components/ui/label"
    import * as RadioGroup from "$lib/components/ui/radio-group"
    import { Button } from "$lib/components/ui/button"
    import { ArrowUpFromLine, ArrowDownToLine, Check, X } from '@lucide/svelte';
    import { tick, createEventDispatcher, onMount, onDestroy } from 'svelte';
    const dispatch = createEventDispatcher();
    import { btn, cbtn, dbtn, btn1 } from '../work/buttons';
    import { event } from '../../../guides/guide';
    import { mark_transcription } from '../../guide_state';
    import { create_action } from '../../../work/controllers';
    import { settings, mouse, key } from './stores';
    import { transcript, set_graph, graph as graph_state } from './transcript.svelte';
    import { graph_rows } from './graph_transcript';
    import { lock_text_only, text_only_refuses } from './text_only';
    import { graph_from_payload } from './graph_from_payload';
    import { apply_message, begin_batch, apply_batched, end_batch, new_group } from './graph_write';
    import { groups } from './groups';
    import { get } from 'svelte/store';
    import { activeo, sourceso, set_reference_text, clear_reference_text } from './shared.svelte';
    import parse_tsv0 from './parse_tsv';
    import { times, round_to_3_places, round_to_6_places } from './times';
    import { sources_object_add_node } from './sources_stores';
    import { play_src_with_audio_id, redactions, local_redactions, redaction_docid } from './play';
    import { request_animation_frame_loop_init } from '../request_animation_frame_loop';
    import {
        play_callback,
        callf,
        is_playing,
        set_audio_element_with_array,
        set_audio_element_multichannel,
        set_audio_id_to_channel,
        decode_audio_data,
        stop_playing
    } from '../audio/main';
    import {
        set_ldc,
        done,
        skip,
        broken,
        add_audio_to_list,
        add_comment_to_list,
        add_audio_to_listp,
        add_audio_to_listq,
        update_node,
        split_segment_at_cursor,
        merge_with_following_segment,
        add_cb,
        delete_all,
        delete_all2,
        delete_section,
        delete_segments,
        check_for_submit,
        change_value,
        change_values,
        change_value_src,
        add_section
    } from './modification1';
    import { waveform_map as keymap, playback_map as playbackmap, text_only_forbidden } from './bindings';
    import { getp, getp_wav, postp, getp_simple } from '../getp';
    import Spinner from '../work/spinner.svelte';
    import parse_sad_with_aws from './parse_sad_with_aws';
    import parse_tsv from './parse_tsv2';
    import parse_tdf from './parse_tdf';
    import { create_transcript } from './download_transcript_helper';
    import { Keyboard } from './keyboard';
    import ServiceResponse from './service_response.svelte';
    import { fromCognitoIdentity } from "@aws-sdk/credential-provider-cognito-identity";
    import { CognitoIdentityClient } from "@aws-sdk/client-cognito-identity";
    import { TranscribeClient } from "@aws-sdk/client-transcribe";
    import { S3Client, GetObjectCommand, HeadObjectCommand, ListObjectsV2Command, PutObjectCommand } from "@aws-sdk/client-s3";
    import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
    import { getSignedUrlPromise } from '../aws_helper';

    // Dialog components (Svelte 5)
    import {
        CommandDialog,
        DeleteAllDialog,
        DeleteAllStereoDialog,
        DownloadTranscriptDialog,
        MainHelpDialog,
        SettingsDialog,
        SpectrogramDialog,
        UploadTranscriptDialog
    } from './dialogs';
    import {
        docid2channel,
        add_save_asr,
        signed_url_for_audio,
        set_urls_source,
        get_audio_buffer_info,
        fill_speakerm,
        fill_speakers,
        // three_way_split_on_selection,
        // three_way_split,
        // add_sad_send,
        // add_asr_send,
        // add_asr_sendx,
        // get_promises,
        fmap_helper
    } from './helpers';
    import Channels from './channels.svelte';
    import Segments from './segments.svelte';
    import GraphPanel from './graph_panel.svelte';
    import DesyncBanner from './desync_banner.svelte';
    import { bulko } from './bulk.svelte';
    import Sections from './sections.svelte';
    import Comments from './comments.svelte';
    import Controls from './controls/controls.svelte';
    import HelpScreen from './help_screen.svelte';
    import InputScreen from './input_screen.svelte';
    let controls = $state();

    let debug = false;
    let experimental = $state();
  let {
    ldc,
    width,
    set_urls,
    source_uid,
    source_uid_channels,
    redact_task,
    permissions,
    constraint_export_transcript,
    constraint_export_transcript_to_task_admin,
    constraint_import_transcript,
    constraint_import_transcript_auto,
    constraint_rtl,
    constraint_speakers,
    constraint_sections,
    constraint_section_order_forced,
    constraint_add_asr_segments,
    constraint_asr_korean,
    constraint_audit
  } = $props();
    let redactiondocid = $derived(redaction_docid(source_uid));
    set_ldc(ldc);
    const ns = ldc.ns;
    const data_set_id = ldc.data_set_id;
    let data_set_file_name;
    const kit_id = ldc.obj2._id;
    // The annotation graph — anchors, spans, labels — unfolded here from the
    // payload the kit loaded with. The wire format is unchanged: the same flat
    // nodes-and-values the tool has always been sent, folded into the shape the
    // stores below consume. This reads the structure back out of it, which the
    // panel derives a transcript from and holds against the live one.
    set_graph(graph_from_payload(ldc.obj2), 'payload');
    ldc.graph = graph_state; // reachable from the console, like ldc.segmap
    let graph_open = $state(false);
    let graph_error = $state(null);
    let graph_loading = $state(false);
    // Rebuild reads the rows back out of graph_nodes / graph_arcs /
    // graph_labels instead: the snapshot pathway, checked against the same
    // transcript.
    function build_graph(){
        graph_loading = true;
        graph_error = null;
        return postp('/kits/graph', { uid: kit_id })
        .then( (x) => {
            if(x) set_graph(x, 'snapshot');
            else  graph_error = 'no response';
        } )
        .finally( () => graph_loading = false );
    }
    function show_graph(){
        graph_open = true;
    }
    function hide_graph(){
        graph_open = false;
    }
    // The kit's own source path, exactly as the kit records it — e.g. the
    // `.json` wrapper. Distinct from activeo.docid / the source_uid prop, which
    // are the *audio* the source resolves to (the wrapper's `wav`).
    const kit_source_uid = ldc.obj2.source?.uid;

    const services = ldc.services_init();

    if(!source_uid_channels) source_uid_channels = [ source_uid ];
    // let perm = [];
    // for(let i = 0; i < source_uid_channels.length; i++) perm[i] = source_uid_channels[i];
    let docid = source_uid;
    let docids = source_uid_channels.map(x => x); //$state([ docid ]);
    // let wave_docid = $state(docid);
    let header;
    let header_size;
    let duration = $state();
    let sample_rate;
    let block_size;
    let play_head = $state(0);
    let split_line_margin = 0.1;

    // The variables two and stereo don't mean exactly the same thing.
    // The more general meaning of two channels is two == true, but
    // it's possible for two channels to be in two separate files,
    // which would be stereo == false.  The typical case of a single stereo
    // file would be two == true and stereo == true.
    // Most of the time, knowing whether there's one or two channels is sufficient,
    // but sometimes you need to know whether there's a real stereo file present.

    let stereo; // true when audio file has more than one channel
    // let two = false;
    let nchannels = $state(0);

    // // define the viewable portion of the waveform
    let wave_display_offset = $derived(activeo.wave_display_offset);
    let wave_display_length = $derived(activeo.wave_display_length);
    // // define the selected portion of the waveform
    let wave_selection_offset = $derived(activeo.wave_selection_offset);
    let wave_selection_length = $derived(activeo.wave_selection_length);
    let wave_selection_end = $derived(round_to_3_places(activeo.wave_selection_offset + activeo.wave_selection_length));
    let wave_selection_src = $derived({
        beg: activeo.wave_selection_offset,
        end: activeo.wave_selection_offset + activeo.wave_selection_length
    });

    let srcso;
    let wave_canvas_height = 125;
    // wave_canvas_height = source_uid.match(/sw02001/) ? 50 : 125;

    let lastk;

    let spectrogram;
    let spectrogram_open;

    let muted = $state(false);

    onMount( () => {
        // width = div.offsetWidth;
        // times.update( (x) => {
        //     return {
        //         wave_display_offset: x.wave_display_offset,
        //         wave_display_length: x.wave_display_length
        //     }
        // } );
        if(constraint_add_asr_segments && ldc.nodes.size == 0){
            let type = constraint_asr_korean ? 'asr5' : 'asr4';
            if(window.ldc.vars.task_id == 169) type = 'asr4';
            // xasr(type, active_channeln == 1, docid, docids, stereo, ldc).then(xasrr);
        }
        request_animation_frame_loop_init();
        ldc.vars.loop.set('play_callback', play_callback);
        ldc.vars.loop.set('waveform_callback', () => callf(waveform_play_callback));
        set_urlsf();
    } );

    // function activate(i){
    //     alert('here')
    //     if(channelsc && channelsc.activate(i)){
    //         // wave_docid = docids[i];
    //         let s = source_uid_channels.length > 1 ? source_uid_channels[i] : source_uid_channels[0];
    //         set_audio_id_to_channel(source_uid_channels[i], i);
    //     }
    // }

    function activate_docid(x){
        // alert(x)
        if(x && x != docids[activeo.channel]){
            // activeo.docid = x;
            // active_docid.update( () => docid );
            // active_channel.update( () => docid2channel(x, docids) );
            const i = docid2channel(x, docids);
            // activeo.channel = i;
            channelsc.activate(i);
              // activate3();
        }
    }

    let last_playing = false;
    function waveform_play_callback(node, playing){
        if(!node) return;
        play_head = node.play_head;
        // for( const [ k, v ] of playheads) v();
        channelsc.draw_play_heads();
        if(playing){
            if(play_head < wave_display_offset || play_head > wave_display_offset + wave_display_length) {
                channelsc.set_times_then_draw(play_head, wave_display_length);
            }
            // selector = "#node-#{node.meta.id}-waveform-#{w.active_channel}"
            // selector += ' .waveform-svg'
            // console.log "NAN #{play_head} #{wave_display_offset}" if @debug
            muted = node.muted;
        }
        else{
            if(last_playing) event.dispatch(null,'playback_ended');
        }
        last_playing = playing;
    }

    ldc.waveform_play_callback = waveform_play_callback;



    // export function upload_transcript(){
    //     show('upload_transcript');
    // }
    function asr(){
        activate_sr()
    }
    let show_asr = false;
    const permission_to_download = constraint_export_transcript || permissions.project_manager ||
        (constraint_export_transcript_to_task_admin && permissions.task_admin);
    // setTimeout(
    //     () => {
    //         const e = {
    //             detail: {
    //                 userf: 'play_current_span_and_add_transcript_line_and_activate',
    //                 e: null
    //             }
    //         }
    //         userf(e);
    //         // set_active_transcript_line_to_last_created();
    //     }, 3000
    // );
    function userf(f, e){
        if(text_only && text_only_forbidden.has(f)) return;
        const o = { userf: f, e: e };
        // const h = { help_screen: help_screen, input_screen: input_screen };
        if(f == 'delete_all_confirm'){
            // show('delete_all');
        }
        else if(f == 'settings'){
            settings.update( (x) => { 
                x.open = true;
                return x;
            } );
        }
        else if(f == 'spectrogram'){
            dialog_spectrogram.showModal();
            // ch1.spectrogramf();
            // ch2.spectrogramf();
            // spectrogram_settings.update( (x) => {
            //     x.spectrogram_open = !x.spectrogram_open;
            //     return x;
            // });
        }
        // else if(f == 'header'){
        //   header = true;
        //   tick().then( () => header_input.focus() );
        // }
        else if(f == 'command'){
            command(f);
        }
        else if(f == 'show_help_screen_main'){
            // show('main');
        }
        else if(f == 'focus_input'){
            refocus();
            // Tab pressed on the keyboard icon → focus goes back to the
            // text window. Matched with the reverse (focus_to_keyboard)
            // in segments.svelte.
            mark_transcription('focus_to_text');
        }
        else if(f == 'play_current_span_or_play_stop'){
            play_current_span_or_play_stop();
        }
        else if(f == 'play_from_selection_beg_or_play_stop'){
            play_from_selection_beg_or_play_stop();
        }
        // else if(f == 'add_transcript_line_based_on_play_head'){
        //     add_transcript_line_based_on_play_head();
        // }
        // else if(f == 'open_spectrogram'){
        //     // w.spectrogram_flag = !w.spectrogram_flag;
        //     // if (w.spectrogram_flag) {
        //     //     $('.spectrogram-canvas').show();
        //     //     w.draw_spectrogram();
        //     // } else {
        //     //     $('.spectrogram-canvas').hide();
        //     // }
        // }
        // // keep center point the same, but toggle between step size of .5s and .2s
        else if(f == 'toggle_zoom'){
            channelsc.toggle_zoom();
        }
        else if(f == 'zoom_in'){
            channelsc.zoom_in();
            mark_transcription('zoomed_in');
        }
        else if(f == 'zoom_out'){
            channelsc.zoom_out();
            mark_transcription('zoomed_out');
        }
        // else if(f == 'play_head_menu'){
        //     console.log('in the segments component');
        // }
        // // else if(f == 'refresh_waveform'){
        // //     $('.Waveform').each(function(i, x) {
        // //         $(x).data().waveform.update_waveform = true;
        // //     });
        // // }
        // else if(f == 'not_sure'){
        //     console.log('not sure');
        // }
        else if(f == 'play_current_span'){
            play_current_span();
        }
        // else if(f == 'open_mode_menu'){
        //     open_mode_menu();
        // }
        else if(f == 'set_mode_to_window'){
            set_mode('window');
            mark_transcription('mode_to_window');
        }
        else if(f == 'set_mode_to_selection'){
            set_mode('selection');
            mark_transcription('mode_to_selection');
        }
        else if(f == 'move_cursor_lstep1'){
            move_cursor_lstep1();
            mark_transcription('cursor_moved');
        }
        else if(f == 'move_cursor_lstep2'){
            move_cursor_lstep2();
            mark_transcription('cursor_moved');
        }
        else if(f == 'move_cursor_lstep3'){
            move_cursor_lstep3();
            mark_transcription('cursor_moved');
        }
        else if(f == 'move_cursor_lstep4'){
            move_cursor_lstep4();
            mark_transcription('cursor_moved');
        }
        else if(f == 'move_cursor_rstep1'){
            move_cursor_rstep1();
            mark_transcription('cursor_moved');
        }
        else if(f == 'move_cursor_rstep2'){
            move_cursor_rstep2();
            mark_transcription('cursor_moved');
        }
        else if(f == 'move_cursor_rstep3'){
            move_cursor_rstep3();
            mark_transcription('cursor_moved');
        }
        else if(f == 'move_cursor_rstep4'){
            move_cursor_rstep4();
            mark_transcription('cursor_moved');
        }
        else if(f == 'split_segment_at_cursor'){
            split_segment_at_cursor(channelsc.cursor_time(), split_line_margin, update_segments);
            mark_transcription('segment_split');
        }
        else if(f == 'merge_with_following_segment'){
            merge_with_following_segment(segmentsc.find_active_id(), wmap, update_segments);
            mark_transcription('segment_merged');
        }
        else if(f == 'set_active_transcript_line_to_prev'){
            const ids = segmentsc.set_active_transcript_line_to_prev();
            set_active_transcript_line_helper(ids.id);
            mark_transcription('segment_navigated');
        }
        else if(f == 'set_active_transcript_line_to_next'){
            const ids = segmentsc.set_active_transcript_line_to_next();
            set_active_transcript_line_helper(ids.id);
            mark_transcription('segment_navigated');
        }
        else if(f == 'upload_transcript'){
            upload_transcript();
        }
        else if(f == 'set_mode_to_cursor'){
            set_mode('cursor');
            mark_transcription('mode_to_cursor');
        }
        else if(f == 'move_window_lstep1'){
            move_window_lstep1();
            mark_transcription('window_moved');
        }
        else if(f == 'move_window_lstep2'){
            move_window_lstep2();
            mark_transcription('window_moved');
        }
        else if(f == 'move_window_lstep3'){
            move_window_lstep3();
            mark_transcription('window_moved');
        }
        else if(f == 'move_window_lstep4'){
            move_window_lstep4();
            mark_transcription('window_moved');
        }
        else if(f == 'move_window_rstep1'){
            move_window_rstep1();
            mark_transcription('window_moved');
        }
        else if(f == 'move_window_rstep2'){
            move_window_rstep2();
            mark_transcription('window_moved');
        }
        else if(f == 'move_window_rstep3'){
            move_window_rstep3();
            mark_transcription('window_moved');
        }
        else if(f == 'move_window_rstep4'){
            move_window_rstep4();
            mark_transcription('window_moved');
        }
        else if(f == 'move_beg_left'){
            move_beg_left();
            mark_transcription('selection_edge_moved');
        }
        else if(f == 'move_beg_right'){
            move_beg_right();
            mark_transcription('selection_edge_moved');
        }
        else if(f == 'move_end_left'){
            move_end_left();
            mark_transcription('selection_edge_moved');
        }
        else if(f == 'move_end_right'){
            move_end_right();
            mark_transcription('selection_edge_moved');
        }
        else if(f == 'play_current_span_and_add_transcript_line_and_activate'){
            play_current_span_and_add_transcript_line_and_activate();
        }
        // else if(f == 'info'){
        //     console.log(waveform.datainfo);
        // }
        else if(f == 'set_active_transcript_line_to_next_and_play_current_span'){
            segmentsc.set_active_transcript_line_to_next_and_play_current_span();
            // User hit Enter inside a transcript textarea — the current
            // line is now committed. The transcription guide's
            // "Transcribe the segment" step listens for this.
            mark_transcription('transcript_committed');
        }
        else{
            // if(waveform[f]) console.log(f)
            // if(waveform[f]) waveform[f](o.e);
            toast.error(`no function ${f}`);
        }
    }

    function get_audio_buffer_info_multi(wav, ldc){
        if(source_uid_channels.length > 1){
            // should check for compatible header properties
            // let wavs = source_uid_channels || [ wav ];
            // const infos = 
            return get_audio_buffer_info(wav, ldc)
            .then(audiof)
            .then( () => set_audio_element_with_array(source_uid_channels, set_urls) );
            // can't allow stereo here
            // .then( () => check_stereo() );
        }
        else{
            return get_audio_buffer_info(wav, ldc)
            .then(audiof)
            .then( () => set_audio_element_multichannel(source_uid, nchannels, set_urls) )
            .then(() => {
                // function check_stereo(){
                //   if(nchannels > 1){
                    // clearInterval(interval);
                    if(stereo){
                        const k = source_uid;
                        docid = k + ':A';
                        docids[0] = docid
                        docids[1] = k + ':B';
                        if(nchannels > 2) docids[2] = k + ':C';
                        if(nchannels > 3) docids[3] = k + ':D';
                        // wave_docid = docid;
                    }
                //   }
                return stereo;
                // }
            });
        }
    }

    function audiof(data){
        header = data.header;
        header_size = data.info.dataOffset;
        stereo = data.info.channels > 1;
        nchannels = data.info.channels;
        duration = data.info.duration;
        sample_rate = data.info.sample_rate;
        block_size = data.info.blockSize;
    }


    let open_deletem = false;
    let audiofp = $state();
    // On once the imported spans are in place: only text may change from then
    // on. Passed to the segment list so the affordances go with it.
    let text_only = $state(false);
    // Why the imported mode couldn't start, shown under the waveform. An
    // annotator meeting a kit with no imported transcript should be told.
    let imported_error = $state(null);
    // Auto-import feature flags. import_transcript_auto shows the Upload Transcript
    // dialog and lets the user pick a choice; the others skip the dialog and apply
    // one choice directly, as if the user had clicked that button.
    const constraint_import_transcript_readonly = ldc.get_constraint('import_transcript_readonly');
    const constraint_import_transcript_blanks   = ldc.get_constraint('import_transcript_blanks');
    const constraint_import_transcript_save     = ldc.get_constraint('import_transcript_save');
    // Transcribe against an imported graph: its spans become both the captions
    // and — for a kit with nothing in it yet — the segments themselves, and
    // from then on only their text can change. Deliberately its own path
    // rather than a variation on the blanks import: that one reads the kit's
    // own source transcript and leaves everything editable, and it stays as
    // it is.
    const constraint_transcribe_text_only = ldc.get_constraint('transcribe_text_only');
    // Comments: a remark about a stretch of audio, kept out of the transcript.
    // Its own permission, so a kit locked to typing can still carry them.
    const constraint_comments = ldc.get_constraint('comments');
    // When on, the window auto-scrolls/zooms to follow the active transcript line
    // (see the $effect near center_window_on_segments). Toggleable in the Controls
    // toolbar; defaults on when import_transcript_blanks is set, so that mode
    // starts with follow enabled at page load.
    let follow_active_segment = $state(!!constraint_import_transcript_blanks || !!constraint_transcribe_text_only);
    function set_urlsf(){
    set_urls_source(source_uid, ldc).then(function(o){
        // const docid = o.wav.replace(/.*\//,'').replace(/\.(wav|flac)[:ABCD]?/,'');
        console.log('[import] flags', {
            auto: !!constraint_import_transcript_auto,
            readonly: !!constraint_import_transcript_readonly,
            blanks: !!constraint_import_transcript_blanks,
            save: !!constraint_import_transcript_save,
            nodes: ldc.nodes.size
        });
        // Blanks reference captions are rebuilt from the source transcript on
        // every load (the persisted blank segments reload, but reference_text is
        // in-memory), so they survive a refresh — not only when first imported.
        if(constraint_import_transcript_blanks) load_blanks_reference();
        // Reads its own source (the imported graph) rather than the kit's
        // transcript file, and seeds the segments itself, so it takes neither
        // branch below.
        if(constraint_transcribe_text_only) load_imported_transcript();
        else if(ldc.nodes.size == 0){
            // A specific choice wins over the generic auto/dialog flag, so setting
            // e.g. import_transcript_blanks works even if import_transcript_auto is
            // also present.
            if(constraint_import_transcript_readonly)   controls.auto_import('readonly');
            else if(constraint_import_transcript_blanks) controls.auto_import('blanks');
            else if(constraint_import_transcript_save)   controls.auto_import('save');
            else if(constraint_import_transcript_auto)   controls.create_transcript_retrieve2();
        }
        for(let i = 0; i < source_uid_channels.length; i++){
            let docid = source_uid_channels[i].replace(/.*\//,'').replace(/\.(wav|flac)[:ABCD]?/,'');
            if(redactions.has(docid)) continue;
            else                      redactions.set(docid, false);
        // postp('/redactions', { wav: docid }).then((x) => {
        //     const b = x.ok != 0;
        //     redactions.set(docid, b);
        //     if(b){
        //         postp('/redactions', { wav: docid, get: true }).then((x) => {
        //             redactions.set(docid, x.ok.sort((a,b) => a.beg - b.end));
        //         });
        //     }
        // });
        }
        audiofp = get_audio_buffer_info_multi(o.wav, ldc);
        return audiofp;
    })
    .then( () => {
        nchannels = docids.length;
        if(nchannels > 1){
            // two = true;
            // force update to underlines
            times.update( (x) => x );
        }
        // activate(0);
    } )
    .then( () => channelsc.set_times_then_draw(0, 10) );
    }
    let channelsc = $state();
    let segmentsc = $state();
    // const un1 = active_channel.subscribe( (x) => activate(x) );
    // const un2 = srcs.subscribe( (x) => srcs_update(x) );
    const un3 = times.subscribe( (x) => {
        // wave_display_offset = x.wave_display_offset;
        // wave_display_length = x.wave_display_length;
        // if(width != x.width && wave_display_length){
        //     width = x.width;
        // }
        // draw_ticks();
        // let ew = width / duration;
        // scrollbar_x = wave_display_offset * ew;
        // scrollbar_width = wave_display_length * ew;
        // event.dispatch(this, 'drew_scroll_cursor');
        // if(wave_display_length){
        //     for(let i = 0; i < nchannels; i++) channels.draw_waveformi(i);
        // }
        // srcs_update(srcso);
        // visible_redactions = find_redactions();

        // selection_beg_x = convert_seconds_to_pixels_by_offset(wave_selection_offset);
        // selection_end_x = convert_seconds_to_pixels_by_offset(wave_selection_end);

    } );
    // const un4 = selection.subscribe( (x) => {
    //     wave_selection_offset = x.wave_selection_offset;
    //     wave_selection_length = x.wave_selection_length;
    //     wave_selection_end = x.wave_selection_end;
    //     wave_selection_src = {
    //         beg: wave_selection_offset,
    //         end: wave_selection_offset + wave_selection_length
    //     };
    //     // selection_beg_x = convert_seconds_to_pixels_by_offset(wave_selection_offset);
    //     // selection_end_x = convert_seconds_to_pixels_by_offset(wave_selection_end);
    //     // let selection_widthx = selection_end_x - selection_beg_x;
    //     // let ww = convert_seconds_to_pixels(wave_selection_length);
    //     // if (selection_widthx!=ww && ww!=0) event.dispatch(selection_rect, 'drew_selection');
    //     // selection_width = ww;
    // } );
    // const un5 = mouse.subscribe( (x) => {
    //     draw_cursor();
    //     set_selection_from_mouse();
    // } );
    onDestroy( () => {
        // un1();
        // un2();
        un3();
        // un4();
        unsubscribe_settings();
        // unsubscribe_segments();
    } );




    // settings.subscribe( (x) => {
    //     if(x.key != 'settings') return;
    //     console.log('settings')
    //     console.log(x);
    //     // if(x.wave_canvas_height) wave_canvas_height = x.wave_canvas_height;
    //     // tick().then( () => spectrogram.draw_buffer(cache[lastk]) );
    //     spectrogram_open = x.spectrogram_open;
    //     if(spectrogram_open) tick().then( () => spectrogram.draw_buffer(scache[lastk]) );
    // })
    function create_audio_hash_from_docid(docid){
        return {
            id: docid,
            btime: round_to_3_places(activeo.wave_display_offset),
            etime: round_to_3_places(activeo.wave_display_offset + activeo.wave_display_length),
            header: header,
            header_size: header_size,
            sample_rate: sample_rate,
            block_size: block_size
        };
    }
    function create_audiok_from_docid(docid){
        const audiok = {
            id: docid,
            btime: round_to_3_places(activeo.wave_display_offset),
            etime: round_to_3_places(activeo.wave_display_offset + activeo.wave_display_length)
        };
        return JSON.stringify(audiok);
    }



    export function get_mode(){ return channelsc && channelsc.get_mode(); }
    export function set_mode(x){ return channelsc.set_mode(x); }
    // Open the Upload Transcript dialog and load ldc.maino.transcript. set_urlsf
    // does this automatically when import_transcript_auto is set and the kit is
    // empty; this export lets automated tests trigger it deterministically.
    export function trigger_import_transcript(){ if(controls) controls.create_transcript_retrieve2(); }
    //     if (x === mode) {
    //         return;
    //     }
    //     if(mode === 'beg' || mode === 'end'){
    //         mouseup_x = mousemove_x;
    //         set_mousedown_false();
    //     }
    //     mode = x;
    //     // ldc.$('.mode').text(x);
    //     if (x === 'beg' || x === 'end') {
    //         if (wave_selection_offset === null) {
    //             set_current_selection(convert_pixels_to_seconds(mousemove_x), 0);
    //         }
    //         switch (x) {
    //             case 'beg':
    //                 return set_mode_beg_end(convert_seconds_to_pixels(wave_selection_offset - wave_display_offset));
    //             case 'end':
    //                 return set_mode_beg_end(convert_seconds_to_pixels(wave_selection_end - wave_display_offset));
    //         }
    //     }
    // }
  

    let wave_active_transcript_line = $state(false);
    // current selection == internal selection times
    // normally there's no difference between the visible selection and the "current" selection
    // when the mouse is down, there is a distinction, and this function syncs them back up,
    // changing the current selection to match the visible selection.
    // optionally modifies a transcript line as well to match this "current" selection (if there's an active line)
    // sets wave_selection_offset wave_length and wave_selection_end, and adjusts transcript line timestamps
    // function wave_update(span_offset, span_length) {
    //     span_offset = round_to_3_places(span_offset);
    //     span_length = round_to_3_places(span_length);
    //     if (debug) { //@debug
    //         console.log('update');
    //         console.log(span_offset);
    //         console.log(span_length);
    //         console.log(wave_selection_offset);
    //         console.log(wave_selection_length);
    //     }
    //     const span_end = round_to_3_places(span_offset + span_length);
    //     if (debug) {
    //         if (wave_active_transcript_line) {
    //             console.log("active line before is " + wave_active_transcript_line.replace('node-', ''));
    //         } else {
    //             console.log("no active line");
    //         }
    //     }
    //     // this section handles updating a transcript line
    //     if (wave_selection_offset !== span_offset && wave_selection_end !== span_end) {
    //         console.log('setting to null');
    //         set_active_transcript_line_helper(null);
    //         if(ldc.active_channel()){
    //             set_active_transcript_line(null);
    //         }
    //     }
    //     if ((wave_selection_offset !== span_offset || wave_selection_length !== span_length) && wave_active_transcript_line) {
    //         let n = wmap.get(wave_active_transcript_line);
    //         console.log(n);
    //         if(xlass_def_id == 2){
    //             if(wave_selection_offset !== span_offset) update_node(wave_docid, n, span_offset, 'beg');
    //             if(wave_selection_end !== span_end)       update_node(wave_docid, n, span_end,    'end');
    //         }
    //         else{
    //             update_wave(wave_docid, n, span_offset, span_end, update_segments);
    //         }
    //     }
    //     // end section
    //     set_current_selection(span_offset, span_length);
    //     if (debug) {
    //         if (wave_active_transcript_line) {
    //             return console.log("active line before is " + wave_active_transcript_line.replace('node-', ''));
    //         } else {
    //             return console.log('no active line');
    //         }
    //     }
    // }

    export function set_current_selection(o, l) {
        console.log(`set current to ${o} ${l}`)
        if (o < 0 || l < 0) return;
        // A segment can run a little past the end of the audio — imported
        // times rarely match the file to the millisecond, and the last
        // segment is where the discrepancy lands. Clamp it to what there is
        // to play.
        //
        // This used to refuse the whole selection, which left the *previous*
        // one in place: selecting the last segment played whichever segment
        // was played before it, with nothing said.
        if (duration > 0) {
            if (o >= duration) {
                console.warn(`selection starts at ${o}s, past the end of ${duration}s of audio`);
                return;
            }
            if (o + l > duration) l = round_to_3_places(duration - o);
        }
        // selection.update( (x) => {
        //     return {
                activeo.wave_selection_offset = o;
                activeo.wave_selection_length = l;
                activeo.wave_selection_end = round_to_3_places(o + l);
        //     };
        // } );
        // return w.update_cursor = true;
        // mouse.update( (x) => x );
    }

    export function show_src(src, beg){
        if (debug === true) {
            console.log(`BEGIN ${beg}`);
            console.log(src);
        }
        //this.set_active_transcript_line this
        set_current_selection_by_src(src);
        // w.update_waveform_canvas false if web_audio
        if (beg === true) {
            if (src.beg > wave_display_offset && ((wave_display_offset + wave_display_length) > src.beg)) {
                return console.log('within');
            } else {
                // this.update_waveform_canvas true # can the arg be false?
                console.log('without');
                console.log(`beg ${src.beg}`);
                return channelsc.center_display_at_time(src.beg);
            }
        } else {
            if (src.end > wave_display_offset && ((wave_display_offset + wave_display_length) > src.end)) {
                return console.log('within');
            } else {
                // this.update_waveform_canvas true # can the arg be false?
                console.log('without');
                console.log(`beg ${src.end}`);
                return channelsc.center_display_at_time(src.end);
            }
        }
    }

    function set_active_transcript_line_helper(id){
        if (debug) { //@debug is true
            console.log("NODE");
            console.log(id);
        }
        if (!id) {
            id = null;
        }
        let same;
        if (id && wave_active_transcript_line === id) {
            same = true;
        } else {
            same = false;
        }
        wave_active_transcript_line = id;
        if (id) {
            const node_id = wmap.get(id);
            if(debug){
                console.log("active line is " + id + ':' + node_id);
                console.log(wmap);
            }
            if (same === false) {
                const srcc = index2.get(id.split('-')[1]);
                activate_docid(srcc.docid);
                const src = {
                    beg: srcc.beg,
                    end: srcc.end
                };
                show_src(src, true);
                if(false){// (this.debug === true) {
                    console.log('showing source');
                    console.log(src);
                }
                ldc.crnt = node_id.split('-')[1];
            }
        } else {
            if(debug) console.log("no active line");
            ldc.crnt = null;
        }
    }


    function play_current_span_and_add_transcript_line_and_activate(){
        // w.set_active_transcript_line_helper(id);
        const f = () => segmentsc.set_active_transcript_line_to_last_created();
        play_current_span_and_add_transcript_line(f);
        // Notify the transcription guide that a segment was just created
        // (only when there was actually a selection — otherwise
        // play_current_span alerts instead of adding anything).
        if (wave_selection_length > 0) mark_transcription('segment_created');
    }

    function play_current_span_and_add_transcript_line(f) {
        play_current_span();
        const aa = '.SegmentList';
        const bb = 'new.Segment';
        check_for_submit( add_transcript_line_based_on_selection_without_submit(aa, bb), () => { update_segments(); f(); } );
    }

    function set_current_selection_by_src(src){
        set_current_selection(src.beg, round_to_3_places(src.end - src.beg));
    }

    function underline(x){
        // The underline belongs to the segment the given node hangs off: for an
        // Arc that's its list item, which is one iid back.
        const id = segmap.get(parseInt(x.node_id) - 1)?.id;
        set_active_transcript_line_helper(id);
        // if(ldc.active_channel()){
            segmentsc.set_active_transcript_line(id);
        // }
        play_current_span();
    }

    // ldc.active_channel = () => document.querySelectorAll('.ChannelA.active_channel').length == 1;



    // const vars = ldc.vars;
    // const aa = `.${vars.add_from_waveform_list}`;
    // const bb = `new.${vars.add_from_waveform_audio}`;

    // function add_transcript_line_based_on_selection(){
    //     check_for_submit( () => add_transcript_line_based_on_selection_without_submit(aa, bb), null );
    // }

    // function add_transcript_line_based_on_play_head(){
    //     check_for_submit( () => add_transcript_line_based_on_play_head_without_submit(aa, bb), null );
    // }
    function add_transcript_line_based_on_selection_without_submit(list_selector, audio_path){
        const span = {
            offset: wave_selection_offset,
            length: wave_selection_length
        };
        if(redact_task) span.transcript = 'REDACTED';
        return add_audio_to_list(docids[activeo.channel], list_selector, audio_path, span);
    }
    
    function play_src_with_audio_for_waveform(src, f){
        const x = source_uid_channels.length > 1 ? docids[activeo.channel] : source_uid;
        console.log('AUDIO')
        console.log(source_uid);
        console.log(docids[activeo.channel])
        console.log(src);
        console.log(x)
        // console.log(perm)
        console.log(source_uid_channels)
        play_src_with_audio_id(x, docids[activeo.channel], src, f);
    }

    let play_current_span_or_play_stop_last;
    export function play_current_span_or_play_stop(){
        if(wave_selection_length == 0){
            if(wave_selection_offset == play_current_span_or_play_stop_last)
                play_stop();
            else{
                play_from_selection_beg();
                play_current_span_or_play_stop_last = wave_selection_offset;
            }
        }
        else
            play_current_span();
    }

    function play_stop(){
        if(is_playing())
            stop_playing();
        else
            play_from_play_head();
    }

    function play_from_play_head(){
        const src = {
            beg: play_head,
            end: duration
        };
        play_src_with_audio_for_waveform(src, () => null);
    }

    export function play_current_span(){
        if(wave_selection_length == 0){
            alert('select a region first');
        }
        else{
            play_src_with_audio_for_waveform(wave_selection_src, () => null);
        }
    }

    export function center_and_play_current_span(){
        if(wave_selection_length == 0){
            alert('select a region first');
        }
        else{
            channelsc.center_display_at_time(wave_selection_offset + wave_selection_length / 2);
            play_src_with_audio_for_waveform(wave_selection_src, () => null);
        }
    }

    export function play_from_cursor(){
        play_head = convert_pixels_to_seconds(cursor_x) + wave_display_offset;
        play_from_play_head();
    }

    export function play_from_selection_beg(){
        if(wave_selection_offset){
            play_head = wave_selection_offset;
            play_from_play_head();
        }
    }

    export function play_from_selection_end(){
        if(wave_selection_offset){
            play_head = wave_selection_offset + wave_selection_length;
            play_from_play_head();
        }
    }





    export function move_cursor_lstep1(){ channelsc.move_cursor_lstep1(); }
    export function move_cursor_lstep2(){ channelsc.move_cursor_lstep2(); }
    export function move_cursor_lstep3(){ channelsc.move_cursor_lstep3(); }
    export function move_cursor_lstep4(){ channelsc.move_cursor_lstep4(); }
    export function move_cursor_rstep1(){ channelsc.move_cursor_rstep1(); }
    export function move_cursor_rstep2(){ channelsc.move_cursor_rstep2(); }
    export function move_cursor_rstep3(){ channelsc.move_cursor_rstep3(); }
    export function move_cursor_rstep4(){ channelsc.move_cursor_rstep4(); }
    export function move_beg_left()  { channelsc.move_beg_left(); }
    export function move_beg_right() { channelsc.move_beg_right(); }
    export function move_end_left()  { channelsc.move_end_left(); }
    export function move_end_right() { channelsc.move_end_right(); }
    export function move_window_lstep1(){ channelsc.move_window_lstep1(); }
    export function move_window_lstep2(){ channelsc.move_window_lstep2(); }
    export function move_window_lstep3(){ channelsc.move_window_lstep3(); }
    export function move_window_lstep4(){ channelsc.move_window_lstep4(); }
    export function move_window_rstep1(){ channelsc.move_window_rstep1(); }
    export function move_window_rstep2(){ channelsc.move_window_rstep2(); }
    export function move_window_rstep3(){ channelsc.move_window_rstep3(); }
    export function move_window_rstep4(){ channelsc.move_window_rstep4(); }

    let dialog_command = $state();
    let dialog_close_kit;
    let dialog_close_kit_audit = "";

    let dialog_delete_all = $state();
    let dialog_delete_all2 = $state();
    const delete_all_docids = { all: [] };
    function delete_all2_wrapper(){
        delete_all2(delete_all_docids.all, update_segments);
        dialog_delete_all2.close();
    }
    // Wrapped in $effect so dialog_delete_all2 is read after the dialog has
    // mounted and bound its ref — otherwise the state-reference warning fires
    // and (if open_deletem were ever true) showModal() would be called on
    // undefined.
    $effect(() => {
        if(!open_deletem) return;
        let found_two = false;
        document.querySelectorAll('.Segment').forEach( (x) => {
            let docid = ldc.$(x).data().value.docid;
            if(docid.match(/:/)){
                found_two = true;
                if(delete_all_docids[docid]){
                    delete_all_docids[docid].push(docid);
                }
                else{
                    delete_all_docids[docid] = [ docid ];
                }
                delete_all_docids.all.push(docid);
            }
            console.log(delete_all_docids)
        });
        if(found_two && !stereo) dialog_delete_all2.showModal();
    });
    let dialog_settings = $state();
    let dialog_settings_h = $state({});
    let current_modifier = $state('ctrl');
    // each one needs to be saved in save_settings in settings.js
    const dialog_settings_a = [
        [ 'open', 'q' ],
        [ 'sections_open', 'a' ],
        [ 'spectrogram_open', 'b' ],
        [ 'experimental', 'x' ]
    ];
    // Maps the 1/2/3/4 keys in the settings dialog to a modifier choice.
    const modifier_choices = ['ctrl', 'alt', 'meta'];
    function set_modifier(id){
        settings.update( (x) => { x.modifier = id; return x; } );
    }
    function dialog_settings_keydown(e){
        for( let y of dialog_settings_a ){
            let k = y[0];
            let v = y[1];
            if(e.key == v){
                settings.update( (x) => { x[k] = !x[k]; return x } );
            }
        }
        const idx = parseInt(e.key, 10) - 1;
        if(idx >= 0 && idx < modifier_choices.length){
            set_modifier(modifier_choices[idx]);
        }
        if(e.key == 'q') controls.keyboard_focus();
    }
    // let sections_open;
    const unsubscribe_settings = settings.subscribe( (x) => {
        experimental = x.experimental;
        if(dialog_settings){
            if(x.open) dialog_settings.showModal();
            else       dialog_settings.close();
        }
        // sections_open = x.sections_open;
        for( let y of dialog_settings_a ){
            let k = y[0];
            let v = y[1];
            dialog_settings_h[k] = x[k];
        }
        current_modifier = x.modifier || 'ctrl';
    });
    
    let dialog_spectrogram = $state();

    let command_line = $state();
    let command_line_enter = $state(false);
    function command(f){
        dialog.showModal();
    }
    // async function process_command_line(c, b){
    //     if(b){
    //         console.log(c);
    //         if(c == 'sad'){
    //             let x = await add_sad_send(source_uid, ldc);
    //             console.log(x);
    //         }
    //         if(c == 'asr'){
    //             let x = await add_asr_send(source_uid);
    //             console.log(x);
    //         }
    //         command_line_enter = false;
    //         return c;
    //     }
    //     return null;
    // }
    // $: command_line_output = process_command_line(command_line, command_line_enter);
    // $: console.log(`command line output: ${command_line_output}`);
    key.subscribe((e) => {
        if(!e) return;
        const mode = get_mode();
        // Try the current mode's bindings first so mode-specific keys (home
        // row, mode switches) win. Fall back to cursor mode so global
        // commands like i/o/z/space/p/q/h work in every mode.
        let x = fmap_helper(e, keymap[mode]);
        if(!x && mode !== 'cursor') x = fmap_helper(e, keymap.cursor);
        if(x) userf(x, e);
        // Signal to the transcription guide that the user pressed space
        // (used by the "Press space to play" / "Press space to stop" steps).
        if (e.key === ' ') mark_transcription('space_press');
    });

    function refocus(){
        segmentsc.refocus();
    }

    function insert_laugh(){
        const input = ttextarea;
        const { x, y, z } = three_way_split_on_selection(input);
        t_value = `${x}${y}{laugh}${z}`;

        setTimeout( () => {
            input.selectionStart = input.selectionEnd = x.length + y.length + 7;
        }, 100);
    }

    // Set by the toolbar toggle. With it on, the speaker command names the
    // segment "subject" and nothing opens — for a recording with one person of
    // interest, choosing the same name out of a menu every time is the whole
    // cost of labelling a speaker.
    let speaker_is_subject = $state(false);
    const SUBJECT = 'subject';

    function set_speaker(h){
        // A segment's speaker is part of the shape an imported transcript
        // fixed. Guarded here because this is where setting one starts,
        // whatever opened the picker.
        if(text_only_refuses('set a speaker')) return;
        const id = h.iid + 3; // the Speaker child of this segment
        // Straight to "subject", skipping the picker. Through set_speaker_value
        // so the message, the graph row and the list of names already used all
        // end up exactly as they would have.
        if(speaker_is_subject) return set_speaker_value(id, SUBJECT, h.nodes, update_segments);
        const kb = new Keyboard('speakers');
        kb.map = {};
        const short = kb.shortcuts();
        const speakerm = {};
        let spkrs = constraint_speakers;
        const speakers = [];
        const new_label = 'new speaker';
        const replace_label = 'replace speaker';
        if (spkrs) {
            if (spkrs[0] === 'new') {
                kb.set_speaker_helper_new_helper(new_label, speakers);
                spkrs = spkrs.slice(1, spkrs.length);
            }
            // Over the list itself, not over the alphabet: running to 26
            // regardless of how long the list was read off its end, and
            // `spkrs[i]` being undefined put a row named "undefined" on the
            // menu. The value is never read — fill_speakers goes by the keys.
            for(const s of spkrs) speakerm[s] = true;
        } else {
            kb.set_speaker_helper_new_helper(new_label, speakers);
            kb.set_speaker_helper_replace_helper(replace_label, speakers);
        }
        fill_speakerm(speakerm, short, speakersm);
        fill_speakers(speakerm, short, speakers, kb);
        help_screen.help_screen_open({
            title: 'Speakers',
            list: speakers,
            keyboard: kb,
            remove: true,
            reset: true,
            mini: true
        }).then( (x) => {
            if(x == 'getf'){ //get_new_speaker(id, h);
                const kb = new Keyboard('speaker');
                return input_screen.input_screen_open_helper({
                    keyboard: kb,
                    title: 'type speaker, hit enter'
                });
            }
            else{
                return x;
            }
        } ).then( (x) => {
            if(x == 'replacef') return x;
            else if(x)          return set_speaker_value(id, x, h.nodes, update_segments);
        } ).then( (x) => {
            if(x == 'replacef'){
                for(let x of [ 'n', 'r' ]){
                    delete kb.map[x];
                    delete kb.delegate[x];
                }
                return help_screen.help_screen_open({
                    title: `Replace ${h.speaker} with:`,
                    list: speakers.slice(2),
                    keyboard: kb,
                    remove: true,
                    reset: true,
                    mini: true
                });
            }
        } ).then( (x) => {
            if(x) set_speaker_value_replace(h.speaker, x, update_segments);
        } );
    }

    function set_speaker_value(id, value, nodes, f){
        penultimate_speaker_used = last_speaker_used;
        last_speaker_used = value;
        // if(rf) rf();
        segmentsc.redactcb(value == 'redacted');
        // No write here: `id` is this segment's Speaker node (h.iid + 3), and
        // change_value sends it a change, which changef applies to that node's
        // store. set_speaker_value_replace below has always worked this way.
        speakersm.set(value, value);
        change_value(id, value, f);
        return value;
    }

    function set_speaker_value_replace(x, value, f){
        penultimate_speaker_used = last_speaker_used;
        last_speaker_used = value;

        // Which rows carry the old label; the writing is change_values' job.
        // This used to call change_value per row, and change_value submits per
        // call — one round trip for every segment with that speaker.
        const iids = [];
        for(const [k, v] of segmap){
            // The row carries the iid of each label the graph gave it.
            if(v.speaker == x && v.label_iids?.Speaker) iids.push(v.label_iids.Speaker);
        }
        change_values(iids, value, f, 'Replacing speaker labels');
        return value;
    }

    function open_section(h){
        if(constraint_section_order_forced === true){
            section_order_forced_open(h);
        }
        else {
            open_section2(h);
        }
    }

    function section_order_forced_open(h){
        const obj = { length: secmap.size, a: -1, b: segmap[h.iid].beg };
        for(const [ k, v ] of secmap){
            if(v.end > obj.a) obj.a = v.end;
        }
        const length = obj.length;
        const a = obj.a;
        const b = obj.b;
        if(a > b){
            alert(`new section must follow last section, but ${a} > ${b}`);
            return;
        }
        const sections = ldc.get_constraint('sections');
        if(!sections){
            alert("sections aren't available");
            return;
        }
        if(length > sections.length){
            alert('no more sections');
            return;
        }
        const s = sections[length];
        add_section(s, h.iid, update_segments);
        sectionsm.set(s, s);
    }

    function open_section2(h){
        // let id;
        // if(ldc.nodes) id = h.iid + 3;
        // else                 id = window.gdata(`#node-${h.iid} .Speaker`).meta.id;
        const kb = new Keyboard('sections');
        kb.map = {};
        const short = kb.shortcuts();
        const speakerm = {};
        let spkrs = constraint_sections;
        const speakers = [];
        const new_label = 'new section';
        // const replace_label = 'replace section';
        if (spkrs) {
            if (spkrs[0] === 'new') {
                kb.set_speaker_helper_new_helper(new_label, speakers);
                spkrs = spkrs.slice(1, spkrs.length);
            }
            // Over the list itself, not over the alphabet: running to 26
            // regardless of how long the list was read off its end, and
            // `spkrs[i]` being undefined put a row named "undefined" on the
            // menu. The value is never read — fill_speakers goes by the keys.
            for(const s of spkrs) speakerm[s] = true;
        } else {
            kb.set_speaker_helper_new_helper(new_label, speakers);
            // kb.set_speaker_helper_replace_helper(replace_label, speakers);
        }
        fill_speakerm(speakerm, short, sectionsm);
        fill_speakers(speakerm, short, speakers, kb);
        help_screen.help_screen_open({
            title: 'Sections',
            list: speakers,
            keyboard: kb,
            remove: true,
            reset: true,
            mini: true
        }).then( (x) => {
            if(x == 'getf'){ //get_new_speaker(id, h);
                const kb = new Keyboard('section');
                return input_screen.input_screen_open_helper({
                    keyboard: kb,
                    title: 'type section, hit enter'
                });
            }
            else{
                return x;
            }
        } ).then( (x) => {
            if(x == 'replacef') return x; // won't happen
            else if(x)          return open_sectionf(h.iid, x);
        } ); //.then( (x) => {
        //     if(x == 'replacef'){
        //         for(let x of [ 'n', 'r' ]){
        //             delete kb.map[x];
        //             delete kb.delegate[x];
        //         }
        //         return help_screen_open({
        //             title: `Replace ${h.speaker} with:`,
        //             list: speakers.slice(2),
        //             keyboard: kb,
        //             remove: true,
        //             reset: true,
        //             mini: true
        //         });
        //     }
        // } ).then( (x) => {
        //     if(x) set_speaker_value_replace(h.speaker, x);
        // } );

            // getf: () => get_new_section(hh),
            // setf: (value) => open_sectionf(hh.iid, value),
    }

    function open_sectionf(id, section){
        const obj = {};
        for(const [ k, v ] of secmap){
            if(v.section == section) obj.exists = true;
        }
        if(obj.exists){
            alert(`section ${section} already exists`);
        }
        else if(obj.repeat){
            alert("sections can't overlap");
        }
        else{
            add_section(section, id, update_segments);
            sectionsm.set(section, section);
        }
    }

    function last_section_obj(id, current_section){
        const length = secmap.size;
        const h = {
            id: id,
            current_section: current_section,
            length: length,
            exists: false,
            repeat: false,
            overlap: false
        };
        if(length > 0){
            const nodeb = window.gdata(`#node-${id} .Segment`);
            if(current_section === null){
                h.src = null;
            }
            else{
                h.src = {
                    beg: nodeb.value.beg,
                    end: nodeb.value.end
                };
            }
            const last_section = find_last_section(h);
            if(ldc.$(last_section).find('.EndSeg.empty').length === 1){
                alert('last section is still open');
                return;
            }
            const seg = ldc.$(last_section).find('.EndSeg').data().value.value;
            const nodea = window.gdata(`#node-${seg} .Segment`);
            if(nodea) h.a = nodea.value.end;
            if(nodeb) h.b = nodeb.value.beg;
        }
        return h;
    }

    function find_last_section(h) {
        const src = h.src;
        let last = null;
        let last_section = null;
        document.querySelectorAll('.SectionListItem').forEach(function(x) {
            let iid = ldc.$(x).data().meta.id;
            if(Number(iid) > Number(last)){
                last = iid;
                last_section = x;
            }
            if(ldc.$(x).find('.Section').data().value.value === h.current_section){
                h.exists = true;
            }
            else{
                if(src && src.beg && src.end) {
                    let begseg = get_begendseg(x, '.BegSeg', h);
                    let endseg = get_begendseg(x, '.EndSeg', h);
                    if(begseg && endseg){
                        if(begseg <= src.end && endseg >= src.beg || h.repeat) h.overlap = true;
                    }
                }
            }
        });
        return last_section;
    }

    function get_begendseg(x, sel, h){
        let begseg = ldc.$(x).find(sel).data();
        if(begseg){
            begseg = begseg.value.value;
            if(begseg){
                if(begseg === h.id){
                    h.repeat = true;
                }
                else{
                    begseg = ldc.$(`#node-${begseg} .Segment`).data();
                    if(begseg){
                        // alert JSON.stringify begseg.value
                        if(sel === '.BegSeg') begseg = begseg.value.beg;
                        else                  begseg = begseg.value.end;
                    }
                }
            }
        }
        return begseg;
    }

    function close_section(h, f) {
        extend_section(h, f);
    }

    function section_order_forced_close(hh){
        const h = get_open_section(hh.iid);
        if(h && h.id) set_pointer(h.eseg.meta.id, h.id);
    }

    function extend_section(hh) {
        const h = get_last_section(hh.iid);
        console.log(h);
        if(!h.sec) return;
        const src = { beg: h.sec.begi, end: h.seg.endi };
        change_value_src(h.sec.iid+1, src)
    }

    function get_last_section(id){
        const h = { id: id };
        if(debug) console.log('SSSSSS')
        const seg = segmap.get(id);
        // const segend = segmap.get(id).end;
        // h.end = segend;
        // h.map = secmap;
        h.seg = seg;
        let found = null;
        for(const [k, v] of secmap){
            if(v.beg <= seg.end){
            if(v.end >= seg.beg){
                // alert('segment overlaps section');
                h.sec = v;
                return h;
            }
            if(found){
                if(v.end > found.end) found = v; // v is closer
            }
            else{
                found = v;
            }
            }
        }
        if(!found) alert('no previous section');
        else       h.sec = found;
        return h;
    }

    function close_section2(hh, f) {
        const h = get_open_section(hh.iid);
        if(h){
            if(h.same){
                if(h.id){
                    set_pointer(h.eseg.meta.id, h.id, f);
                }
            }
            else{
                h.overlap = false;
                h.src = {
                    beg: h.a.value.beg,
                    end: h.b.value.end
                };
                const last_section = find_last_section(h);
                if(h.overlap) alert("sections can't overlap");
                else if(h.id) set_pointer(h.eseg.meta.id, h.id, f);
            }
        }
    }

    function set_pointer(pointer, segment, f) {
        console.log('setting pointer ' + pointer)
        change_value(pointer, segment.toString(), f);
    }

    function get_open_section(id){
        const h = { id: id };
        const length = secmap.size;
        let last_section = null;
        const segs = [...secmap].map( ([ k, v ]) => v).filter( (x) => x.nodes.get('EndSeg').node_value_id == 0 );
        if (segs.length === 0) {
            alert('no open sections');
            return;
        }
        let iid;
        let seg;
        if(debug){
            console.log('SSSSSS')
            console.log(segs)
        }
        iid = segs[0].iid;
        const sss = ldc.nodes.get(iid);
        h.eseg = sss.nodes.get('EndSeg');
        h.eseg.meta = { id: h.eseg.iid };
        h.current_section = sss.nodes.get('Section').value.value;
        h.bseg = sss.nodes.get('BegSeg');
        h.bseg.meta = { id: h.bseg.iid };
        seg = parseInt(h.bseg.value.value);
        if(seg !== id){
            h.a = ldc.nodes.get(seg).nodes.get('Segment');
            h.a.value.beg = h.a.value.beg;
            h.b = ldc.nodes.get(id).nodes.get('Segment');
            // alert "#{a} #{b}"
            if(h.a.value.end > h.b.value.beg){
                h.id = null;
                alert(`closing segment must follow opening segment, but ${h.a.value.end} > ${h.b.value.beg}`);
                return;
            }
        }
        else{
            h.same = true;
        }
        return h;
    }

    function suserf(e, x){
        if(text_only && text_only_forbidden.has(e.detail.userf)) return;
        const o = { userf: e.detail.userf, e: e.detail.e };
        const h = { iid: x.iid };
        h.rf = () => redactcb();
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
        else if(e.detail.userf == 'split_segment_at_cursor')            split_segment_at_cursor(channelsc.cursor_time(), split_line_margin, update_segments);
        else if(e.detail.userf == 'merge_with_following_segment')            merge_with_following_segment(segmentsc.find_active_id(), wmap, update_segments);
        else if(e.detail.userf == 'play_current_span') play_current_span();
        else if(e.detail.userf == 'set_active_transcript_line_to_prev') userf(e.detail.userf, e);
        else if(e.detail.userf == 'set_active_transcript_line_to_next') userf(e.detail.userf, e);
        else if(e.detail.userf == 'set_active_transcript_line_to_next_and_play_current_span') userf(e.detail.userf, e);
        else if(e.detail.userf == 'play_current_span_and_add_transcript_line_and_activate') play_current_span_and_add_transcript_line_and_activate();
        else                                                       dispatch('userf', o);
    }
    function generic_next(x){
        // if(experimental) xasr2();
    }
    
    function show_sections(){
        settings.update( (x) => {
            x.sections_open = !x.sections_open;
            return x;
        } );
    }

    let service_promise;
    let output_promise = $state();
    function get1(text){
        const o = { type: 'validate_transcript', data: { text: text } };
        const set_sp = (x) => service_promise = x;
        const set_op = (x) => output_promise = x;
        output_promise = Promise.resolve({ errors: ['validating...'] });
        get_promises(set_sp, set_op, o);
    }
    let transcript_text = $state(); // the TSV built for download, not the transcript rows
    run(() => {
    if(transcript_text) get1(transcript_text);
  });
    let include_headers = false;
    let include_speaker = true;
    let include_section = true;
    let kit = kit_id;
    function validate_transcript(){
        if(output_promise){
            output_promise = null;
        }
        else{
            // Same check the download runs: don't send a transcript off to be
            // validated when it doesn't match the graph it was folded from.
            // The errors show under the waveform either way.
            try{
                transcript_text = create_transcript(kit, include_speaker, include_section, include_headers, segs, graph_state);
            }
            catch(e){
                output_promise = Promise.resolve({ result: 'error', errors: [ e.message ] });
                return;
            }
            transcript_text = transcript_text.replace(/\t\n/g, "\tx\n");
        }
    }
    function play_head_menu(h){
        // kb = this.keyboards.playback;
        // if (w.special) {
        //   kb.map.p = 'close';
        //   return kb.show_mini_screen(w, false);
        // } else {
          // delete kb.map.p;
          const hh = {
            // html: help_screen.playback,
            html: 'help_screen_playback_html',
            // remove: true,
            // reset: true,
            mini: true,
            map: playbackmap,
            delegate: {
                'play_from_cursor': play_from_cursor,
                'play_from_selection_beg': play_from_selection_beg,
                'play_from_selection_end': play_from_selection_end,
                'stop_playing': stop_playing,
                'center_and_play_current_span': center_and_play_current_span
            }
          };
          help_screen.help_screen_open(hh);
        // }
        // // if(segment.tokens.every( x => x.length == 1)){
        // //     segment.text = segment.tokens.map( x => x[0].content ).join(' ');
        // //     if(segment.punc) segment.text += segment.punc;
        // // }

        // segment.docid = mapf(segment.channel);
        // segment.offset = segment.beg;
        // segment.length = round_to_3_places(segment.end - segment.beg);
        // segment.transcript = segment.text;
        // vvsegs.push(segment);
        // return asro_i + 1;
        // return i;
    }
    let vsegs = [];
    let active_node_id;
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

            const ids = segmentsc.set_active_transcript_line_to_last_created();
            // const ids = set_active_transcript_line_to_next();
            set_active_transcript_line_helper(ids.id);
            // play_current_span();
            update_segments();
        };
        add_audio_to_listp(segment.docid, segment, f);
    }

    // A periodic consistency check against /kits/:id/check lived here. Its body
    // began with an unconditional `return;` and its inner branch tested
    // ldc.obj.xlass_def, a key the payload has never had — it hadn't run in
    // years. The graph panel's Rebuild does this job now, on demand.

    const speakersm = ldc.speakers;
    let last_speaker_used;
    let penultimate_speaker_used;
    const sectionsm = ldc.sections;
    export function update_segments_with(){
        update_segments();
        new_update_segments();
    }

    function update_segments(){
        if(ldc.node_lists) return;
        const o = segment_list_f('segments');
        transcript.segments = o.segments;
        transcript.undefined_segments = o.undefined_segments;
        transcript.sections = o.sections;
    }

    function update_segments2(json){
        json.map( (x) => x.readonly = true );
        // Keep the imported read-only segments in vsegs (alongside virtual/ASR
        // ones) so they survive rebuilds. sort_segments() merges segmap (the
        // persisted nodes) with vsegs; setting the segments store directly would
        // drop them the next time a real segment is added and sort_segments runs.
        for(const x of json) if(!vsegs.includes(x)) vsegs.push(x);
        sort_segments();
    }

    // Blanks import: add an empty editable segment at each reference segment's
    // times, and stash the reference text keyed by those timestamps so the
    // segment list can show it *above* the matching blank segment. This replaces
    // the old behaviour of injecting separate read-only reference rows — the
    // annotator now sees "what was supposed to be said" as a caption over the
    // empty segment they type into, rather than as its own line.
    function update_segments2_with_blanks(json){
        set_reference_text_for(json);
        add_blank_segments_for(json);
    }

    // Populate the blanks reference captions (text shown above each overlapping
    // segment) from a parsed transcript, WITHOUT adding any segments. Stored with
    // each reference's own time span; the segment list matches by overlap. Called
    // both on import and on every page load (see load_blanks_reference) so the
    // captions survive a refresh.
    function set_reference_text_for(segs){
        clear_reference_text();
        for(const s of segs) set_reference_text(s.beg, s.end, s.text);
    }

    // Rebuild the blanks reference captions from the source transcript on every
    // page load. The blank segments themselves are persisted and reload
    // normally, but reference_text is in-memory only and the import path only
    // runs for a fresh (empty) kit — so without this the captions vanish on
    // refresh. Mirrors auto_import: only the tsv transcript is wired.
    function load_blanks_reference(){
        const o = ldc.maino;
        if(!(o && o.transcript)){ setTimeout(load_blanks_reference, 500); return; }
        o.transcript.then( (x) => {
            if(!x || x.use_transcript != 'tsv') return;
            const json = parse_tsv0(x.found_transcript);
            if(json) set_reference_text_for(json);
        } );
    }

    // Transcribe-text-only mode: fetch the imported graph matched to this
    // kit's audio and set the tool up against it.
    //
    // The spans do two jobs. They're the captions above each segment, as in
    // the blanks import. And on a kit with nothing in it yet they're the
    // segments too — created once, at the imported times, empty. After that
    // the shape is fixed: lock() closes off everything except typing.
    //
    // A kit that already has segments is one the annotator has come back to,
    // so nothing is created; the captions are rebuilt and the lock goes on.
    function load_imported_transcript(){
        postp('/kits/imported', { uid: kit_id }).then( (x) => {
            if(!x || x.error || !(x.rows && x.rows.length)){
                // Nothing imported for this audio. Say so rather than
                // silently behaving like an ordinary kit — the annotator
                // would otherwise be given an empty waveform and no reason.
                console.error('[imported]', (x && x.error) || 'no rows');
                imported_error = (x && x.error) || 'no imported transcript for this kit';
                return;
            }
            // "Empty" means no segments, not no nodes. Deleting a segment
            // leaves its anchors behind — they're what its times pointed at —
            // so a kit that once held one still has nodes in it. Counting
            // nodes would mean such a kit never gets its segments and the
            // annotator is given a waveform with nothing on it.
            const segments = graph_rows(graph_state, 'SegmentListItem');
            console.log('[imported]', x.tier, x.rows.length, 'spans from', x.docid,
                        '/ kit holds', segments.length, 'segments');
            set_reference_text_for(x.rows);
            if(segments.length == 0) add_blank_segments_for(x.rows);
            lock_to_text_only();
        } );
    }

    // From here on the only message this tool may send is a change to a
    // segment's text. Set on ldc so add_message can refuse the rest at the
    // point they'd become messages — whatever gesture, button or keystroke
    // got there. The keymaps and the segment list check it too, so the
    // affordances are gone rather than merely inert.
    function lock_to_text_only(){
        lock_text_only();   // what the operations in modification1.js ask
        text_only = true;   // what the segment list and the cheat sheet render from
        ldc.text_only = true; // a breadcrumb for the console and the harness
    }

    // ─── Comments ─────────────────────────────────────────────────────────
    //
    // A remark about a stretch of audio: its own span, its own label, its own
    // list. Nothing that writes a transcript reads them, so they stay out of
    // every export without anything having to filter them.

    // From the current selection, or from the active segment's span when there
    // is no selection — the common case being "this line needs a note".
    function comment_span(){
        const beg = activeo.wave_selection_offset;
        const end = round_to_3_places(beg + activeo.wave_selection_length);
        if(activeo.wave_selection_length > 0) return { beg: beg, end: end };
        const row = index_segments_by_id.get(activeo.active);
        if(row && row.beg != null && row.end != null) return { beg: row.beg, end: row.end };
        return null;
    }

    function add_comment(){
        if(!constraint_comments) return;
        const span = comment_span();
        if(!span){
            alert('select a stretch of audio, or a segment, to comment on');
            return;
        }
        const docid = docids[activeo.channel];
        if(add_comment_to_list(docid, span, '') === 'submit'){
            add_audio_to_listq( () => {
                update_segments_with();
                // Focus the row that was just made, so the comment can be
                // typed without reaching for the mouse.
                comment_focus_iid = Math.max(...[ ...cmtmap.keys() ]);
            } );
        }
    }
    let comment_focus_iid = $state(null);
    // Whether the comments panel is showing. Its switch is in the Controls
    // toolbar; there's no key for it, and none for making a comment either —
    // the panel's own button does that.
    let comments_open = $state(false);

    // The Comment label of a comment row, changed the way any other label is.
    function set_comment_text(row, value){
        const iid = row.label_iids && row.label_iids.Comment;
        if(iid == null || value === row.text) return;
        change_value(iid, value, () => update_segments_with());
    }

    // The list item goes, and its label and span go with it. Its anchors stay,
    // as they do for a segment.
    function delete_comment(row){
        delete_segments([ row.iid ], () => update_segments_with());
    }

    // Scroll + zoom the waveform to center the given segments' time span, padding
    // it by half a second on each side (so the window is one second longer than
    // the span). For the common single-segment case this centers that segment.
    function center_window_on_segments(segs){
        if(!segs || !segs.length || !channelsc) return;
        let beg = Infinity, end = -Infinity;
        for(const s of segs){
            if(s.beg < beg) beg = s.beg;
            if(s.end > end) end = s.end;
        }
        if(!isFinite(beg) || !isFinite(end) || end <= beg) return;
        const pad = 0.5;
        // Window = segment padded by `pad` on each side, e.g. segment [5, 15] with
        // pad 0.5 -> window [4.5, 15.5]. set_times_then_draw takes (start, length).
        console.log('[import] center', { seg_beg: beg, seg_end: end, window_start: beg - pad, window_end: end + pad });
        channelsc.set_times_then_draw(beg - pad, (end - beg) + pad * 2);
    }

    // Follow the active segment: whenever the selected transcript line changes
    // — arrow up/down in the segment list, a click, or next-and-play — recenter
    // the window on it with the same padding as the import. Reacts to
    // activeo.active (set by set_active_transcript_line) and the follow toggle.
    // Only reads those, so setting the window offset/length below can't re-trigger it.
    $effect(() => {
        if(!follow_active_segment) return;
        const id = activeo.active;
        if(id == null) return;
        const seg = index_segments_by_id.get(id);
        if(seg) center_window_on_segments([seg]);
    });

    // Batch-add empty (no text) editable segments at the given segments' times,
    // then submit once — same path add_timestamps2/create_segments use.
    function add_blank_segments_for(segs){
        const docid = docids[activeo.channel];
        for(const s of segs){
            const length = round_to_3_places(s.end - s.beg);
            add_audio_to_list(docid, null, null, { offset: s.beg, length });
        }
        add_audio_to_listq( () => update_segments_with() );
    }

    function segment_list_f(show){
        // if(!($(".ChannelA").length > 0)) return;
        const pair = create_segments();
        const segments = pair[0];
        const undefined_segments = pair[1];
        segmentsc.index_segments(segments);
        const sections = (function() {
            const ref = index_sections_by_name;
            const results = [];
            for (let k in ref) {
                let v = ref[k];
                results.push(v);
            }
            return results;
        })();
        if(debug){
            console.log("INDEX");
            console.log(index_sections_by_name);
            console.log('TEST');
            console.log(segments);
            console.log(sections);
        }
        const o = {
            segments: segments,
            undefined_segments: undefined_segments,
            sections: sections,
            show: show
        };
        return o;
        // ns.main.set_segments(segments, sections, show);
    }

    function create_segments(){
        const vars = ldc.vars;
        const sel1 = `.${vars.add_from_waveform_list}Item`;
        const sel2 = `.${vars.add_from_waveform_audio}`;
        const sel3 = `.${vars.add_from_waveform_text}`;
        const sel4 = ".Speaker";
        const segments = [];
        const undefined_segments = [];
        document.querySelectorAll(sel1).forEach(function(x, i){
            const data = ldc.$(x).find(sel2).data();
            const src = data.value;
            if(!src.beg && src.beg != 0){
                undefined_segments.push(ldc.$(x).data().meta.id);
                return;
            }
            const c1 = {
                id: `unsorted-${i}`,
                iid: ldc.$(x).data().meta.id,
                docid: src.docid,
                beg: src.beg,
                end: src.end,
                text: ldc.$(x).find(sel3).data().value.value || '',
                speaker: ldc.$(x).find(sel4).data().value.value || '',
                section: null,
                error: new Map()
            };
            let n1 = c1.text.match(/\(/g);
            if(!n1) n1 = [];
            let n2 = c1.text.match(/\)/g);
            if(!n2) n2 = [];
            if(c1.text && n1.length != n2.length) c1.error.set("unbalanced parens");
            else                                  c1.error.delete("unbalanced parens")
            // if(c1.text && n1 && n2) c1.error = 'x'
            segments.push(c1);
        });
        segments.sort( (x, y) => x.beg - y.beg );
        return [ segments, undefined_segments ];
    }

    // let set_playing_transcript_line_index;
    const index2 = new Map();
    const index_segments_by_id = new Map();
    const wmap = new Map();
    const segmap = new SvelteMap();
    const secmap = new Map();
    // Comments live apart from the transcript, in the same way segments and
    // sections do: one row per CommentListItem span, made and unmade by
    // refold_graph.
    const cmtmap = new SvelteMap();
    ldc.index2 = index2;
    ldc.index_segments_by_id = index_segments_by_id;
    ldc.wmap = wmap;
    ldc.segmap = segmap;
    ldc.secmap = secmap;
    ldc.cmtmap = cmtmap;
    const nmap = new Map();
    ldc.nmap = nmap;
    // const gmap = new Map();

    let index_sections_by_segment_id;
    const index_sections_by_name = new Map();
    function create_section_index(){
        const begmap = {};
        const endmap = {};
        index_sections_by_segment_id = {};
        index_sections_by_name.clear();
        ldc.index_sections_by_segment_id = index_sections_by_segment_id;
        ldc.index_sections_by_name = index_sections_by_name;
        return document.querySelectorAll('.SectionListItem').forEach(function(x) {
            var a, b, id, s, section;
            section = ldc.$(x).find(".Section").data().value.value;
            a = ldc.$(x).find('.BegSeg').data().value.value;
            b = ldc.$(x).find('.EndSeg').data().value.value;
            if (a && b && a === b) {
                id = segmap.get(Number(a)).id;
                s = {
                    name: section,
                    beg: id,
                    end: id,
                    list_item_id: ldc.$(x).data().meta.id
                };
                if(index_segments_by_id.has(id)){
                    s.begr = index_segments_by_id.get(id).beg;
                    s.endr = index_segments_by_id.get(id).end;
                }
                else{
                    if(debug) console.log(`was segment ${id} deleted?`);
                }
                index_sections_by_segment_id[id] = s;
                return index_sections_by_name[section] = s;
            } else {
                if (a) {
                    id = segmap.get(Number(a)).id;
                    s = {
                        name: section,
                        beg: id,
                        list_item_id: ldc.$(x).data().meta.id
                    };
                    if(index_segments_by_id.has(id)){
                        s.begr = index_segments_by_id.get(id).beg;
                    }
                    else{
                        if(debug) console.log(`was segment ${id} deleted?`);
                    }
                    index_sections_by_segment_id[id] = s;
                    index_sections_by_name[section] = s;
                }
                if (b) {
                    id = segmap.get(Number(b)).id;
                    s = index_sections_by_name[section];
                    s.end = id;
                    if(index_segments_by_id.has(id)){
                        s.endr = index_segments_by_id.get(id).end;
                    }
                    else{
                        if(debug) console.log(`was segment (${b}, ${id}) deleted?`);
                    }
                    return index_sections_by_segment_id[id] = s;
                }
                if(!a && !b && !section){
                    s = {
                        name: section,
                        list_item_id: ldc.$(x).data().meta.id
                    };
                    index_sections_by_name[section] = s;
                }
            }
        });
    }

    function create_section_index2(){
        const begmap = {};
        const endmap = {};
        index_sections_by_segment_id = {};
        index_sections_by_name.clear();
        ldc.index_sections_by_segment_id = index_sections_by_segment_id;
        ldc.index_sections_by_name = index_sections_by_name;
        for(const [k, v] of secmap){
            let s;
            // From the row, which refold_graph has just refreshed from the
            // graph. Reading the node layer here meant reading each node's
            // mirror of its store, which lags a burst of changes — the section
            // was still nameless when this ran, and the exported transcript
            // came out without it.
            const section = v.section;
            const a = v.begi;
            const b = v.endi;
            if(debug){
                console.log('ARC')
                console.log(arc)
            }
            if (a && b && a === b) {
                id = segmap.get(a-1).id;
                s = {
                  name: section,
                  beg: id,
                  end: id,
                  list_item_id: k
                };
                if(index_segments_by_id.has(id)){
                  s.begr = index_segments_by_id.get(id).beg;
                  s.endr = index_segments_by_id.get(id).end;
                }
                else{
                  console.log(`was segment ${id} deleted?`);
                }
                index_sections_by_segment_id[id] = s;
                index_sections_by_name[section] = s;
            } else {
                if (a) {
                    // id = wrmap.get(`node-${a}`);
                    s = {
                        name: section,
                        // beg: id,
                        begr: nmap.get(a).beg,
                        list_item_id: k
                    };
                    index_sections_by_name[section] = s;
                }
                if (b) {
                    // id = wrmap.get(`node-${b}`);
                    s = index_sections_by_name[section];
                    // s.end = id;
                    s.endr = nmap.get(b).beg;
                }
                if(!a && !b && !section){
                    s = {
                        name: section,
                        list_item_id: k
                    };
                    index_sections_by_name[section] = s;
                }
            }
        }
    }

    function sources_object_add_node_helper(id, x){
        const data = {
            meta: {
            id: id
            },
            value: {
            docid: x.docid,
            beg: x.beg,
            end: x.end
            }
        };
        sources_object_add_node(null, data);
    }
    // Nothing subscribes. Rows are made and unmade in refold_graph from the
    // spans themselves, and edits reach them through apply_to_graph before the
    // node layer is touched. This just draws the first transcript.
    function new_update_segments(){
        sort_segments();
        sort_sections();
    }

    // The transcript is the annotation graph. Rows are made, updated and
    // dropped in refold_graph from the spans themselves; every edit reaches
    // them through apply_to_graph, which runs before anything else so the
    // display never lags a message.
    //
    // The node layer still exists — init_nodes builds it from the payload and
    // addf adds to it — but nothing here reads it any more, and no value is
    // written into it. The annotations are the record either way: the messages
    // this sends are byte-for-byte the ones it always sent.

    // A new group's iids and its group string, allocated on the graph side. The
    // string is what goes to the server, so this is the encoder of the wire
    // format: "5:SegmentListItem,6:Arc,7:Text,8:Speaker", children in the order
    // the class def declares them. last_iid stays on the payload object, which
    // is where it arrived and where it will stay when the node layer goes.
    ldc.allocate_group = (list) => {
        const group = new_group(list, groups, ldc.obj.last_iid);
        ldc.obj.last_iid = group.last_iid;
        return { value: group.value };
    };

    // Installed only where there is a graph. Its presence is also what tells
    // add_message not to write the value into the node layer as well.
    // The working set of a whole-transcript operation, open between the first
    // message and the panel coming down. Null the rest of the time, which is
    // what tells apply_to_graph which path it is on.
    let batch = null;
    // Set while the fold is being skipped, so it can be paid for once at the end.
    let render_deferred = false;

    $effect(() => {
        // The panel clearing is the signal that the list is about to be seen
        // again: close the batch, publish it as one change, and fold once —
        // rather than doing either per message on the way.
        if(!bulko.label && (batch || render_deferred)){
            if(batch){
                const next = end_batch(batch);
                batch = null;
                if(next) set_graph(next, 'live');
            }
            render_deferred = false;
            sort_segments();
            sort_sections();
        }
    });

    ldc.apply_to_graph = (message, node, value) => {
        // A whole-transcript operation. apply_message would scan and copy a row
        // collection per message, and sort after every add — O(messages x rows),
        // for intermediate graphs nobody can see, because the list is hidden
        // behind the progress panel. One working copy instead, O(1) per message,
        // published once by the effect above.
        if(bulko.label){
            batch = batch || begin_batch(graph_state);
            apply_batched(batch, message, node, value);
            render_deferred = true;
            return;
        }

        // One edit at a time: pure, and the rune sees each keystroke.
        const next = apply_message(graph_state, message, node, value);
        if(!next) return;
        set_graph(next, 'live');
        // The pump. The rows, and so the transcript, follow the messages —
        // this is what the per-node store subscriptions used to be for.
        sort_segments();
        sort_sections();
    };

    function refold_graph(){
        // Nothing has written to the rows yet on the first pass: the payload
        // fold is what the page loaded with, and this marks it live.
        if(graph_state.source !== 'live'){
            set_graph({ nodes: graph_state.nodes, arcs: graph_state.arcs, labels: graph_state.labels }, 'live');
        }

        const g = graph_state;
        const time = new Map(g.nodes.map( (n) => [ n.iid, n.time ] ));
        const docid = new Map(g.nodes.map( (n) => [ n.iid, n.docid ] ));
        const labels = new Map();
        const label_nodes = new Map();
        for(const l of g.labels){
            if(!labels.has(l.arc_iid)){ labels.set(l.arc_iid, {}); label_nodes.set(l.arc_iid, {}); }
            labels.get(l.arc_iid)[l.name] = l.value;
            label_nodes.get(l.arc_iid)[l.name] = l;
        }

        // The anchors, as the section indexing wants them. Same lifecycle as the
        // rows: one entry per anchor in the graph, and no others.
        for(const n of g.nodes){
            let anchor = nmap.get(n.iid);
            if(!anchor){ anchor = {}; nmap.set(n.iid, anchor); }
            anchor.docid = n.docid;
            anchor.beg = n.time;
        }
        const anchors = new Set(g.nodes.map( (n) => n.iid ));
        for(const k of [ ...nmap.keys() ]) if(!anchors.has(k)) nmap.delete(k);

        // The rows the transcript is made of, kept in step with the spans: one
        // per arc, created when an arc appears and dropped when it goes. This
        // is what the node_lists subscriptions used to do, before rows had a
        // graph to follow.
        // Which list a span belongs in, by the name of its group. Named rather
        // than "section or else segment": an invented group — a comment, or
        // whatever a class def declares next — used to fall through to the
        // transcript and appear as a segment. Anything unrecognised is left
        // alone now, which is what the server does with it too.
        const kinds = {
            SegmentListItem: 'segments',
            SectionListItem: 'sections',
            CommentListItem: 'comments'
        };
        const maps = { segments: segmap, sections: secmap, comments: cmtmap };

        const row_for = (arc, kind) => {
            const map = maps[kind];
            let row = map.get(arc.iid);
            if(!row){
                row = { id: `unsorted-${arc.iid}`, iid: arc.iid, text: '', speaker: '', section: null };
                if(kind == 'segments') row.error = new Map();
                map.set(arc.iid, row);
            }
            return row;
        };

        // Every span, not only the ones with times: a segment whose anchors
        // haven't been placed yet still has a row, and has to come out of this
        // with no time so sort_segments puts it in tundef.
        const live = { segments: new Set(), sections: new Set(), comments: new Set() };
        for(const arc of g.arcs){
            const kind = kinds[arc.name];
            if(!kind) continue;
            const section = kind == 'sections';
            live[kind].add(arc.iid);
            const c1 = row_for(arc, kind);
            const own = labels.get(arc.iid) || {};
            const own_labels = label_nodes.get(arc.iid) || {};
            c1.label_iids = Object.fromEntries(Object.entries(own_labels).map( ([ n, l ]) => [ n, l.iid ] ));

            const was = { beg: c1.beg, end: c1.end, docid: c1.docid };
            c1.begi = arc.beg_iid;
            c1.endi = arc.end_iid;
            c1.beg = time.has(arc.beg_iid) ? time.get(arc.beg_iid) : null;
            c1.end = time.has(arc.end_iid) ? time.get(arc.end_iid) : null;
            if(docid.get(arc.beg_iid) != null) c1.docid = docid.get(arc.beg_iid);
            if(section){
                c1.section = own.Name ?? null;
                if(c1.section) sectionsm.set(c1.section, c1.section);
                continue;
            }
            if(kind == 'comments'){
                // One label, and none of what a segment carries — no speaker,
                // no section, no paren check, and no place in the transcript.
                c1.text = own.Comment ?? '';
                continue;
            }

            c1.text = own.Text ?? '';
            c1.speaker = own.Speaker ?? '';
            // The speaker picker offers what's already been used. The Speaker
            // subscription used to feed it; nothing subscribes now.
            if(c1.speaker) speakersm.set(c1.speaker, c1.speaker);

            // Flagged on the row and shown under it by segments.svelte. Used to
            // be computed in the Text subscription, which no longer sees the
            // value it would check.
            if(c1.error){
                const opened = (c1.text.match(/\(/g) || []).length;
                const closed = (c1.text.match(/\)/g) || []).length;
                if(c1.text && opened != closed) c1.error.set("unbalanced parens");
                else                            c1.error.delete("unbalanced parens");
            }

            // The sources object drives playback of a span, so it has to follow
            // the times. Only worth doing when they actually moved.
            if(c1.beg != null && (was.beg !== c1.beg || was.end !== c1.end || was.docid !== c1.docid)){
                // The Arc child's iid names the playable span. The fallback is
                // the legacy group layout — Arc sits at list item + 1.
                sources_object_add_node_helper(`${arc.arc_node_iid ?? arc.iid + 1}`, c1);
            }
        }

        // A span that's gone from the graph — deleted, or merged away — takes
        // its row with it.
        for(const k of [ ...segmap.keys() ]) if(!live.segments.has(k)) segmap.delete(k);
        for(const k of [ ...secmap.keys() ]) if(!live.sections.has(k)) secmap.delete(k);
        for(const k of [ ...cmtmap.keys() ]) if(!live.comments.has(k)) cmtmap.delete(k);
    }

    // Comments in time order. Their own list, kept out of transcript.segments
    // — which is what create_transcript writes — so no export has to know to
    // leave them out.
    function sort_comments(){
        transcript.comments = [ ...cmtmap.values() ]
            .sort( (x, y) => (x.beg ?? 0) - (y.beg ?? 0) || x.iid - y.iid );
    }

    function sort_segments(){
        refold_graph();
        sort_comments();
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
            // One line per read-only row, on every fold — and a fold happens per
            // message while editing. Guarded; its neighbours already were.
            if(debug) console.log(x)
            tsegs.push(x);
        }
        // Sort by start time; when times tie (e.g. a read-only reference segment
        // and the matching editable one), put the read-only one first.
        tsegs.sort( (x, y) => (x.beg - y.beg) || ((y.readonly ? 1 : 0) - (x.readonly ? 1 : 0)) );
        segmentsc.index_segments(tsegs);
        transcript.segments = tsegs;
        transcript.undefined_segments = tundef;
    }

    function sort_sections(){
        const ref = index_sections_by_name;
        const results = [];
        for (let k in ref) {
            let v = ref[k];
            results.push(v);
        }
        transcript.sections = results;
    }

    let ttextarea = $state();
    let t_previous = new Map();
    let t_iid;
    let t_value = $state();
    let t_readonly = $state();
    let t_timeout;

    function fmap2(delegate, e, map){
        if(e.ctrlKey || e.altKey) map = map.control;
        if(!map) map = {};
        const f = map[e.key];
        if(f){
            if(delegate[f]){
                return delegate[f](e);
            }
            else{
                console.log(`no function: ${f}`);
                return 'none';
            }
            // return f;
        }
        else{
            console.log('no binding 2');
            console.log(e);
            return 'none';
        }
    }






    let rando = 0;
    let help_screen = $state();
    let input_screen = $state();
    let check_redactions = setInterval( () => {
        if(!redactions.has(redactiondocid)) return;
        const r = redactions.get(redactiondocid);
        if(r && r !== true && channelsc){
            channelsc.set_all_redactions(r);
            clearInterval(check_redactions);
        }
    }, 500);
    const help_screen_mini_css = "shadow-xl bg-white border-2 rounded fixed right-24 top-48 opacity-100 z-10";
</script>

<DesyncBanner />

<!-- <div>previous {asro.previous}</div>
<div>type {asro.type}</div>
<div>status {asro.status}</div>
<div>i {asro.i}</div>
<div>source {asro.source_uid}</div>
<div>segments length {asro.segments.length}</div>
<div>items length {asro.items?.length}</div>
<div>vvsegs length {asro.vvsegs.length}</div>
<div>added {asro.addedn}</div>
<div>channels {asro.source_uid_channels}</div>
<div>prev {asro.asr_previous.length}</div> -->
<!-- <div>results {JSON.stringify(asro.result)}</div> -->

<Toaster richColors expand={true} />

    <!-- .selection-handle {
        cursor: col-resize;
        z-index: 11;
    } -->

    <!-- pre {
        width: 800px;
        overflow: auto;
    } -->


<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<CommandDialog
    bind:dialogRef={dialog_command}
    bind:commandLine={command_line}
    onEnter={() => command_line_enter = true}
    {btn1}
/>

<MainHelpDialog
    {controls}
    {source_uid_channels}
    {docids}
    {ldc}
    {text_only}
/>



<DeleteAllStereoDialog bind:dialogRef={dialog_delete_all2} onConfirm={delete_all2_wrapper} {btn} {dbtn} />

<SettingsDialog bind:dialogRef={dialog_settings} settingsArray={dialog_settings_a} settingsHash={dialog_settings_h} currentModifier={current_modifier} onSelectModifier={set_modifier} onKeydown={dialog_settings_keydown} />

<SpectrogramDialog bind:dialogRef={dialog_spectrogram} />

{#if spectrogram_open}
    <!-- svelte-ignore missing_declaration -->
    <!-- <Spectrogram
        bind:this={spectrogram}
        {waveform}
    /> -->
{/if}

<Controls
    bind:this={controls}
    {redact_task}
    {muted}
    {constraint_import_transcript}
    {permissions}
    {permission_to_download}
    {constraint_audit}
    {dialog_close_kit_audit}
    {show_asr}
    {asr}
    {dialog_close_kit}
    {dialog_delete_all}
    {data_set_id}
    {data_set_file_name}
    {update_segments}
    {update_segments2}
    {update_segments2_with_blanks}
    {add_save_asr}
    {show_graph}
    {kit_id}
    {kit_source_uid}
    bind:follow_active_segment
    {constraint_comments}
    bind:comments_open
    bind:speaker_is_subject
/>

{#if audiofp}
{#await audiofp}
    loading audio
{:then v}
<Channels
    bind:this={channelsc}
    {ldc}
    {nchannels}
    {underline}
    {wave_canvas_height}
    {width}
    {create_audio_hash_from_docid}
    {create_audiok_from_docid}
    {docids}
    {debug}
    {redact_task}
    {set_current_selection}
    {controls}
    {wave_active_transcript_line}
    {set_active_transcript_line_helper}
    {duration}
    {play_head}
    {wmap}
    {source_uid_channels}
    {segmentsc}
/>
{/await}
{/if}

<Sections
    {update_segments}
/>

{#if constraint_comments && comments_open}
    <Comments
        {add_comment}
        {set_comment_text}
        {delete_comment}
        focus_iid={comment_focus_iid}
        play_span={(row) => { set_current_selection_by_src(row); play_current_span(); }}
    />
{/if}

<!-- <Segments {ns} {waveform} on:userf on:click_transcript_line /> -->
<HelpScreen
    bind:this={help_screen}
    {refocus}
    {fmap2}
    {help_screen_mini_css}
/>
<InputScreen
    bind:this={input_screen}
    {controls}
/>
{#if imported_error}
    <!-- This kit is set up to transcribe an imported transcript and there
         isn't one for its audio. Nothing has been created and nothing is
         locked; saying so beats an empty waveform with no explanation. -->
    <div class="text-center text-red-600">
        No imported transcript for this kit — {imported_error}
    </div>
{/if}
{#if output_promise}
    {#await output_promise}
        <div class="text-center text-red-500">working...</div>
    {:then v}
        {#if v.result != "ok"}
            <!-- <div>{JSON.stringify(v)}</div> -->
            {#each v.errors as x}
                <div class="text-center text-red-500">{x}</div>
            {/each}
        {/if}
    {/await}
{/if}

{#if experimental}
    <!-- <div class="w-96 mx-auto">
        <button id="xasrb2" class="{btn}" on:click={xasrr}>add ASR segments</button>
        <button id="xasrb" class="{btn}" on:click={xasr}>get ASR segments</button>
    </div> -->
{/if}

<Segments
    bind:this={segmentsc}
    {ldc}
    {debug}
    {text_only}
    {docids}
    {set_current_selection}
    {wave_active_transcript_line}
    {set_active_transcript_line_helper}
    {play_head}
    {constraint_rtl}
    {index_segments_by_id}
    {segmap}
    {secmap}
    {update_segments}
    {set_speaker}
    {show_sections}
    {open_section}
    {close_section}
    {validate_transcript}
    {play_head_menu}
    {generic_next}
    {play_current_span}
    {play_current_span_and_add_transcript_line_and_activate}
    {wmap}
    {index2}
    {index_sections_by_name}
    {create_section_index}
    {create_section_index2}
    {split_line_margin}
    {controls}
    {channelsc}
/>

{#if graph_open}
    <GraphPanel
        loading={graph_loading}
        error={graph_error}
        onRefresh={build_graph}
        onHide={hide_graph}
        {btn}
    />
{/if}
