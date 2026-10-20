<script>
    import { run } from 'svelte/legacy';

    import { tick } from 'svelte';
    import { flash } from './helpers';
    /**
     * @typedef {Object} Props
     * @property {any} urlf
     * @property {any} label
     * @property {any} key
     * @property {any} value
     * @property {any} values
     * @property {boolean} [att]
     * @property {string} [idk]
     * @property {boolean} [meta]
     */

    /** @type {Props} */
    let {
        urlf,
        label,
        key,
        value,
        values,
        att = false,
        idk = 'id',
        meta = false
    } = $props();
    const id = Math.random().toString(36).substring(2);
    function patch(k, v){
        if(!urlf){
            return;
        }
        let x = {};
        if(att){
            if(meta){
                x.meta = {};
                if(v[idk] == 0){
                    x.meta[k] = '';
                }
                else{
                    x.meta[k] = v[idk];
                }
            }
            else{
                x[k] = v[idk];
            }
        }
        else{
            if(meta){
                x.meta = {};
                x.meta[k] = v;
            }
            else{
                x[k] = v;
            }
        }
        urlf(x).then(
            x => flash(x, k)
        );
    }
    let first = true;
    function update(x){
        // alert('update ' + key + ' ' + JSON.stringify(value));
        if(first){
            return;
        }
        patch( key, value );
    }
    run(() => {
        update(value);
    });
    tick().then( () => first = false );
</script>

<div class="form-group">
    <div class="form-group-header">
        <label for="input-{id}">{label}</label>
    </div>
    <div class="form-group-body">
        {JSON.stringify(value)}
        <select
            id="input-{id}"
            class="focus:ring-indigo-500 focus:border-indigo-500 flex-1 block w-full rounded-md border-gray-300"
            bind:value={value}
            aria-describedby="input-{id}-validation"
        >
            {#each values as x}
                <option value={x}>{att ? x[att] : x}</option>
            {/each}
        </select>
    </div>
</div>
