<script>
    import { onMount } from 'svelte';
	let { url, blob, filename } = $props();
    let audio;
    let src = $state();
    onMount(() => {
        audio.controls = true;
        src = blob ? URL.createObjectURL(blob) : url;
    });

    let duration = $state();
	let buffered = $state();
	let played = $state();
	let seekable = $state();
	let seeking = $state();
	let ended = $state();
	let currentTime = $state();
	let playbackRate = $state();
	let paused = $state();
	let volume = $state();
	let muted = $state();

</script>

<audio
    bind:this={audio}
    {src}
    bind:duration
	bind:buffered
	bind:played
	bind:seekable
	bind:seeking
	bind:ended
	bind:currentTime
	bind:playbackRate
	bind:paused
	bind:volume
	bind:muted
></audio>
<div>{duration} seconds</div>
<div><a href={src} download={filename}>download</a></div>
