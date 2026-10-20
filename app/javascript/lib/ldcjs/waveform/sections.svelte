<script>
    import { onDestroy } from 'svelte';
    import { btn, cbtn, dbtn, btn1 } from '../work/buttons';
    import { settings } from './stores';
    import { transcript } from './transcript.svelte';
    import {
        delete_section
    } from './modification1';
    import { DeleteSectionDialog } from './dialogs';
    import Table from '../work/table.svelte';
    let { update_segments } = $props();
    let dialog_delete_section = $state();

    let sections_table = $state();
    // begr / endr: the section's span in seconds, resolved from its anchors.
    const sections_table_columns = [
        [ 'Name', 'name', 'col-4' ],
        [ 'Begin', 'begr', 'col-4' ],
        [ 'End', 'endr', 'col-4' ]
    ];
    const sections_table_rows = $derived(transcript.sections);
    let sections_open = $state(false);
    const unsubscribe_settings = settings.subscribe( (x) => {
        // experimental = x.experimental;
        // if(dialog_settings){
        //     if(x.open) dialog_settings.showModal();
        //     else       dialog_settings.close();
        // }
        sections_open = x.sections_open;
        // for( let y of dialog_settings_a ){
        //     let k = y[0];
        //     let v = y[1];
        //     dialog_settings_h[k] = x[k];
        // }
    });
    onDestroy( () => {
        unsubscribe_sections();
        unsubscribe_settings();
    } );
    function close_sections(){
        settings.update( (x) => { 
            x.sections_open = false;
            return x;
        } );
    }
    function delete_selected_section(){
        let id = sections_table.get_selected_key();
        if(id){
            delete_section(sections_table.get_selected_key(), update_segments);
        }
        else{
            alert('no section selected');
        }
        dialog_delete_section.close();
    }
</script>

<DeleteSectionDialog bind:dialogRef={dialog_delete_section} onConfirm={delete_selected_section} {btn} {dbtn} />

{#if sections_open}
    <div class="sections">
        <div class="flex justify-around m-2">
            <div><button class="{btn}" onclick={close_sections}>Close</button></div>
            <div><button class="{dbtn}" onclick={() => dialog_delete_section.showModal()}>Delete Section</button></div>
        </div>
        <Table
            bind:this={sections_table}
            columns={sections_table_columns}
            rows={sections_table_rows}
            use_filter={true}
            key_column="list_item_id"
            selectedf={() => null}
        />
    </div>
{/if}
