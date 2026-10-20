<script>
    import { createEventDispatcher } from 'svelte';
    const dispatch = createEventDispatcher();
    import { btn } from './work/buttons'
    export let name = null;
    export let title;
    export let h = null;
    export let b = null;
    export let delegate = null;
    export let f = null;
    export let ff = null;
    export let btnc = null;
    export let icon = null;
    export let buttons = null;
    let unused = name && btnc && icon;
    function callf(){
        if(delegate){
            delegate[f]();
        }
        else{
            ff();
        }
    }
    let btn_class = b == "DELETE" ? "btn-danger" : "btn-primary";
    let btn_class2 = b == "DELETE" ? "btn-danger" : "";

    export let open = false;
    function close(){
        open = false;
        dispatch('close');
    }
    function closef(f){
        f();
        close();
    }
    export let width = "w-full";
    export let start_with_button = true;
</script>

{#if open}
    <!-- <div>
        {h}
    </div>
    <!-- This example requires Tailwind CSS v2.0+ -->
    <div class="fixed z-20 inset-0 overflow-y-auto" aria-labelledby="modal-title" role="dialog" aria-modal="true">
      <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
        <!--
          Background overlay, show/hide based on modal state.

          Entering: "ease-out duration-300"
            From: "opacity-0"
            To: "opacity-100"
          Leaving: "ease-in duration-200"
            From: "opacity-100"
            To: "opacity-0"
        -->
        <div on:click={close} class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity" aria-hidden="true"></div>

        <!-- This element is to trick the browser into centering the modal contents. -->
        <span class="hidden sm:inline-block sm:align-middle sm:h-screen" aria-hidden="true">&#8203;</span>

        <!--
          Modal panel, show/hide based on modal state.

          Entering: "ease-out duration-300"
            From: "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
            To: "opacity-100 translate-y-0 sm:scale-100"
          Leaving: "ease-in duration-200"
            From: "opacity-100 translate-y-0 sm:scale-100"
            To: "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
        -->
        <div class="inline-block align-bottom bg-white rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-4xl sm:{width}">
          <div class="bg-white px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
              <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left">
                <h4 class="text-lg font-medium leading-6 text-gray-900">
                  {title}
                </h4>
                <div class="mt-2">
                    {#if h}
                      <p class="text-sm text-gray-500">
                        {h}
                      </p>
                    {/if}
                  {#if $$slots.body}
                      <div>
                          <slot name=body></slot>
                      </div>
                  {/if}
                </div>
              </div>
          </div>
          <div class="bg-gray-50 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
            {#if buttons}
                {#each buttons as button}
                    <div class="ml-4">
                        {#if button[2]}
                            <button type="button" on:click={ () => closef(button[2]) } class={button[1]}>{button[0]}</button>
                        {:else}
                            <button type="button" on:click={ close                   } class={button[1]}>{button[0]}</button>
                        {/if}
                    </div>
                {/each}
            {/if}
          </div>
        </div>
      </div>
    </div>
{:else if start_with_button}
    <button class={btn} on:click={ () => open = true }>
        <slot name=summary>
            Click
        </slot>
    </button>
{/if}
