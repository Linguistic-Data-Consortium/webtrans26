<script>
    let { v, clipped } = $props();

    let maxv = 0;
    if(v > maxv) maxv = v;
    let w = $state(v * 100);
    let x = $state(maxv * 100);
    let textx = $state((maxv + .1) * 100);
    let text = $state(Math.round(maxv * 10000) / 100);
    let fill = maxv > clipped ? 'red' : 'green';

    let localmaxv = $state(0);
    let timeout;
    
    $effect(() => {
        if(v > localmaxv){
            localmaxv = v;
            if(timeout) clearTimeout(timeout);
            timeout = setTimeout( () => localmaxv = 0, 3000 );
        }
    });
    let localx = $derived(localmaxv * 100);
    let localtextx = $derived((localmaxv + .1) * 100);
    let localtext = $derived(Math.round(localmaxv * 10000) / 100);
</script>

<style>
    #rect1 {
        fill: green;
        opacity: 0.5;
    }
    #rect3 {
        fill: white;
        stroke-width: 1;
        stroke: green;
    }
    .text1 {
        fill: green;
    }
</style>

<div>
    <svg width="100%" height="50">
        <rect id="rect3" width="100%" height="100%" />
        <rect id="rect1" width="{w}%" height="100%" />
        <rect id="rect2" width="10" height="100%" x="{x}%" fill={fill} />
        <rect id="rect4" width="5"  height="100%" x="{localx}%" fill="green" />
        <text class="text1" y="25"                x="{textx}%">{text}</text>
        <text class="text1" y="45"                x="{localtextx}%">{localtext}</text>
    </svg>
</div>

