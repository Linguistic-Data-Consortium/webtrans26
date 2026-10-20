<script>
    import { run } from 'svelte/legacy';

    import { tick } from 'svelte';
    import { flash } from './helpers';
    /**
     * @typedef {Object} Props
     * @property {any} label
     * @property {any} key
     * @property {any} value
     * @property {any} urlf
     * @property {any} meta
     * @property {boolean} [disabled]
     */

    /** @type {Props} */
    let {
        label,
        key,
        value = $bindable(),
        urlf,
        meta,
        disabled = false
    } = $props();
    const id = Math.random().toString(36).substring(2);
    function patch(k, v){
        if(!urlf){
            return;
        }
        let x = {};
        if(meta == 'meta'){
            x.meta = {};
            x.meta[k] = v;
        }
        else if(meta == 'constraints'){
            x.constraints = {};
            x.constraints[k] = v;
        }
        else{
            x[k] = k;
        }
        urlf(x).then(
            x => flash(x, k)
        );
    }
    let first = true;
    function update(x){
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

<style>
input { display: inline-block; }
</style>

<div>
    <div>
        <label for="input-{id}">
            <input
                id="input-{id}"
                class="focus:ring-indigo-500 focus:border-indigo-500 h-4 w-4 border-gray-300"
                type="checkbox"
                bind:checked={value}
                aria-describedby="input-{id}-validation"
                {disabled}
            />
            {label}
        </label>
    </div>
</div>
