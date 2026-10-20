<script>
    import * as Dialog from "$lib/components/ui/dialog"
    import { btn, cbtn, dbtn, btn1 } from '../../work/buttons';
    import { activeo } from '../shared.svelte';
    let {
        segs,
        save_redactionf
    } = $props();
    let last_active_segment = $derived(activeo.active);
    let open_dialog_redact = $state(false);
    let redact_from = $state("");
    let redact_text = $state("");
    let redact_edit;
    // let redact_beg;
    // let redact_end;
    let redact_iid;
    // let dialog;
    export function redactcb(redact_mode){
        if(redact_mode){
            // last_speaker_used = penultimate_speaker_used;
            let rseg = get_redact_from();
            redact_from = rseg ? rseg.text : rseg;
            if(redact_from){
                // setTimeout(() => dialog.showModal(), 100);
                open_dialog_redact = true;
                redact_iid = (parseInt(rseg.iid) + 2).toString();
            }
            else{
                if(redact_from !== '') alert('no overlapping segment');
                // redact_mode = false;
            }
        }
        else{
            open_dialog_redact = false;
        }
    }
    function select_redaction(){
        let x = window.getSelection();
        if(x.type == 'Range' && x.anchorNode.textContent == x.focusNode.textContent){
            let b = x.anchorOffset;
            let e = x.focusOffset;
            if(b > e){
                let x = b;
                b = e;
                e = x;
            }
            for(let i = b; i > -1; i--){
                if(redact_from.substring(i, i+1).match(/\s/)) break;
                b = i;
            }
            for(let i = e; i < redact_from.length+1; i++){
                if(redact_from.substring(i-1, i).match(/[\s,.]/)) break;
                e = i;
            }
            // redact_beg = b;
            // redact_end = e - 1;
            redact_text = redact_from.substring(b, e);
            redact_edit = redact_from.substring(0, b) + '<redact>' + redact_text + '</redact>' + redact_from.substring(e);
        }
    }
    function save_redactionff(){
        open_dialog_redact = false;
        const value = redact_text;
        redact_text = "";
        save_redactionf(value, redact_iid, redact_edit);
    }
    function get_redact_from(){
        // if(!redact_mode) return "";
        let b = 0;
        let e = 0;
        let aseg;
        for(const x of segs){
            if(x.id == activeo.last_active_segment){
                aseg = x;
                // b = x.beg;
                // e = x.end;
                break;
            }
        }
        let rseg;
        for(const x of segs){
            if(x.id != activeo.last_active_segment && x.beg <= aseg.beg && x.end >= aseg.end){
                rseg = x;
                b = x.beg;
                e = x.end;
                break;
            }
        }
        if(!rseg) return false;
        redact_iid = (parseInt(rseg.iid) + 2).toString();
        return rseg;
    }
</script>


{#if open_dialog_redact}
    <div>Select Text</div>
    <div>use the mouse to double click or swipe</div>
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="m-9 p-9 border" onmouseup={select_redaction}>{redact_from}</div>
    <div><span class="mr-4">selection:</span><span class="border">{redact_text}</span></div>
    <div class="flex mt-3">
        <button class="{btn} mr-3" onclick={save_redactionff}>Save</button>
        <button class="{btn} mr-3" onclick={() => open_dialog_redact = false}>Cancel</button>
    </div>
{/if}
