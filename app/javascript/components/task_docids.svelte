<script>
    // The list of documents a task hands to every one of its users.
    //
    // The SameListForEveryone workflow reads it: when a user comes for work
    // with nothing left to do, it creates a kit for each document on this list
    // they haven't had yet. Every other workflow ignores the list, which the
    // panel says rather than hiding — a list is usually entered before the
    // workflow is switched over.
    import { get_task_docids, set_task_docids } from './controllers';
    import { btn } from './buttons';

    let { task_id } = $props();

    let text = $state('');       // what's in the box
    let stored = $state(null);   // what came back from the server
    let workflow = $state(null);
    let used_by_workflow = $state(false);
    let error = $state(null);
    let saving = $state(false);
    let loaded_for = $state(null);

    // The count as typed, so it moves while the list is being edited.
    const typed_count = $derived(text.split('\n').map( (x) => x.trim() ).filter(Boolean).length);
    const changed = $derived(stored !== null && text !== stored);

    function apply(data){
        if(!data || data.error){ error = (data && data.error) || 'no response'; return; }
        error = null;
        stored = data.text ?? '';
        text = stored;
        workflow = data.workflow;
        used_by_workflow = !!data.used_by_workflow;
    }

    $effect(() => {
        if(task_id == null || loaded_for === task_id) return;
        loaded_for = task_id;
        get_task_docids(task_id).then(apply);
    });

    function save(){
        saving = true;
        // What comes back is what was kept — blank lines and repeats dropped —
        // so the box ends up showing the list as stored, not as typed.
        set_task_docids(task_id, text).then(apply).finally( () => saving = false );
    }
</script>

<div class="p-3 space-y-3">
    <div>
        <h4 class="font-medium">Documents for every user</h4>
        <p class="text-sm text-gray-600">
            One docid per line — whatever this task's kits use as their source. Every user of
            this task gets a kit for each of these, created when they run out of work. A user
            who already had one doesn't get it again.
        </p>
    </div>

    {#if workflow && !used_by_workflow}
        <div class="text-sm bg-amber-50 border border-amber-200 rounded p-2 text-amber-900">
            This task's workflow is <span class="font-mono">{workflow}</span>, which doesn't read
            this list. Switch it to <span class="font-mono">SameListForEveryone</span> on the Task
            Info tab for these to be handed out.
        </div>
    {/if}

    {#if error}
        <div class="text-sm bg-red-50 border border-red-200 rounded p-2 text-red-800">{error}</div>
    {/if}

    <textarea
        bind:value={text}
        rows="12"
        spellcheck="false"
        placeholder="s3://my-bucket/recordings/0972745F…_passage_reading.json"
        class="block w-full rounded-md border border-gray-300 p-2 font-mono text-sm shadow-sm focus:ring-indigo-500 focus:border-indigo-500 box-border"
    ></textarea>

    <div class="flex items-center gap-3">
        <button class="{btn}" onclick={save} disabled={saving || !changed}>
            {saving ? 'Saving…' : 'Save list'}
        </button>
        <span class="text-sm text-gray-600">
            {typed_count} document{typed_count === 1 ? '' : 's'}
            {#if changed}<span class="text-amber-700">— unsaved</span>{/if}
        </span>
    </div>
</div>
