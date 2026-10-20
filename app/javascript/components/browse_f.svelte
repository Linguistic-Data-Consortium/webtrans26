<script>
  import { run } from 'svelte/legacy';

    import * as Table from "$lib/components/ui/table";
    import * as Select from "$lib/components/ui/select";
    import * as Tabs from "$lib/components/ui/tabs";
    import * as Dialog from "$lib/components/ui/dialog";
    import { Button, buttonVariants } from "$lib/components/ui/button";
    import Spinner from './spinner.svelte';
    import { get_open_tasks } from './browse_helper';
    import Table2 from '../lib/ldcjs/work/table.svelte';
    import Help from './help.svelte';
    import { getp } from "../lib/ldcjs/getp";
    import Buckets from './buckets.svelte';

  let {
    help,
    admin,
    portal_manager,
    project_manager,
    p
  } = $props();
    // let tasksp = p;
    let task_id = $state(0);
    p.then( (x) => console.log(x))

    let pages = [
        [ 'Your Uploads',  'all',    'files you uploaded' ],
        [ 'All Uploads',   'all',    'all uploaded files' ],
        [ 'Transcripts',   'all',    'kits created from uploads' ],
        [ 'Buckets',       'admin',  'available buckets' ],
    ];




    let columns1 = [
        [ 'Source', 'source_id', 'col-1' ],
        [ 'Filename', 'filename', 'col-3' ],
        [ 'Key', 'key', 'col-2' ],
        [ 'User', 'user', 'col-1' ],
        [ 'Task', 'task', 'col-2' ]
    ];
    let p1 = $state(Promise.resolve([]));
    let columns2 = [
        [ 'Task', 'task', 'col-2' ],
        // [ 'Source', 'source_id', 'col-1' ],
        // [ 'Type', 'type', 'col-1' ],
        [ 'Filename', 'filename', 'col-3' ],
        // [ 'Key', 'key', 'col-2' ],
        // [ 'Last Edited by', 'kit_user', 'col-1' ],
        [ 'Uploaded By', 'user', 'col-1' ]
    ];
    let p2 = $state(Promise.resolve([]));
    let columns3 = [
        [ 'Task', 'task', 'col-2' ],
        [ 'Kit', 'uid', 'col-2' ],
        // [ 'Source', 'source_id', 'col-1' ],
        // [ 'Type', 'type', 'col-1' ],
        [ 'Filename', 'filename', 'col-2' ],
        [ 'Name', 'name', 'col-2' ],
        [ 'State', 'state', 'col-1' ],
        [ 'Last Edited by', 'kit_user', 'col-1' ]
        // [ 'Uploaded By', 'user', 'col-1' ],
    ];
    let p3 = $state(Promise.resolve([]));


    let your_uploads = [];
    let open_tasks = {};
    let all_uploads = [];
    let kits = [];
    function tabs(x){
        switch(x){
            case 'your':
                p1 = getp("/browser?blobs=audio").then( x => your_uploads = x );
                break;
            case 'all':
                p2 = p.then( (x) => get_open_tasks(x, open_tasks, true) ).then( x => all_uploads = x );
                break;
            case 'transcripts':
                p3 = p.then( (x) => get_open_tasks(x, open_tasks, false) ).then( x => kits = x );
                break;
        }
    }

    let pp = $derived(getp("/sources/get_upload?task_id=" + task_id));

    
    let object_id1 = $state();
    let object_index1 = $state();
    function create(){
        console.log(object_index1);
        const path = `/kits_new?open=${object_index1[object_id1].source_id}&task_id=${object_index1[object_id1].task_id}&filename=${object_index1[object_id1].filename}`
        getp(path).then( () => window.location = open_tasks[selected_task_id1].work_path );
    }
    let open_kit_uid1 = $state();
    let selected_task_id1 = $state();
    run(() => {
        if(object_id1){
            selected_task_id1 = object_index1[object_id1].task_id;
            open_kit_uid1 = open_tasks[selected_task_id1].has_kit;
        }
    });




    let object_id2 = $state();
    let object_index2 = $state();
    let block = $state();
    let ppp = Promise.resolve();
    function goto(){
        block = true;
        console.log(open_tasks);
        // if(!allow_goto) return;
        // getp("/kits_new?goto=" + object_index2[object_id2].id)
        // .then( () => window.location = work_paths[selected_task_id2] );
        if(allow_goto){
            let pp = getp("/kits_new?goto=" + object_index2[object_id2].id);
        }
        ppp.then( console.log(open_tasks[selected_task_id2]) );
        ppp.then( () => window.location = open_tasks[selected_task_id2].work_path );
    }
    let allow_return = $state();
    let allow_goto = $state();
    let open_kit_uid2 = $state();
    let selected_task_id2 = $state();
    run(() => {
        if(object_id2){
            selected_task_id2 = object_index2[object_id2].task_id;
            open_kit_uid2 = open_tasks[selected_task_id2].has_kit;

            // open_kit = open_tasks[object_index[object_id].task_id];
            allow_return = object_index2[object_id2].uid == open_kit_uid2;
            allow_goto =  !open_kit_uid2 && object_index2[object_id2].state == 'done';
        }
    });
</script>

<Help {help}>
    {#snippet content()}
    <div >
          <p>
              The Browse feature allows you to upload audio files and collaborate on transcripts.
              Uploaded audio files, as well as their transcripts, can be shared among the group.
          </p>
          <p>
              <!-- {@html marked.parse("You can upload under **Your Uploads**, create new transcripts under **All Uploads**, and access transcripts under **Transcripts**")} -->
          </p>
      </div>
  {/snippet}
</Help>
<!-- <div class=upload4>
  <p>
    After uploading, a code snippet is shown for creating a url
    for that file in Ruby code.  The part that varies is the integer source
    id.  This id can also be found on the Files tab.  In an erb file,
    the ruby code would have to be within &lt;%= %&gt; tags.  In a haml file, the
    ruby code would have to follow = (and appropripate indentation).
  </p>
</div> -->
<!-- <Help {help}>
    <div slot=content>
        <p>
            If you're a member of a browesable task, you can upload audio files into that task.
            The table shows the files you've uploaded.
        </p>
    </div>
</Help> -->
<!-- <Help {help}>
    <div slot=content>
        <p>
            If you're a member of a browesable task, this table shows all the uploaded audio files (uploaded by you or by others).
        </p>
        <p>
            You can create a new transcript from any of these audio files, as long as you don't already
            have an open transcript in that task.
        </p>
    </div>
</Help> -->
<!-- <Help {help}>
    <div slot=content>
        <p>
            This table shows transcripts created by the group, and you can open any one of them,
            as long as it's not already open by someone else.
        </p>
        <p>
            If you have one open, you can return to it here (as well as from the Work tab).
        </p>
    </div>
</Help> -->


<Tabs.Root value="x" class="w-full justify-center" onValueChange={tabs}>
    <Tabs.List>
        <Tabs.Trigger value="your">Your Uploads</Tabs.Trigger>
        <Tabs.Trigger value="all">All Uploads</Tabs.Trigger>
        <Tabs.Trigger value="transcripts">Transcripts</Tabs.Trigger>
        {#if admin}
            <Tabs.Trigger value="buckets">Buckets</Tabs.Trigger>
        {/if}
    </Tabs.List>
    <Tabs.Content value="your">
        <div class="flex flex-row-reverse w-full">
            <Dialog.Root>
                <Dialog.Trigger class={buttonVariants({ variant: "outline" })}>Upload File</Dialog.Trigger>
                <Dialog.Content>
                    <Dialog.Header>
                        <Dialog.Title>Upload into one of these tasks</Dialog.Title>
                        <!-- <Dialog.Description>
                            This action cannot be undone. This will permanently delete your account
                            and remove your data from our servers.
                        </Dialog.Description> -->
                    </Dialog.Header>
                    {#await p}
                        loading...
                    {:then v}
                    <!-- {JSON.stringify(v[0])} -->
                    {#if v[0].length}
                        <label for=x>Project/Task</label>
                        <Select.Root
                            onSelectedChange={x => task_id = x.value}
                        >
                        <Select.Trigger class="w-96">
                            Task
                        </Select.Trigger>
                        <Select.Content class="w-full">
                            {#each v[0] as task}
                                {#if task.free}
                                    <Select.Item value={task.task_id}>
                                        {task.project} / {task.task}
                                    </Select.Item>
                                {/if}
                            {/each}
                        </Select.Content>
                        </Select.Root>
                        {#if task_id}
                            {#await pp}
                                <div class="mx-auto w-8 h-8"><Spinner /></div>
                            {:then v}
                                <div class="m-3">
                                    {@html v.html}
                                </div>
                            {/await}
                        {/if}
                    {:else}
                        <div>No tasks are available for upload</div>
                    {/if}
                    <!-- <select class="form-select" aria-label="Important decision">
                        <option>Select</option>
                        <option value="option 2">Option 2</option>
                    </select> -->
                    {/await}
                </Dialog.Content>
            </Dialog.Root>
        </div>
        {#await p1}
            <div class="mx-auto w-8 h-8"><Spinner /></div>
        {:then rows}
            <Table2 columns={columns1} {rows} use_filter={true} key_column=source_id height=500 />
        {/await}
        <!-- <Table.Root>
            <Table.Caption>Your uploaded audio files</Table.Caption>
            <Table.Header>
                <Table.Row>
                    <Table.Head class="w-[100px]">Source</Table.Head>
                    <Table.Head class="w-[100px]">Filename</Table.Head>
                    <Table.Head>Key</Table.Head>
                    <Table.Head>User</Table.Head>
                    <Table.Head class="text-right">Task</Table.Head>
                </Table.Row>
            </Table.Header>
            <Table.Body>
                {#each your_uploads as audio}
                    <Table.Row>
                        <Table.Cell class="font-medium">{audio.source_id}</Table.Cell>
                        <Table.Cell class="font-medium">{audio.filename}</Table.Cell>
                        <Table.Cell>{audio.key}</Table.Cell>
                        <Table.Cell>{audio.user}</Table.Cell>
                        <Table.Cell class="text-right">{audio.task}</Table.Cell>
                    </Table.Row>
                {/each}
            </Table.Body>
        </Table.Root> -->
    </Tabs.Content>
    <Tabs.Content value="all">
        {#await p}
            <div class="mx-auto w-8 h-8"><Spinner /></div>
        {:then vv}
            <div class="flex justify-around">
                <div>Tasks with Uploaded Files</div>
                {#if object_id1}
                    <Button
                        variant="secondary"
                        on:click={create}
                        disabled={open_kit_uid1 ? true : false}
                    >
                        Create Transcript
                            {#if open_kit_uid1}
                                (disabled because transcript {open_kit_uid1} is open)
                            {/if}
                    </Button>
                {/if}
            </div>
            {#await p2}
                <div class="mx-auto w-8 h-8"><Spinner /></div>
            {:then v}
                <!-- {JSON.stringify(v)} -->
                <div class="float-right p-2">
                    <!-- {v.name} {object_id} -->
                </div>
                <Table2 bind:selected={object_id1} indexf={x => object_index1 = x} columns={columns2} rows={v} use_filter={true} key_column=uid height="96" />
            {/await}
        {/await}
        <!-- <Table.Root>
            <Table.Caption>All Uploads</Table.Caption>
            <Table.Header>
                <Table.Row>
                    <Table.Head>Task</Table.Head>
                    <Table.Head>Filename</Table.Head>
                    <Table.Head>Uploaded By</Table.Head>
                </Table.Row>
            </Table.Header>
            <Table.Body>
                {#each all_uploads as audio}
                    <Table.Row>
                        <Table.Cell>{audio.task}</Table.Cell>
                        <Table.Cell class="font-medium">{audio.filename}</Table.Cell>
                        <Table.Cell>{audio.user}</Table.Cell>
                    </Table.Row>
                {/each}
            </Table.Body>
        </Table.Root> -->
    </Tabs.Content>
    <Tabs.Content value="transcripts">
        {#await p}
            <div class="mx-auto w-8 h-8"><Spinner /></div>
        {:then vv}
            <!-- {JSON.stringify(vv)} -->
            <div class="flex justify-around">
                <div>Tasks with Uploaded Files</div>
                {#if object_id2}
                    {#if block}
                        <div class="mx-auto w-8 h-8"><Spinner /></div>
                    {:else}
                        <Button
                            variant="secondary"
                            on:click={goto}
                            disabled={!allow_return && !allow_goto}
                        >
                            {#if allow_return}
                                Return to Transcript
                            {:else if allow_goto}
                                Open Transcript
                            {:else if open_kit_uid2}
                                {open_kit_uid2} is open
                            {:else}
                                this transcript is open
                            {/if}
                        </Button>
                    {/if}
                {/if}
            </div>
            {#await p3}
                <div class="mx-auto w-8 h-8"><Spinner /></div>
            {:then v}
                <!-- {JSON.stringify(v)} -->
                <div class="float-right p-2">
                    <!-- {v.name} {object_id} -->
                </div>
                <Table2 bind:selected={object_id2} indexf={x => object_index2 = x} columns={columns3} rows={v} use_filter={true} key_column=uid height=400 />
            {/await}
        {/await}
        <!-- <Table.Root>
          <Table.Caption>A list of your recent invoices.</Table.Caption>
          <Table.Header>
            <Table.Row>
              <Table.Head>Task</Table.Head>
              <Table.Head>Kit</Table.Head>
              <Table.Head>Filename</Table.Head>
              <Table.Head>Name</Table.Head>
              <Table.Head>State</Table.Head>
              <Table.Head>Last Edited by</Table.Head>
            </Table.Row>
          </Table.Header>
          <Table.Body>
                    {#each kits as kit}
                    <Table.Row>
                        <Table.Cell>{kit.task}</Table.Cell>
                        <Table.Cell>{kit.uid}</Table.Cell>
                        <Table.Cell>{kit.filename}</Table.Cell>
                        <Table.Cell>{kit.name}</Table.Cell>
                        <Table.Cell>{kit.state}</Table.Cell>
                        <Table.Cell>{kit.kit_user}</Table.Cell>
                    </Table.Row>
                {/each}
          </Table.Body>
        </Table.Root> -->
    </Tabs.Content>
    {#if admin}
        <Tabs.Content value="buckets">
            <Buckets
                {help}
                {admin}
                {portal_manager}
                {project_manager}
                p_for_bucket={p}
            />
        </Tabs.Content>
    {/if}
</Tabs.Root>
