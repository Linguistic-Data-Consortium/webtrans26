<script>
    let { help, content } = $props();
</script>

<style>
</style>

{#if help}
    <div class="text-center bg-blue-200 my-2 rounded-full">
    	{#if content}{@render content()}{:else}empty{/if}
    </div>
{/if}
