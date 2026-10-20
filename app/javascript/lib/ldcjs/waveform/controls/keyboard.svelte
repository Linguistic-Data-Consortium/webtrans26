<script>
    import { onMount } from 'svelte';
    import { event } from '../../../../guides/guide';
    import { mouse, key } from '../stores';
    let {
    } = $props();
    let keyboard;
    export function keyboard_focus(e){
        e.preventDefault();
        keyboard.focus();
    }
    function mouseup(e){
        const x = e.clientX - this.getBoundingClientRect().left;
        mouse.set({ x: x });
    }
    function keydown(e){
        e.preventDefault();
        key.set(e);
    }
    export function focus(){
        keyboard.focus();
        setTimeout(() => keyboard.focus(), 100)
    }
    onMount(() => {
        focus();
    });
</script>

<style>
    .keyboard:focus {
        color: green;
        box-shadow: inset 0 0 5px green;
        outline: none;
        background-color: white;
    }
</style>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="col-span-2 float-left" onmouseleave={mouseup} >
    <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div bind:this={keyboard} onkeydown={keydown} use:event.dispatch={'drew_keyboard_icon'} class="keyboard text-center mx-auto" style="width: 30px" tabindex="0">
        <svg aria-hidden="true" focusable="false" data-prefix="fas" data-icon="keyboard" class="svg-inline--fa fa-keyboard fa-w-18" role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 576 512"><path fill="currentColor" d="M528 448H48c-26.51 0-48-21.49-48-48V112c0-26.51 21.49-48 48-48h480c26.51 0 48 21.49 48 48v288c0 26.51-21.49 48-48 48zM128 180v-40c0-6.627-5.373-12-12-12H76c-6.627 0-12 5.373-12 12v40c0 6.627 5.373 12 12 12h40c6.627 0 12-5.373 12-12zm96 0v-40c0-6.627-5.373-12-12-12h-40c-6.627 0-12 5.373-12 12v40c0 6.627 5.373 12 12 12h40c6.627 0 12-5.373 12-12zm96 0v-40c0-6.627-5.373-12-12-12h-40c-6.627 0-12 5.373-12 12v40c0 6.627 5.373 12 12 12h40c6.627 0 12-5.373 12-12zm96 0v-40c0-6.627-5.373-12-12-12h-40c-6.627 0-12 5.373-12 12v40c0 6.627 5.373 12 12 12h40c6.627 0 12-5.373 12-12zm96 0v-40c0-6.627-5.373-12-12-12h-40c-6.627 0-12 5.373-12 12v40c0 6.627 5.373 12 12 12h40c6.627 0 12-5.373 12-12zm-336 96v-40c0-6.627-5.373-12-12-12h-40c-6.627 0-12 5.373-12 12v40c0 6.627 5.373 12 12 12h40c6.627 0 12-5.373 12-12zm96 0v-40c0-6.627-5.373-12-12-12h-40c-6.627 0-12 5.373-12 12v40c0 6.627 5.373 12 12 12h40c6.627 0 12-5.373 12-12zm96 0v-40c0-6.627-5.373-12-12-12h-40c-6.627 0-12 5.373-12 12v40c0 6.627 5.373 12 12 12h40c6.627 0 12-5.373 12-12zm96 0v-40c0-6.627-5.373-12-12-12h-40c-6.627 0-12 5.373-12 12v40c0 6.627 5.373 12 12 12h40c6.627 0 12-5.373 12-12zm-336 96v-40c0-6.627-5.373-12-12-12H76c-6.627 0-12 5.373-12 12v40c0 6.627 5.373 12 12 12h40c6.627 0 12-5.373 12-12zm288 0v-40c0-6.627-5.373-12-12-12H172c-6.627 0-12 5.373-12 12v40c0 6.627 5.373 12 12 12h232c6.627 0 12-5.373 12-12zm96 0v-40c0-6.627-5.373-12-12-12h-40c-6.627 0-12 5.373-12 12v40c0 6.627 5.373 12 12 12h40c6.627 0 12-5.373 12-12z"></path>
        </svg>
    </div>
</div>
