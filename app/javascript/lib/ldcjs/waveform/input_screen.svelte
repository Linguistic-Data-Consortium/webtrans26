<script>
    let {
        controls
    } = $props();
    let input_screen_invisible = $state(true);
    let input_screen_title = $state('TITLE');
    let input_screen_input;
    let input_screen_keyboard;
    let input_screen_resolvef;
    function input_screen_open(h){
        input_screen_invisible = false;
        input_screen_title = h.title;
        input_screen_keyboard = h.keyboard;
        // remove = h.remove;
        setTimeout(function(){
            // document.getElementById('set_new_speaker_input').focus()
            input_screen_input.focus()
        }, 100);
        return new Promise( (resolve, reject) => input_screen_resolvef = resolve );
    }
    function input_screen_close(){
        input_screen_invisible = true;
        // document.getElementById('set_new_speaker_input').value = '';
        input_screen_value = '';
    }
    function input_screen_keydown(e){
        const f = input_screen_keyboard.handle(e, true);
        if(f) f();
    }

    let input_screen_value = $state('');
    export function input_screen_open_helper(h){
      const kb = h.keyboard;
      kb.map = { Enter: 'setf', Escape: 'escape' };
      kb.delegate.setf = function() {
        // id =  $('.crnt .Speaker').data().meta.id
        const v = input_screen_value;
        // document.querySelector('.keyboard').focus();
        controls.keyboard_focus();
        input_screen_close();
        input_screen_resolvef(v);
      };
      kb.delegate.escape = function() {
        // id =  $('.crnt .Speaker').data().meta.id
        // kb.reset();
        input_screen_close();
        input_screen_resolvef(null);
      };
      return input_screen_open(h);
    }
</script>
<!-- svelte-ignore a11y_no_noninteractive_tabindex -->
<div class="shadow-xl bg-white border-2 rounded fixed right-24 top-48 opacity-100 z-10" class:invisible={input_screen_invisible} tabindex=0>
    <div class="p-2">
        <div class="p-1 text-sm">{input_screen_title}</div>
        <input bind:this={input_screen_input} id="set_new_speaker_input" class="pl-1" onkeydown={input_screen_keydown} bind:value={input_screen_value} >
        <div class="p-1 text-sm">or ESC to exit</div>
    </div>
</div>
