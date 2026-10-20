<script>
    import { run } from 'svelte/legacy';
    import { tick } from 'svelte';
    import { flash, ok_reload } from './helpers';
    import { Label } from "$lib/components/ui/label";
    import { Input } from "$lib/components/ui/input";
    import { Textarea } from "$lib/components/ui/textarea";
    import * as Select from "$lib/components/ui/select";
    import { Checkbox } from "$lib/components/ui/checkbox";
    let {
        label,
        key,
        value,
        values,
        type,
        att,
        urlf = null,
        meta = false,
        wrap = false,
        required = false,
        split = null,
        idk = 'id',
        disabled = false,
        reload
    } = $props();
    if(split && value) value = value.join(split);
    const id = Math.random().toString(36).substring(2);
    function patch(k, v){
        if(!urlf) return;
        let x = {};
        if(split) v = v.split(split);
        if(att){
            if(meta){
                x.meta = {};
                if(v[idk] == 0) x.meta[k] = '';
                else            x.meta[k] = v[idk];
            }
            else{
                x[k] = v[idk];
            }
        }
        else{
            if(meta == 'meta'){
                x.meta = {};
                x.meta[k] = v;
            }
            else if(meta == 'constraints'){
                x.constraints = {};
                x.constraints[k] = v;
            }
            else{
                // x[k] = k; why was checkbox like this?
                x[k] = v;
            }
        }
        if(wrap){
            const y = {};
            y[wrap] = x;
            x = y;
        }
        urlf(x).then(x => reload ? ok_reload(x, reload) : flash(x, k));
    }
    let first = true;
    let timeout;
    function update(x){
        if(first) return;
        if(type == 'input' || type == 'textarea'){
            if(timeout) clearTimeout(timeout);
            timeout = setTimeout( () => patch(key, x) , 1000 );
        }
        else{
            patch(key, x);
        }
    }
    tick().then( () => first = false );
    let v = $state(value);
    let vv = $state( { value: value } ); // weirdness with Select
    $effect(() => update(v));
    $effect(() => update(vv.value));

    // const trigger = $derived( values.find((f) => f.name == v.name)?.name ?? "Select" );
</script>

{#if type != 'checkbox'}
    <Label for="patch-{id}">{label}</Label>
{/if}
{#if type == 'input'}
    <Input id="patch-{id}" type="text" bind:value={v} />
{:else if type == 'textarea'}
    <Textarea id="patch-{id}" bind:value={v} />
{:else if type == 'select'}
    <Select.Root id="patch-{id}" bind:value={vv} type="single">
        <Select.Trigger class="w">
            {att ? vv.value[att] : vv.value}
        </Select.Trigger>
        <Select.Content >
            {#each values as x}
                <Select.Item value={x ? { value: x } : ""} label={att ? x[att] : x} />
            {/each}
        </Select.Content>
    </Select.Root>
{:else if type == 'checkbox'}
    <div class="flex items-center space-x-2 mt-2">
        <Checkbox id="patch-{id}" aria-labelledby="patch-label-{id}" bind:checked={v} {disabled} />
        <Label
            id="patch-label-{id}"
            for="patch-{id}"
            class="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
        >
            {label}
        </Label>
    </div>
{/if}
