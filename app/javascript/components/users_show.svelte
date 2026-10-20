<script>
    import { getp } from '../lib/ldcjs/getp';
    import Users from './users.svelte';
    import PageKeyControls from '../lib/page_key_controls.svelte';
    import GettingStartedGuide from '../lib/getting_started_guide.svelte';
    let p = getp(window.location);
    // p.then(x => console.log(x));

    const guide_binding = { key: 'g', desc: 'Open the getting-started guide' };
</script>

{#await p}
    loading...
{:then v}

    <Users {...v} />

    <GettingStartedGuide project_manager={v.project_manager} user_id={v.user_id} />

    <PageKeyControls extraBindings={[
        guide_binding,
        ...(v.admin ? [{ key: 'j', desc: 'Jump to readonly (admin)' }] : [])
    ]} />

{/await}
