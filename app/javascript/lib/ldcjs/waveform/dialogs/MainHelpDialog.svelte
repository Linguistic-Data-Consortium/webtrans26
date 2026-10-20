<script>
    import BaseDialog from './BaseDialog.svelte';
    import {
        AsrSpanDialog,
        ServicesDialog,
        ASRDialog,
        KeyboardCheatSheetDialog
    } from '../dialogs';
    import { fmap_helper } from '../helpers';
    import { key } from '../stores';
    import { event } from '../../../../guides/guide';
    import { mark_transcription } from '../../../guide_state';
    import { asro, sado, run_asr4, run_sad } from '../asr.svelte';
    import { services_configured } from '../../service_config';
    import { modes, home_keys, waveform_map, input_map, playback_map, modifier_label, text_only_forbidden } from '../bindings';
    import { settings } from '../stores';
    let {
        controls,
        source_uid_channels,
        docids,
        ldc,
        // transcribe_text_only: the keys that change the transcript's shape
        // don't do anything, so the sheet shows them struck through rather
        // than promising something that won't happen.
        text_only = false
    } = $props();

    let dialog_main = $state();
    let dialog_services = $state();
    let dialog_span = $state();
    let span_dialog = $state();
    let dialog_asr = $state();
    let dialog_keyboard = $state();
    let add_which = $derived.by(() => {
        if(sado.status) return 'asr';
        if(asro.type?.match(/^asr/)) return 'asr';
        return '';
    });

    $effect(() => {
        if(sado.status || asro.type?.match(/asr/)){
            dialog_asr.showModal();
        }
    });

    function focus(x) { x.focus(); }

    // The selected modifier label flows through the cheat sheet so control
    // bindings render with the currently-active modifier (ctrl/alt/⌘/etc).
    let current_modifier = $state('ctrl');
    settings.subscribe(s => current_modifier = s.modifier || 'ctrl');
    let mod_label = $derived(modifier_label(current_modifier));

    // Pull cheat-sheet rows out of a keymap. Every entry surfaces — bare-string
    // entries (legacy, no `desc`) fall back to using the action name. `group`
    // is an optional filter so a section can take just its slice. `ctrl=true`
    // marks the entries as modifier-key bindings (the cheat sheet then
    // prepends the active modifier label).
    function rows(map, group, ctrl=false){
        const out = [];
        for (const [k, v] of Object.entries(map || {})) {
            if (k === 'control') continue;
            const obj = typeof v === 'object' ? v : { action: v };
            if (group != null && obj.group !== group) continue;
            out.push({
                key: obj.label ?? k,
                desc: obj.desc ?? obj.action,
                dir: obj.dir,
                size: obj.size,
                ctrl,
                off: text_only && text_only_forbidden.has(obj.action)
            });
        }
        return out;
    }
    let home_row = $derived(
        home_keys.map(({k, size}) => {
            const v = waveform_map.cursor[k];
            return { k, size, desc: typeof v === 'object' ? v.desc : null };
        })
    );
    let mode_switches  = $derived(rows(waveform_map.cursor, 'mode'));
    let waveform_cmds  = $derived([
        ...rows(waveform_map.cursor, 'global'),
        ...rows(waveform_map.control.cursor, 'global', true)
    ]);
    let waveform_sys   = $derived(rows(waveform_map.cursor, 'system'));
    let input_cmds = $derived([
        ...rows(input_map, 'global'),
        ...rows(input_map.control, 'global', true)
    ]);
    let playback_cmds = $derived(rows(playback_map, 'global'));

    function onKeydown(e){
        switch(e.key){
            case '4':
                dialog_main.close();
                dialog_services.showModal();
                break;
            case '5':
                dialog_main.close();
                window.open(
                    'https://docs.google.com/document/d/e/2PACX-1vSTU3051TwfSjLorIpae_Yy5G6veJwuo1AXPW7fvVWlD-CIZ95KpQL2zyfV3FoRNBtf6JZARobEtGCz/pub',
                    'webann_document_window',
                    'toolbar=no,menubar=no,status=no,width=1000,height=500'
                );
                break;
            case '6':
                dialog_main.close();
                dialog_keyboard.showModal();
                break;
            case '/':
                break;
            default:
                dialog_main.close();
                controls.keyboard_focus();
        }
    }

    key.subscribe((e) => {
        if(!e) return;
        const map = { 'h': 'h' };
        const x = fmap_helper(e, map);
        if (x === 'h') show_main();
    });

    function show_main(){
        dialog_main.showModal();
        event.dispatch(dialog_main, 'opened_help');
        event.dispatch(dialog_main, 'destroy_opened_help_transcript');
        mark_transcription('help_opened');
    }

    // With the asr_range constraint on, choosing an ASR service asks which
    // stretch of audio it may fill and the run is bounded by the answer. Off —
    // the default — a run adds the whole transcript the service returns, which
    // is how ASR behaved before the prompt existed. SAD is not an ASR run and
    // never asks.
    const constraint_asr_range = ldc.get_constraint('asr_range');
    let pending_asr_type = null;

    function start_asr_run(type){
        if(constraint_asr_range) ask_for_span(type);
        else                     run_asr4(type, docids, ldc, source_uid_channels);
    }

    function ask_for_span(type){
        pending_asr_type = type;
        span_dialog.prefill_from_selection();
        dialog_span.showModal();
    }

    function start_asr(span){
        const type = pending_asr_type;
        pending_asr_type = null;
        if(!type) return;
        run_asr4(type, docids, ldc, source_uid_channels, span);
    }

    function cancel_asr(){
        pending_asr_type = null;
        controls.keyboard_focus();
    }

    // The menu keys are commands, not text. Without preventDefault the browser
    // still performs the keystroke's default action after this runs — and where
    // an ASR option opens the span dialog, whose first field takes focus, the
    // digit landed in it: the span began as "06".
    const SERVICES_KEYS = new Set([ 'h', '1', '2', '3', '4', '5', '6' ]);

    function dialog_services_keydown(e){
        if(SERVICES_KEYS.has(e.key)) e.preventDefault();
        // With nothing configured the dialog shows a notice rather than the
        // numbered menu, so there is nothing to pick — but the keys still
        // reach here, and dispatching them would start a run against an empty
        // endpoint. Only 'h' does anything.
        if(!services_configured() && e.key !== 'h') return;
        dialog_services.close();
        switch(e.key){
            case 'h':
                show_main();
                break;
            case '1':
                run_sad(docids, ldc, source_uid_channels);
                break;
            case '2':
                start_asr_run('asr4');
                break;
            case '3':
                start_asr_run('asr6');
                break;
            case '4':
            case '5':
                alert('unavailable');
                break;
        }
    }
</script>

<BaseDialog bind:dialogRef={dialog_main} size="w-[96vw] max-w-none !max-h-[96vh]" title="Keyboard Cheat Sheet" {onKeydown} showClose={false}>
    {#snippet children({ dialog })}
        <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div use:focus tabindex="0" onkeydown={onKeydown} class="p-5 h-[calc(96vh-4rem)] overflow-auto outline-none text-sm">
            <div class="bg-amber-50 border border-amber-200 rounded p-2 mb-4 flex items-center gap-3 text-xs">
                <span class="text-amber-900">Keyboard icon must be focused for keys to register.</span>
                <span class="text-amber-900">Press <kbd class="px-1.5 py-0.5 bg-white rounded font-mono shadow-sm">h</kbd> any time to reopen.</span>
                <span class="ml-auto text-amber-700">Press any other key to dismiss.</span>
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">

                <!-- Column 1: Modes, Home Keys, Mode Switches -->
                <section class="space-y-4">
                    <div>
                        <h3 class="text-xs font-bold uppercase tracking-wide text-gray-500 mb-2">Modes</h3>
                        <div class="space-y-1.5">
                            {#each modes as m}
                                <div class="flex items-center gap-2 p-2 rounded {m.bg} {m.text}">
                                    <kbd class="inline-flex items-center justify-center w-6 h-6 rounded border border-current/40 bg-white/70 font-mono text-xs">{m.key}</kbd>
                                    <div class="flex-1">
                                        <div class="font-semibold leading-tight">{m.name}</div>
                                        <div class="text-[11px] opacity-80 leading-tight">{m.desc}</div>
                                    </div>
                                </div>
                            {/each}
                        </div>
                    </div>

                    <div>
                        <h3 class="text-xs font-bold uppercase tracking-wide text-gray-500 mb-2">Home Keys</h3>
                        <p class="text-xs text-gray-600 mb-2">Left hand moves backward, right hand moves forward. Inner keys are small steps, outer keys are large.</p>
                        <div class="flex items-center justify-center gap-0.5 p-2 bg-gray-50 rounded">
                            {#each home_row as hk, i}
                                {#if i === 4}
                                    <div class="w-px h-8 bg-gray-300 mx-1"></div>
                                {/if}
                                <div class="flex flex-col items-center">
                                    <kbd class="inline-flex items-center justify-center w-7 h-7 rounded border border-gray-300 bg-white font-mono text-xs">{hk.k}</kbd>
                                    <span class="text-[9px] text-gray-500 mt-0.5">{hk.size}</span>
                                </div>
                            {/each}
                        </div>
                        <p class="text-[11px] text-gray-500 mt-2">Step sizes scale with zoom. Exact durations are shown in the mode banner at the top of the screen.</p>
                    </div>

                    {#if mode_switches.length}
                        <div>
                            <h3 class="text-xs font-bold uppercase tracking-wide text-gray-500 mb-2">Mode Switches (from Cursor)</h3>
                            <div class="space-y-1">
                                {#each mode_switches as m}
                                    <div class="flex items-center p-1.5 bg-gray-50 rounded">
                                        <kbd class="px-1.5 py-0.5 bg-white border border-gray-300 rounded font-mono text-xs mr-2 min-w-[40px] text-center">{m.key}</kbd>
                                        <span class="text-gray-700 text-xs">{m.desc}</span>
                                    </div>
                                {/each}
                            </div>
                        </div>
                    {/if}
                </section>

                <!-- Column 2: Waveform commands + System -->
                <section class="space-y-4">
                    <div>
                        <h3 class="text-xs font-bold uppercase tracking-wide text-gray-500 mb-2">Waveform Commands</h3>
                        <div class="space-y-1">
                            {#each waveform_cmds as wk}
                                <div class="flex items-center p-1.5 bg-gray-50 rounded {wk.off ? 'opacity-40' : ''}">
                                    <kbd class="px-1.5 py-0.5 bg-white border border-gray-300 rounded font-mono text-xs mr-2 min-w-[70px] text-center">{wk.ctrl ? `${mod_label}-${wk.key}` : wk.key}</kbd>
                                    <span class="text-gray-700 text-xs {wk.off ? 'line-through' : ''}">{wk.desc}</span>
                                </div>
                            {/each}
                        </div>
                    </div>

                    {#if waveform_sys.length}
                        <div>
                            <h3 class="text-xs font-bold uppercase tracking-wide text-gray-500 mb-2">System</h3>
                            <div class="space-y-1">
                                {#each waveform_sys as wk}
                                    <div class="flex items-center p-1.5 bg-gray-50 rounded">
                                        <kbd class="px-1.5 py-0.5 bg-white border border-gray-300 rounded font-mono text-xs mr-2 min-w-[70px] text-center">{wk.key}</kbd>
                                        <span class="text-gray-700 text-xs">{wk.desc}</span>
                                    </div>
                                {/each}
                            </div>
                        </div>
                    {/if}
                </section>

                <!-- Column 3: Text input, playback menu, services -->
                <section class="space-y-4">
                    <div>
                        <h3 class="text-xs font-bold uppercase tracking-wide text-gray-500 mb-2">Text Input (when input is focused)</h3>
                        <div class="space-y-1">
                            {#each input_cmds as ik}
                                <div class="flex items-center p-1.5 bg-gray-50 rounded {ik.off ? 'opacity-40' : ''}">
                                    <kbd class="px-1.5 py-0.5 bg-white border border-gray-300 rounded font-mono text-xs mr-2 min-w-[80px] text-center">{ik.ctrl ? `${mod_label}-${ik.key}` : ik.key}</kbd>
                                    <span class="text-gray-700 text-xs {ik.off ? 'line-through' : ''}">{ik.desc}</span>
                                </div>
                            {/each}
                        </div>
                    </div>

                    <div>
                        <h3 class="text-xs font-bold uppercase tracking-wide text-gray-500 mb-2">Playback Menu (open with <kbd class="px-1 py-0.5 bg-white border border-gray-300 rounded font-mono text-[10px]">p</kbd>)</h3>
                        <div class="space-y-1">
                            {#each playback_cmds as pk}
                                <div class="flex items-center p-1.5 bg-gray-50 rounded">
                                    <kbd class="px-1.5 py-0.5 bg-white border border-gray-300 rounded font-mono text-xs mr-2 min-w-[40px] text-center">{pk.key}</kbd>
                                    <span class="text-gray-700 text-xs">{pk.desc}</span>
                                </div>
                            {/each}
                        </div>
                    </div>

                    <div>
                        <h3 class="text-xs font-bold uppercase tracking-wide text-gray-500 mb-2">From this Sheet</h3>
                        <div class="space-y-1">
                            <div class="flex items-center p-1.5 bg-indigo-50 rounded border border-indigo-100">
                                <kbd class="px-1.5 py-0.5 bg-white border border-indigo-300 rounded font-mono text-xs mr-2 min-w-[40px] text-center">4</kbd>
                                <span class="text-gray-700 text-xs">Open services menu (SAD / ASR)</span>
                            </div>
                            <div class="flex items-center p-1.5 bg-indigo-50 rounded border border-indigo-100">
                                <kbd class="px-1.5 py-0.5 bg-white border border-indigo-300 rounded font-mono text-xs mr-2 min-w-[40px] text-center">5</kbd>
                                <span class="text-gray-700 text-xs">Open annotation guidelines (new window)</span>
                            </div>
                            <div class="flex items-center p-1.5 bg-indigo-50 rounded border border-indigo-100">
                                <kbd class="px-1.5 py-0.5 bg-white border border-indigo-300 rounded font-mono text-xs mr-2 min-w-[40px] text-center">6</kbd>
                                <span class="text-gray-700 text-xs">View bindings as a QWERTY keyboard</span>
                            </div>
                        </div>
                    </div>
                </section>
            </div>
        </div>
    {/snippet}
</BaseDialog>

<ServicesDialog
    bind:dialogRef={dialog_services}
    onKeydown={dialog_services_keydown}
/>

<ASRDialog
    bind:dialogRef={dialog_asr}
    addWhich={add_which}
/>

<KeyboardCheatSheetDialog
    bind:dialogRef={dialog_keyboard}
/>

<AsrSpanDialog
    bind:this={span_dialog}
    bind:dialogRef={dialog_span}
    onRun={start_asr}
    onCancel={cancel_asr}
/>
