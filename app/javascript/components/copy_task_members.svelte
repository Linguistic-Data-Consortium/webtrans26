<script>
    // Add every member of another task to this one.
    //
    // The list offered is the tasks the signed-in user administers, which is
    // the same rule that lets them add a member by hand. Each carries its
    // member count, so the choice is made knowing the size of it.
    //
    // Membership only: someone who administers the other task doesn't become
    // an admin here, and their state starts fresh — the same rows Add Member
    // would have made, one at a time.
    import { get_source_tasks, copy_task_members } from './controllers';
    import { btn } from './buttons';

    let { task_id, reload = null } = $props();

    let tasks = $state(null);
    let filter = $state('');
    let chosen = $state(null);
    let result = $state(null);
    let error = $state(null);
    let busy = $state(false);
    let loaded_for = $state(null);

    const shown = $derived(
        (tasks || []).filter( (t) => {
            if(!filter) return true;
            const hay = `${t.name} ${t.project_name || ''}`.toLowerCase();
            return hay.includes(filter.toLowerCase());
        } )
    );

    $effect(() => {
        if(task_id == null || loaded_for === task_id) return;
        loaded_for = task_id;
        result = null;
        get_source_tasks(task_id).then( (data) => {
            if(data && data.error){ error = data.error; tasks = []; }
            else { error = null; tasks = data || []; }
        } );
    });

    function copy(){
        if(!chosen) return;
        busy = true;
        copy_task_members(task_id, chosen.id).then( (data) => {
            if(data && data.error){ error = data.error; result = null; }
            else { error = null; result = data; if(reload) reload(); }
        } ).finally( () => busy = false );
    }
</script>

<div class="space-y-3 min-w-0">
    {#if error}
        <div class="text-sm bg-red-50 border border-red-200 rounded p-2 text-red-800">{error}</div>
    {/if}

    {#if tasks === null}
        <div class="text-sm text-gray-600">Loading tasks…</div>
    {:else if tasks.length === 0}
        <div class="text-sm text-gray-600">
            There's no other task you administer to copy from.
        </div>
    {:else}
        <input
            type="text"
            bind:value={filter}
            placeholder="filter by task or project"
            class="block w-full rounded-md border border-gray-300 p-2 text-sm shadow-sm focus:ring-indigo-500 focus:border-indigo-500"
        />
        <div class="max-h-64 overflow-auto border border-gray-200 rounded">
            {#each shown as t (t.id)}
                <button
                    type="button"
                    class="w-full text-left px-2 py-1 text-sm border-b border-gray-100 last:border-0
                           {chosen && chosen.id === t.id ? 'bg-indigo-50 font-medium' : 'hover:bg-gray-50'}"
                    onclick={() => { chosen = t; result = null; }}
                >
                    <span>{t.name}</span>
                    <span class="text-gray-500">— {t.project_name}</span>
                    <span class="text-gray-500">({t.member_count} member{t.member_count === 1 ? '' : 's'})</span>
                </button>
            {/each}
            {#if shown.length === 0}
                <div class="px-2 py-1 text-sm text-gray-500">nothing matches</div>
            {/if}
        </div>

        <div class="flex items-center gap-3">
            <button class="{btn}" onclick={copy} disabled={!chosen || busy}>
                {busy ? 'Adding…' : chosen ? `Add ${chosen.member_count} from ${chosen.name}` : 'Choose a task'}
            </button>
        </div>
    {/if}

    {#if result}
        <div class="text-sm bg-green-50 border border-green-200 rounded p-2 text-green-900">
            <div>{result.ok}</div>
            {#if result.added?.length}
                <div class="mt-1 text-xs">added: {result.added.join(', ')}</div>
            {/if}
            {#if result.skipped?.length}
                <div class="mt-1 text-xs text-green-800">already members: {result.skipped.join(', ')}</div>
            {/if}
        </div>
    {/if}
</div>
