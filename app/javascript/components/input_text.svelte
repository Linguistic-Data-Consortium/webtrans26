<script>
    import { run } from 'svelte/legacy';

    import { tick } from 'svelte';
    import { flash } from './helpers';
    /**
     * @typedef {Object} Props
     * @property {any} label
     * @property {any} key
     * @property {any} [value]
     * @property {boolean} [textarea]
     * @property {any} [urlf]
     * @property {boolean} [meta]
     * @property {boolean} [wrap]
     * @property {boolean} [required]
     * @property {any} [split]
     */

    /** @type {Props} */
    let {
        label,
        key,
        value = $bindable(),
        textarea = false,
        urlf = null,
        meta = false,
        wrap = false,
        required = false,
        split = null
    } = $props();
    if(split && value) value = value.join(split);
    const id = Math.random().toString(36).substring(2);
    function patch(k, v){
        console.log(urlf)
        if(!urlf){
            return;
        }
        let x = {};
        if(split){
            v = v.split(split);
        }
        if(meta == 'meta'){
            x.meta = {};
            x.meta[k] = v;
        }
        if(meta == 'constraints'){
            x.constraints = {};
            x.constraints[k] = v;
        }
        else{
            x[k] = v;
        }
        if(wrap){
            const y = {};
            y[wrap] = x;
            x = y;
        }
        urlf(x).then(
            x => flash(x, k)
        );
    }
    let first = true;
    let timeout;
    function update(x){
        if(first){
            return;
        }
        if(timeout){
            clearTimeout(timeout);
        }
        timeout = setTimeout( () => patch( key, value ) , 1000 );
    }
    run(() => {
        update(value);
    });
    tick().then( () => first = false );
</script>

<div class="pb-4">
    <div class="form-group-header">
        <label for="input-{id}">{label}</label>
    </div>
    <div class="form-group-body">
        {#if textarea}
            <textarea
                id="input-{id}"
                class="focus:ring-indigo-500 focus:border-indigo-500 flex-1 block w-full rounded-md border-gray-300"
                bind:value={value}
                aria-describedby="input-{id}-validation"
            ></textarea>
        {:else}
            <input
                id="input-{id}"
                class="focus:ring-indigo-500 focus:border-indigo-500 flex-1 block w-full rounded-md border-gray-300"
                type=text
                bind:value={value}
                aria-describedby="input-{id}-validation"
            />
        {/if}
    </div>
</div>
