<script>
  import { onMount } from 'svelte';
  import { btn } from "./buttons"
  import { getp } from 'https://cdn.jsdelivr.net/gh/Linguistic-Data-Consortium/ldcjs@0.0.3/src/getp.js'
  import Spinner from './spinner.svelte'
  let {
      user,
      kitid,
      kituid,
      locked
      // admin = false,
      // portal_manager = false,
      // project_manager = false
  } = $props();
  let header = $state(false);
  function d(){
    document.getElementsByClassName('keyboard')[0].focus();
  }
  function ee(){}
  function e(){
    header = false;
  }
  let header_input = $state();
  function open(){
    header = true;
  }
  // const data = document.getElementById('headerdata').dataset;
  function unlock(){
    getp(`/kits/${kitid}/unlock_tree`).then( (x) => {
      console.log(x);
      window.location.reload();
    } );
  }
  onMount( () => {
    const x = document.getElementById('oldsignout');
    const y = document.getElementById('newsignout');
    x.replaceWith(y);
  } );
</script>

<button class="fixed top-0 right-0 text-white" onclick={open}>header</button>

{#if header}
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="fixed top-0 h-10 bg-white right-0 z-30 w-10 bg-green-300" onclick={e} onkeydown={ee}></div>
    <div class="fixed top-0 h-10 bg-white left-0 right-0 z-20">
      <input bind:this={header_input} type=text class="bg-green-300 w-full border-none text-center focus:ring-0 text-white text-4xl"/>
    </div>
      <!-- <button class="fixed top-0 h-10 bg-white right-20" onclick={d}>d</button> -->
      <button class="fixed top-0 h-10 bg-white right-10" onclick={e}>e</button>
{:else}
    <div class="Header-item mr-10 p-4"><a href="/">Home</a></div>
    <div class="Header-item mr-10 p-4"><a href="/documentation">Documentation</a></div>
    <div class="Header-item mr-10 p-4"><div id="oldsignout"></div></div>
    <div class="Header-item mr-10 p-4">
      <div id="current_user_name" class="Label Label--green">{user}</div>
    </div>
    {#if kitid}
      <div class="Header-item mr-10 p-4">
        <div id="kit_uid" class="Label Label--green">{kituid}</div>
      </div>
      <div class="Header-item mr-10 p-4">
        <div id="task_name" class="Label Label--green"></div>
      </div>
      {#if locked}
        <div class="Header-item mr-10 p-4">
          <button class="{btn}" onclick={unlock}>unlock</button>
        </div>
      {/if}
      <div id="spinner">
        <Spinner />
      </div>
    {/if}
{/if}
