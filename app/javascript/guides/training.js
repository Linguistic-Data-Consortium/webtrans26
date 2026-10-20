console.log("Hello from training.js");
import { state as state_store } from '../lib/ldcjs/waveform/stores';
import { times } from '../lib/ldcjs/waveform/times';
import { is_playing } from '../lib/ldcjs/audio/main';
let state;
state_store.subscribe( (x) => state = x );

import { Guide } from "./guide";
import { event as evt } from './guide';
import { delete_nodes_after } from '../lib/ldcjs/waveform/modification1';

const addTTE = n=>{
  n._tooltip = {guide: tuto}; 
  n.tte = (text, ...args) => Guide.tte.call(n, text, ...args);
  return n;
}

const allSegments = [];
evt.addEventListener('created_segment',e=>allSegments.push(e.detail));
evt.addEventListener('destroy_created_segment',e=>allSegments.splice(allSegments.indexOf(e.detail),1));
const evValues = {};
const oldDispatch = evt.dispatchEvent;
evt.dispatchEvent = function(e){
  evValues[e.type]=e;
  if (e.detail instanceof Node) addTTE(e.detail);
  return oldDispatch.call(evt, e);
};
const event = new Proxy(evValues, {get(t,p){ 
  const pr = new Promise(async r=>{
    await new Promise(r2=>evt.addEventListener(p, r2));
    r(evValues[p].detail);
  });
  pr.rush = new Promise(async r=>{
    let v = evValues[p];
    if (v) v = v.detail;
    else v = await pr;
    r(v);
  });
  return pr;
}});

const isTaskPage = () => Guide.route(["task_users", "get"]) && Guide.route("workflow_id")
// let is_playing=()=>false; // to be defined later
const xpath = sel=>document.evaluate(sel,document,null,XPathResult.FIRST_ORDERED_NODE_TYPE,null).singleNodeValue;

/**
 * GUIDE CREATION
 */
const tuto = new Guide("Webtrans Tutorial");

/** 
 * Helper functions 
 */
const deleteNodesAfter = delete_nodes_after;
const appear = (...args) => tuto.wait(...args), disappear = s => appear(s, true);
const promise = f => tuto.promise(f);
let gobackDialogBox = null;
const step = (t, f) => tuto.step(t, async () => {
  if (!isTaskPage()) throw "Abort";
  let misc = {};
  try {
    const incoming = JSON.parse(tuto._misc);
    if (incoming && incoming instanceof Object)
      misc = Guide.extend(incoming, misc);
  }
  catch { }
  if (!(misc.lastNodes instanceof Array))
    misc.lastNodes = [];
  const oldMax = misc.lastNodes[tuto._currentStep];
  let max = 3;
  document.querySelectorAll(".Node").forEach(v=>max = Math.max(max,$(v).data('meta').id));
  if (oldMax!==null && !isNaN(oldMax) && oldMax < max){
    gobackDialogBox = document.createElement("DIV");
    gobackDialogBox.classList.add("gobackDialogBox");
    document.body.append(gobackDialogBox);
    gobackDialogBox.innerText = "Do you want to erase the modifications you have made\
                          between the step you are coming from\
                          and the one you are jumping to?";
    await new Promise(r=>gobackDialogBox.dialog({
      title: "Erase progress?",
      resizable: false,
      width: 350,
      closeOnEscape: false,
      modal: true,
      buttons: {
        Erase: () => {
          deleteNodesAfter(oldMax);
          // Erase next steps' states
          for (let i = tuto._steps.length-1; i > tuto._currentStep; i--)
            misc.lastNodes[i] = null;
          gobackDialogBox.dialog( "close" );
        },
        No: () => gobackDialogBox.dialog( "close" )
      },
      beforeClose: r
    }));
  }
  misc.lastNodes[tuto._currentStep] = max;
  tuto._misc = JSON.stringify(misc);
  await f();
});

/**
 * STEPS
 */
const welcome = step("Welcome", async () => {
  dontOpenHelp();
  await openDialog(
    "Welcome to the Webtrans Tutorial!",
    "Hi! This tutorial will guide you through how to use the transcription tool.\
     This tool allows you to work remotely, and it was especially designed to help you transcribe\
     quickly and easily."
  );

  const bottomBar = await appear(".guide.bottomBar");
  await bottomBar.tte("<p>See the bar at the bottom of the page?</p>\
       <p> This tutorial is composed of <em>steps</em>. In case you miss a step, \
       you can use the dropdown menu in this bottom bar to navigate back to it.\
       Click <em>Reset</em> to go back to the first step with a blank slate (all progress will be lost).</p>", "above", "cover").promise;
  introducing_waveform();
});

function check_state(x, r){
  console.log(1)
  const f = () => {
    if(state == x){
      r();
      console.log(2)
    }
    else if(x == 'playing' && is_playing()){
      r();
    }
    else if(x == 'stopped' && !is_playing()){
      r();
    }
    else{
      setTimeout(f, 500);
    }
  };
  f();
}
function check_times(r){
  let second = false;
  const un = times.subscribe( x => {
    if(second){
      un();
      r();
    }
    second = true;
  });
}
/**
 * @description Introducing the Waveform window and It's features
 */
const introducing_waveform = step("Introduction & Playback", async function () {
  dontOpenHelp();
  await openDialog(
    "Introduction",
    "Let us start with the basics of the interface and see how to play our file"
  );

  let waveform = await event.drew_waveform.rush;
  await waveform.tte("<p>This represents the waveform of an audio file.</p>", "cover", { click: true }).promise;
  
  const ticks = await event.drew_ticks.rush;
  await ticks.tte("<p>This timeline (in seconds) helps you locate yourself as you navigate through the waveform.</p>", "cover", {click: true}).promise;
  
  const filename = await event.drew_filename.rush;
  await filename.tte("<p>The name of the audio file you are transcribing appears here to the left.</p>", "cover", "below", "left", {click: true}).promise;

  await waveform.tte("<p>To play the audio file, start by clicking anywhere in the waveform window\
                   (you should see a red cursor as you move your mouse).</p>", "cover", {
    click: false,
    // promise: r=>event.clicked_on_waveform.then(r)
    promise: r => check_state('mousedown_waveform', r)
  }).promise;

  const keyboard_icon = await event.drew_keyboard_icon.rush;
  await waveform.tte("<p>Now press the space bar on your keyboard to play the audio.</p>", {
    click: false,
    // promise: r=>event.playback_started.then(r),
    promise: r => check_state('playing', r),
    condition: ()=>document.activeElement == keyboard_icon,
    loseCondition: async ()=>{
      await waveform.tte("<p>Oops, it looks like you clicked outside the waveform window.</p>\
                    <p>Please click inside the waveform window again.</p>", {
        click: false,
        cover: true,
        // promise: r=>event.clicked_on_waveform.then(r)
        promise: r => check_state('playing', r)
      }).promise;
    }
  }).promise;

  await waveform.tte("<p>Great! You can press Space again to stop playing, or wait until playback is over.</p>", {
    click: false,
    // promise: r=>event.playback_ended.then(r)
    promise: r => check_state('stopped', r)
  }).promise;
  // Wait 500ms to prevent a keyup on spacebar from closing first dialog from next step
  await promise(r => setTimeout(r, 500));

  navigating_waveform();
});

/**
 *  @description Teching users how to Move Back and Fro in the Waveform Window
 */
const navigating_waveform = step("Navigating the waveform", async function () {
  dontOpenHelp();
  await openDialog(
    "Navigating the waveform",
    "Most audio files are long enough that their waveform does not entirely fit at once in the window.\
     In this step, you will learn how to navigate the waveform using your mouse (we will later see how to do it using your keyboard)."
  );

  const waveform_scrollbar = await event.drew_scrollbar.rush;
  await waveform_scrollbar.tte("<p>This area can be used to scroll the waveform window. Try clicking and dragging \
                                   the scrollbar to the right to see the remaining of the audio.</p>\
                                <p>Note that the longer the audio file, the narrower the red bar in this area appears.</p>",
    {
      cover: true,
      click: false,
      // promise: r=>event.drew_scroll_cursor.then(()=>setTimeout(r,200))
      promise: r => check_times(r)
    }
  ).promise;

  const waveform = await event.drew_waveform.rush;
  await waveform.tte("<p>Great! Note that rendering the waveform takes time, so it might get updated only after you release the click.\
                         Feel free to practice more before moving on to the next step.</p>", { click: true }).promise;

  makeAselection();
});

/**
 * @description How to Creating the Audio Segments/Chunks
 */
const makeAselection = step("Create an Audio Segment", async function () {
  dontOpenHelp();
  const waveform = await event.drew_waveform.rush;
  await openDialog(
    "Create an Audio Segment",
    "Transcribing the full audio file as one long single line would be unwise. In this step, \
       we will learn how to create short <em>segments</em> that can easily be transcribed.<br>\
       Ideally, segments should be a single sentence long, but many segments will include the last part of one sentence and the first part of another."
  );
  await waveform.tte("<p>To start with, let's see how to make a selection: move your cursor over the waveform, click, drag your cursor, and release.</p>\
               <p>Important tip: when transcribing, end your segments at pauses or breaths lasting 0.5 seconds or longer.<br>\
                  For now, just create a short segment, just 2sec long for example.</p>", "cover", {
    click: false,
    promise: async r=>{
      await event.drew_selection;
      await event.clicked_on_waveform;
      r();
    }
  }).promise;

  const keyboard_icon = await event.drew_keyboard_icon.rush, rect = await event.drew_selection.rush;
  let new_segment;
  function find_active(){
    new_segment = document.querySelector('.active-segment');
    if(!new_segment){
      setTimeout(x => find_active(), 500);
    }
  }
  await waveform.tte("<p>Great job! You can press the space bar to listen to the selection.</p>", {
    click: false,
    promise: r=>{
      event.playback_started.then(r);
      event.created_segment.then(s=>r(new_segment=s));
    },
    condition: ()=>document.activeElement==keyboard_icon && rect.offsetWidth>5,
    loseCondition: async()=>{
      await promise(r=>setTimeout(r,100));
      await getSelectionAndFocusBack();
      waveform.tooltips[0].querySelector("p").innerText = "Press the space bar to listen to the selection";
    }
  }).promise;

  // This will not run if the user pressed Enter instead of Space in response to the previous tooltip
  if (!new_segment){
    await event.playback_ended;
    await waveform.tte("<p>Now press <tt>Enter</tt> to create a new segment for this selection.</p>", {
      click: false,
      promise: r=>event.created_segment.then(r),
      condition: ()=>rect && rect.offsetWidth>5 && document.activeElement == keyboard_icon,
      loseCondition: async()=>{
        await promise(r=>setTimeout(r,100));
        await getSelectionAndFocusBack();
        waveform.tooltips[0].childNodes.forEach(n=>{
          if (n.nodeName=="P") n.innerHTML = "<p>Press <tt>Enter</tt> to create a new segment.</p>";
        });
      }
    }).promise;
  }

  let replay = await event.drew_underline.rush;
  await new Promise(r=>setTimeout(r,1000));
  find_active();
  await new Promise(r=>setTimeout(r,500));
  let input = addTTE(new_segment.querySelector("textarea"));

  await input.tte("<p>This text input box is where you transcribe the newly created segment.</p>\
                   <p>Type some text and then press <tt>Enter</tt> to finish it.</p>\
                   <p>Tip: you can listen to the segment again by pressing <tt>Ctrl</tt>+<tt>Spacebar</tt>.</p>", {
    cover: true,
    y: "above",
    click: false, 
    key: "Enter",
    condition: t => document.body.contains(t._target),
    loseCondition: async t => {
      await new_segment.tte("<p>You need to keep focus on the input box. Click to bring back focus.</p>",{
        click: false,
        cover: true,
        y: 'above',
        promise: r=>new_segment.addEventListener('click', ()=>{
          input = new_segment.querySelector("textarea");
          t._target = input;
          r();
        })
      }).promise;
    }
  }).promise;
  await event.playback_started;
  
  await replay.tte("<p>Playback starts automatically after you press <tt>Enter</tt>.</p>\
                    <p>Note that segments come with blue bars that help you delineate them.</p>", {
    click: true,
    cover: true
  }).promise;

  await promise(r => setTimeout(r, 500));

  await openDialog(
    "Create an Audio Segment",
    "<p>Great Job! Now try creating another 1-2 sec audio segment not overlapping with the previous one.</p>" +
    "<p>Remember, blue lines indicate audio segments, so you can use them as a guide to create additional, non-overlapping segments for the same speaker. (Different speakers may overlap.)</p>"
  );

  await waveform.tte({
    content: "<p>Reminder: click, drag and release, then press <tt>Enter</tt>, type some text and press <tt>Enter</tt> again.</p>",
    cover: false,
    key: false,
    click: false,
    y: "above",
    promise: async r=>{
      await event.created_segment;
      await event.playback_started;
      r();
    }
  }).promise;

  await event.playback_ended;
  await promise(r => setTimeout(r, 500));

  await openDialog(
    "Create an Audio Segment",
    "Good Job! You just created, transcribed and re-heard a particular segment on your own.\
       Let's move on to next step."
  );

  toggle();
});

/**
 * @description Toggle using Tab and,
 *              Use of Enter button and it's effect in both waveform and input area
 */
const toggle = step("Toggle", async function () {
  dontOpenHelp();
  const waveform = await event.drew_waveform.rush;
  await openDialog(
    "Toggle",
    "While working on a segment, the ability to toggle between the waveform window and the text window makes you much more effcient.<br><br>\
       Indeed, you can use keyboard commands from either window, but the two windows use different keys or key combinations.\
       Let us learn how to toggle from one window to the other."
  );

  let segment = await event.created_segment.rush;
  await segment.tte("<p>First, click on this transcription line.</p>", {
    click: false,
    cover: true,
    y: "above",
    promise: r => segment.addEventListener('click',r)
  }).promise;

  let input = addTTE(segment.querySelector("textarea"));
  input.focus();

  const inputCondition = t=>document.body.contains(t._target) && document.activeElement==t._target;
  const inputLoseCondition = async t => {
    await segment.tte("<p>It looks like you lost focus from the input box. Click here to get it back.</p>",{
      cover: true,
      y: 'above',
      click: false,
      promise:async r=>{
        await new Promise(r2=>segment.addEventListener('click',r2));
        t._target = segment.querySelector("textarea");
        input = t._target;
        r();
      }
    }).promise;
  };

  await input.tte("<p>The text window currently has focus: notice the red border around the textbox.</p>\
                           <p>Toggle focus by pressing the <tt>Tab</tt> key on your keyboard.</p>", {
    click: false,
    cover: false,
    y: 'above',
    key: "Tab",
    condition: inputCondition,
    loseCondition: inputLoseCondition
  }).promise;

  // Can get back focus
  let keyboard_icon = await event.drew_keyboard_icon.rush;
  keyboard_icon.focus(); // safety measure
  await keyboard_icon.tte("<p>The waveform window now has focus: notice this framed keyboard icon.</p>\
    <p>Press <tt>Tab</tt> again to bring focus back to the text input field.</p>", {
    cover: true,
    click: false,
    key: "Tab",
    condition: t=>document.body.contains(input) && document.activeElement==t._target,
    loseCondition: async t => {
      await new Promise(r=>setTimeout(r,250));
      if (document.body.contains(input)){ // Lost focus from keyboard icon
        const filename = await event.drew_filename.rush;
        await filename.tte("<p>It looks like the waveform window lost focus. Please click on the keyboard icon.</p>",{
          y: 'below', x: 'right', click: false, cover: false, promise: r=>keyboard_icon.addEventListener("focusin",r)
        }).promise;
      }
      else{ // Lost input
        await segment.tte("<p>It looks like you closed the input box. Please click here to reopen it.</p>",{
          click: false, cover: true, y: 'above', promise:r=>segment.addEventListener('click',r)
        }).promise;
        input = addTTE(segment.querySelector("textarea"));
        await segment.tte("<p>Now press <tt>Tab</tt> to bring focus back to the waveform window.</p>",{
          click: false, cover: false, promise:r=>keyboard_icon.addEventListener('focusin',r)
        }).promise;
      }
      await new Promise(r=>setTimeout(r,250));  // Prevent previous Tab from satifsying promise
    }
  }).promise;

  await new Promise(r=>setTimeout(r,250));  // Wait for input to re-appear(?)
  input = addTTE(segment.querySelector("textarea"));

  await input.tte("<p>Now you're back in the text window (notice its red border).</p>\
                   <p>Press <tt>Enter</tt> to play the next audio segment.</p>", {
    cover: false,
    click: false,
    key: "Enter",
    condition: inputCondition,
    loseCondition: inputLoseCondition
  }).promise;

  await event.playback_started;
  await event.playback_ended;
  
  await waveform.tte("<p>Let's toggle back to the waveform window: press <tt>Tab</tt>.</p>", {
    cover: false,
    click: false,
    key: "Tab",
    condition: ()=>inputCondition({_target: input}),
    loseCondition: async()=>await inputLoseCondition({_target: input})
  }).promise;

  await waveform.tte("<p>Now press <tt>Enter</tt> and notice what happens!</p>", {
    click: false,
    condition: () => keyboard_icon==document.activeElement,
    loseCondition: async () => await bringFocusToRelevantWindow(waveform, "Waveform area"),
    key: "Enter",
    y: "below"
  }).promise;
  
  let new_segment = await event.created_segment;
  let rect = await event.drew_underline.rush;
  
  await rect.tte("<p>Unlike in the text window, where <tt>Enter</tt> played the next audio segment,\
      pressing <tt>Enter</tt> with focus on the waveform window just created another copy of the active segment,\
      as indicated by the double blue bar.</p>", {
    click: true,
    cover: true,
    y: "below"
  }).promise;

  await new_segment.tte("<p>To deal with this, click in the input box of the newly created segment \
                                        in the list below (the empty red-colored line).</p>", {
    click: false,
    cover: true,
    y: "above",
    promise: r => new_segment.addEventListener("focusin", r)
  }).promise;

  input = addTTE(new_segment.querySelector("textarea"));
  await input.tte("<p>Now press <tt>CTRL</tt>+<tt>d</tt> on your keyboard to delete this unwanted audio segment, clicking the red 'delete' button to confirm.</p>", {
    click: false,
    y: "below",
    promise: r => document.addEventListener("keydown", e => { if (e.ctrlKey && e.key === "d") r(); }),
    condition: t=>document.body.contains(t._target),
    loseCondition: async t => {
      await new_segment.tte("<p>It looks like you lost focus from the input box. Click here to get it back.</p>",{
        cover: true,
        y: 'above',
        click: false,
        promise:r=>new_segment.addEventListener('click',r)
      }).promise;
      input = addTTE(new_segment.querySelector("textarea"));
      t._target = input;
    }
  }).promise;

  await new Promise(r=>event.destroy_created_segment.then(s=>s==new_segment && r()));

  await waveform.tte("<p>As you can see, the duplicate segment has now disappeared.\
                         You now know how to toggle and delete an unwanted segment.</p>", {
    cover: false, click: true, key: false, y: "above"
  }).promise;

  divide_and_merge_segment();
});

/**
 * @description Splitting and mergin while in Waveform Window
 */
const divide_and_merge_segment = step("Split and Merge Segments: Part I", async function () {
  dontOpenHelp();
  await openDialog(
    "Split and Merge Segments: Part I",
    "As your transcription work progresses, you will find that the edits you want to make to your segments\
       are not limited to deletion.<br><br>\
       Sometimes, you will create one segment and later realize that splitting it in two would be a better option, or the other way around. Maybe you want to exclude a pause or breath of 0.5 seconds or longer, or part of the segment actually contains speech from a different speaker. This tool allows for these adjustments. Let us learn how to split and merge audio segments."
  );

  const waveform = await event.drew_waveform.rush, keyboard_icon = await event.drew_keyboard_icon.rush;

  let segments = await event.drew_segments.rush, segment;
  await segments.tte("<p>Click on the transcription line of an audio segment\
                        to make it active.</p>", {
    click: false, cover: false, y: "above",
    promise: r => allSegments.forEach(s=>s.addEventListener('click',e=>r(segment=segment||addTTE(s))))
  }).promise;

  const getSegmentBack = async (t) => {
    await promise(r=>setTimeout(r,100)); // wait to check if segment is still active;
    const input = segment.querySelector("textarea");
    if (!input || (t=='no_keyboard' && input != document.activeElement))
      await segment.tte("You lost focus from your segment. Click on it again", "cover", "above",
        {click:false, promise:r=>segment.addEventListener("click",r)}).promise;
    if (t=='no_keyboard') return;
    const keyboard_icon = await event.drew_keyboard_icon.rush;
    await keyboard_icon.tte("Click on the keyboard icon", "cover",
      {promise: r=>keyboard_icon.addEventListener("click",r), click:false}).promise;
  };

  await waveform.tte("<p>Now press <tt>Tab</tt> to give focus to the waveform window.</p>", {
    key: "Tab", click: false, cover: false, y: "above",
    condition: ()=>document.activeElement == segment.querySelector("textarea"),
    loseCondition: async () => {
      await getSegmentBack("no_keyboard");
    }
  }).promise;

  await waveform.tte("<p>Move your mouse over the waveform window to control the red line cursor</p>\
                      <p>and, place it where you want to divide the current segment.</p>\
                      <p>IMPORTANT: do NOT click, simply move the red cursor</p>", {
    click: false, key: false,
    promise: r => waveform.addEventListener('mousemove',r),
    condition: ()=>document.activeElement == keyboard_icon && segment.querySelector("textarea"),
    loseCondition: getSegmentBack
  }).promise;

  let red_rect = await event.drew_selection.rush, mouse_in_red_rect = false;;
  red_rect.addEventListener('mouseenter', ()=>mouse_in_red_rect=true);
  red_rect.addEventListener('mouseleave', ()=>mouse_in_red_rect=false);
  
  keyboard_icon.focus();
  await waveform.tte("<p>Press the comma '<tt>,</tt>' key on your keyboard to split the segment where the cursor is.</p>\
                      <p>IMPORTANT: do NOT click, simply move the cursor and then press '<tt>,</tt>'.</p>", {
    click: false,
    condition: ()=>document.activeElement == keyboard_icon && segment.querySelector("textarea"),
    loseCondition: getSegmentBack,
    promise: r=> {
      let resolved = false, warning = false;
      document.addEventListener("keydown", async e => {
        if (resolved) return true;
        if (e.key === "," && !warning && !mouse_in_red_rect) {
          warning = true;
          await segment.tte("<p>Your cursor needs to be inside the red region.</p>", {
            click: false, cover: false, y: "above", 
            promise: r2=>red_rect.addEventListener('mouseenter', r2) 
          }).promise;
          warning = false;
        }
      });
      event.split_segment.then(()=>r(resolved=true));
    }
  }).promise;

  await event.created_segment;
  keyboard_icon.focus();

  let underline = await event.drew_underline.rush;
  await underline.tte("<p>The former active segment has been split in two: there now are two blue bars where there used to be one,\
                         and a new empty transcription line appeared in the list below the waveform.</p>", {
    click: true, key: false, cover: true, y: "above"
  }).promise;

  keyboard_icon.focus();
  await waveform.tte("<p>Now that you know how to split segments in two, we will learn to merge them back!<br>\
                         To merge them back, simply press the letter <tt>m</tt> on your keyboard:\
                         this will merge the new active segment with the next one on its right (the empty one).</p>\
                         <p>Note that this command works with waveform focus---framed keyboard icon.</p>", {
    click: false, y: 'above', 
    promise: r=>event.merged_segments.then(r),
    condition: () => document.activeElement==keyboard_icon && segment.querySelector("textarea"),
    loseCondition: getSegmentBack,
    cover: false
  }).promise;

  await event.destroy_created_segment;

  await waveform.tte("<p>Good job! Remember, when focus is on the waveform window, <br>\
        a keypress on <tt>,</tt> will split the segment at the red cursor,<br>\
        and a keypress on <tt>m</tt> will merge the next segment into the active segment.</p>", {
    click: true,
    key: false,
    y: "below"
  }).promise;

  divide_and_merge_from_text();
});

/**
 * @description Splitting and mergin while in Text Window
 */
const divide_and_merge_from_text = step("Split and Merge: Part II", async function () {
  dontOpenHelp();
  await openDialog(
    "Split and Merge: Part II",
    "<p>You now know how to split and merge two segments while you are in the waveform window.</p>\
     <p>Commands work differently in the waveform window and the text window.\
        For example, simply pressing comma in the text window will just type it instead of dividing the segment.</p>\
     <p>So let's see how to do merge and split while focus is on the text window.</p>"
  );

  let segments = await event.drew_segments.rush, segment;
  await segments.tte("<p>First, click on a segment to open its input box and give it focus.</p>", {
    click: false,
    cover: true,
    y: "above",
    promise: r => allSegments.forEach(s=>s.addEventListener('click',()=>r(segment=addTTE(s))))
  }).promise;

  let red_rect = await event.drew_selection.rush, mouse_in_red_rect = false;;
  red_rect.addEventListener('mouseenter', ()=>mouse_in_red_rect=true);
  red_rect.addEventListener('mouseleave', ()=>mouse_in_red_rect=false);

  const waveform = await event.drew_waveform.rush;
  await waveform.tte("<p>Now move the red line cursor (<em>without clicking</em>) to where you want to split.</p>\
      <p>Then press the Control and comma keys together (<tt>Ctrl</tt>+<tt>,</tt>).</p>", {
    click: false,
    cover: false,
    y: "above",
    condition: () => document.activeElement==segment.querySelector("textarea"),
    loseCondition: async () => await bringFocusToRelevantWindow(waveform, "text window", segment),
    promise: r=> {
      let resolved = false, warning = false;
      document.addEventListener("keydown", async e => {
        if (resolved) return true;
        if (e.ctrlKey && e.key === "," && !warning && !mouse_in_red_rect) {
          warning = true;
          await segment.tte("<p>Your cursor needs to be inside the red region.</p>", {
            click: false, cover: false, y: "above", 
            promise: r2=>red_rect.addEventListener('mouseenter', r2) 
          }).promise;
          warning = false;
        }
      });
      event.split_segment.then(()=>r(resolved=true));
    }
  }).promise;

  await event.created_segment;
  await waveform.tte("<p>You now have two segments.</p>\
                      <p>Press the Control and <tt>m</tt> keys together\
                         (<tt>Ctrl</tt>+<tt>m</tt>) to merge the two split segments.</p>", {
    click: false,
    y: "above",
    condition: () => document.activeElement == segment.querySelector("textarea"),
    loseCondition: async () => await bringFocusToRelevantWindow(waveform, "text window", segment),
    promise: r => document.addEventListener('keyup', e=> e.ctrlKey && e.key === "m" && r())
  }).promise;

  await waveform.tte("<p>As you can see, the two split segments are now merged into a single one again.</p>\
                      <p>You are now able to split and merge two segments both from within the waveform and\
                      from within the text window.</p>", {
    cover: false, click: true, y: "above"
  }).promise;

  adjust_segments();
});

/**
 * @description Adjusting the already created audio segments to increse or decrease the length
 */
const adjust_segments = step("Adjust Audio Segments", async function () {
  dontOpenHelp();
  const waveform = await event.drew_waveform.rush;
  await openDialog(
    "Adjust Audio Segments",
    "You may have noticed that splitting one segment inserts an empty area between the two new segments: this is one situation where you might need to adjust (shorten or lengthen) an existing segment. You may need to adjust your segments to reflect different, simultaneous speakers, whose segments can overlap."
  );
  
  let segments = await event.drew_segments.rush, segment;
  await segments.tte("<p>First, click on a segment in this list.</p>", {
    click: false,
    cover: true,
    y: "above",
    promise: r => allSegments.forEach(n=>n.addEventListener("click", e=>r(segment=addTTE(n))))
  }).promise;

  await event.drew_selection.rush;
  
  await waveform.tte("<p>Now you should see a red region in the waveform.</p>\
                      <p>Click either end of that red region and drag your cusor in either direction.</p>", {
      click: false,
      cover: true,
      promise: r=>event.adjusted_time.then(r),
      condition: ()=>segment.querySelector("textarea"),
      loseCondition: async () => await bringFocusToRelevantWindow(waveform, "text window", segment)
  }).promise;

  await promise(r=>setTimeout(r,500)); // 500ms timer to leave time to user to see what happens
  await waveform.tte("<p>There you go, it's as simple as that!\
                         Drag in one direction to shorten, drag in the other direction to lengthen.</p>", {
    click: true,
    cover: false,
    y: "below"
  }).promise;

  zoom_in_out();
});

/**
 * @description Zoom funciton for the waveform audio file
 */
const zoom_in_out = step("Zoom In/Zoom Out", async function () {
  dontOpenHelp();
  const waveform = await event.drew_waveform.rush;
  await openDialog(
    "Adjust Audio Segments: Zoom In/Zoom Out",
    "Whenever you adjust a segment, you should insert a buffer of 0.1 sec before and after it:\
       this ensures that a word won't be cut off prematurely.<br><br>\
       Precisely measuring 0.1 sec can be difficult, so this tool comes with a built-in zoom in/out function."
  );

  const keyboard_icon = await event.drew_keyboard_icon.rush;
  // the code below handles keypresses from outside waveform focus
  await waveform.tte("<p>To zoom in, make sure you are in the waveform window (framed keyboard icon),<br>\
                         and press the letter key <tt>i</tt> (for '<tt>in</tt>').</p>", {
    click: false,
    y: "below",
    promise: r => {
      let zoomed_in = false;
      event.zoomed_in.then(()=>r(zoomed_in=true));
      document.addEventListener("keydown", e => {
        if (zoomed_in || e.key != "i" || document.activeElement == keyboard_icon) return true;
        waveform.tooltips[0].innerHTML = "Click the waveform to give it focus, and only then press <tt>i</tt>.";
        waveform.addEventListener('click',()=>!zoomed_in&&(waveform.tooltips[0].innerHTML="Now press <tt>i</tt>."));
      });
    }
  }).promise;

  const waveform_ticks = await event.drew_ticks.rush;
  await waveform_ticks.tte("<p>As you can see, the timeline intervals are now finer-grained. You can zoom further in by pressing <tt>i</tt> again.</p>", {
    click: true,
    cover: true
  }).promise;

  keyboard_icon.focus();
  
  await waveform.tte("<p>To zoom out, press the letter key <tt>o</tt> (for '<tt>out</tt>')<br>\
                         while focus is still on the waveform window (framed keyboard icon).</p>", {
      click: false,
      cover: false,
      y: "below",
      promise: r => {
        let zoomed_out = false;
        event.zoomed_out.then(()=>r(zoomed_out=true));
        document.addEventListener("keydown", e => {
          if (zoomed_out || e.key != "o" || document.activeElement == keyboard_icon) return true;
          waveform.tooltips[0].innerHTML = "Click the waveform to give it focus, and only then press <tt>o</tt>.";
          waveform.addEventListener('click',()=>!zoomed_out&&(waveform.tooltips[0].innerHTML="Now press <tt>o</tt>."));
        });
      }
  }).promise;

  await waveform.tte("<p>Remember, <tt>i</tt> to zoom <strong>i</strong>n, <tt>o</tt> to zoom <strong>o</strong>ut.</p>", {
    click: true,
    cover: false,
    key: false,
    y: "below"
  }).promise;

  home_keys_one();
});

/**
 * @description Usage of Home Keys to edit the audio segment
 */
const home_keys_one = step("Home Keys: Part I", async () => {
  dontOpenHelp();
  await openDialog(
    "Home Keys: Part I",
    "Zooming in and out is not the only way of getting finer-grained control over the waveform.<br><br>\
     In this step, you will learn to control elements from the waveform window using your keyboard."
  );

  let segment;

  // Wait for waveform here, because segmentss takes it place early on
  const waveform = await event.drew_waveform.rush;
  const segments = await event.drew_segments.rush;
  await segments.tte("<p>First, click on one of the transcription lines below.</p>", {
    y: "above",
    click: false,
    cover: true,
    promise: r => allSegments.forEach(n=>n.addEventListener('click',e=>r(segment=addTTE(n))))
  }).promise;

  let input = addTTE(segment.querySelector("textarea"));
  await input.tte("<p>Now that your segment is active, press <tt>Tab</tt> to give focus to the waveform window.</p>\
             <p>Important: do NOT click the waveform window, or you will lose the active segment.</p>", {
    y: "below",
    cover: false,
    click: false,
    condition: t => t._target === document.activeElement,
    loseCondition: async t => {
      await bringFocusToRelevantWindow(input, "text window", segment);
      input = segment.querySelector("textarea");
      t._target = input;
    },
    key: "Tab"
  }).promise;

  const keyboard_icon = await event.drew_keyboard_icon.rush;
  keyboard_icon.focus(); // safety measure

  const mode = await event.drew_mode.rush;
  await mode.tte("<p>Notice how this reads <em>cursor</em>: this means that key bindings will apply to the red cursor.</p>\
                  <p>In this step, we want to adjust the beginning/end of the segment. \
                    Press <tt>b</tt> to control the <strong>b</strong>eginning of the segment.</p>", {
    click: false,
    cover: true,
    y: "below",
    key: "b",
    condition: ()=>document.activeElement == keyboard_icon && segment.querySelector("textarea"),
    loseCondition: async ()=>{
      await new Promise(r=>setTimeout(r,100));
      if (segment.querySelector("textarea")){
        const filename = await event.drew_filename.rush;
        await filename.tte("<p>It looks like your waveform window lost focus. Simply click on the keyboard icon.</p>",{
          click: false, y: 'below', x: 'right', cover: false, promise:r=>keyboard_icon.addEventListener('click',r)
        }).promise;
      }
      else{
        await segment.tte("<p>It looks like you lost your active segment. Please click on the segment again.</p>",{
          click: false, cover: true, y: 'above', promise:r=>segment.addEventListener('click',r)
        }).promise;
        await waveform.tte("<p>Now press <tt>Tab</tt> to give focus to the waveform window.</p>",{
          click: false, y: 'below', x: 'right', cover: false, key: "Tab"
        }).promise;
      }
    }
  }).promise;

  await modeAppears('beg');
  await mode.tte("<p>This now reads <em>beg</em>: you are now controlling the beginning of the segment.</p>\
                  <p>Press the key <tt>f</tt> to move it to the left, or the key <tt>j</tt> to move it to the right.</p>", {
    y: "below",
    cover: true,
    click: false,
    key: ["f","j"],
    condition: ()=>mode.innerText=='beg',
    loseCondition: async ()=>{
      await lostMode('beg');
      mode.tooltips[0].querySelector(".content").innerHTML = "<p>Press the key <tt>f</tt> to move it to the left, or the key <tt>j</tt> to move it to the right.</p>";
    }
  }).promise;
  
  await waveform.tte("<p>Press the key <tt>f</tt> to move further to the left, or <tt>j</tt> to move further to the right.\
                         Feel free to practice a little.</p>", {
    cover: false,
    click: true,
    y: "below",
  }).promise;

  keyboard_icon.focus(); // Click on tooltip lost focus---restore it
  window.ldc.wc.set_mode('beg');
  await new Promise(r=>setTimeout(r,1000));
  await waveform.tte("<p>You can make bigger steps to the left by using the keys <tt>d</tt>, <tt>s</tt> and <tt>a</tt>,<br>\
                         and to the right using the keys <tt>k</tt>, <tt>l</tt> and <tt>;</tt>.<br>\
                         The relative positions of those keys on a standard US keyboard reflect the magnitude of the step.</p>\
                      <p>Press <tt>c</tt> when you are satisfied to go back to <em>cursor</em> mode, thus validating the new beginning position.</p>", {
    y: "below",
    cover: false,
    click: false,
    key: "c",
    condition: ()=>mode.innerText=='beg',
    loseCondition: ()=>lostMode('beg')
  }).promise;

  keyboard_icon.focus();

  await mode.tte("<p>Now press the key <tt>e</tt> to control the <strong>e</strong>nd of the segment.</p>", {
    y: "below",
    cover: true,
    click: false,
    key: "e",
    condition: ()=>allSegments.find(s=>s.querySelector("textarea")) && document.activeElement==keyboard_icon,
    loseCondition: ()=>bringFocusToRelevantWindow(mode,"Keyboard Icon area")
  }).promise;

  await modeAppears('end');

  await mode.tte("<p>This now reads <em>end</em>: you are now controlling the end of the segment.</p>\
                  <p>As before, press the key <tt>f</tt> to move it to the left, or the key <tt>j</tt> to move it to the right.</p>", {
    y: "below",
    cover: true,
    click: false,
    key: ["f","j"],
    condition: ()=>mode.innerText=='end',
    loseCondition: ()=>lostMode('end')
  }).promise;

  await waveform.tte("<p>The key bindings are the same: <tt>f</tt>, <tt>d</tt>, <tt>s</tt> and <tt>a</tt> move to the left, \
                         <tt>j</tt>, <tt>k</tt>, <tt>l</tt> and <tt>;</tt> move to the right. \
                         Feel free to practice, and press <tt>c</tt> when you are done.</p>", {
    cover: false,
    y: "below",
    click: false,
    key: "c",
    condition: ()=>mode.innerText=='end',
    loseCondition: ()=>lostMode('end')
  }).promise;

  home_keys_two();
});

/**
 * @description Usage of Home Keys to move teh waveform cursor
 */
const home_keys_two = step("Home Keys: Part II", async () => {
  dontOpenHelp();
  await openDialog(
    "Home Keys: Part II",
    "These eight keys (<tt>a</tt>, <tt>s</tt>, <tt>d</tt>, <tt>f</tt> and <tt>j</tt>, <tt>k</tt>, <tt>l</tt>, <tt>;</tt>)\
     are called the <em>home keys</em>. You just saw how you can use them to control the beginning and the end of a segment,\
     you will now see how to use them to scroll the waveform window and control the red cursor's position."
  );

  const waveform = await event.drew_waveform.rush;
  await waveform.tte("<p>First, click anywhere in the waveform window.</p>", {
    click: false,
    cover: true,
    key: false,
    promise: r => waveform.addEventListener('click',r)
  }).promise;

  const mode = await event.drew_mode.rush;
  await mode.tte("<p>Now press <tt>w</tt> to change from cursor to <em>window</em> mode.</p>", {
    click: false, cover: true, y: "below", key: "w"
  }).promise;

  await modeAppears('window');

  let moved_window = false;
  event.moved_window.then(e=>moved_window=true);
  await waveform.tte("<p>You can now use the home keys to scroll the waveform window \
                         to the right (<tt>j</tt>, <tt>k</tt>, <tt>l</tt> and <tt>;</tt>)\
                         and to the left (<tt>f</tt>, <tt>d</tt>, <tt>s</tt> and <tt>a</tt>).</p>", {
    click: true,
    cover: false,
    key: false,
    condition: ()=>mode.innerText=='window'||moved_window,
    loseCondition: ()=>lostMode('window')
  }).promise;

  const keyboard_icon = await event.drew_keyboard_icon.rush;
  keyboard_icon.focus();
  window.ldc.wc.set_mode('cursor');
  // await modeAppears('cursor');
  await mode.tte("<p>In cursor mode, the home keys will simply move the red cursor, allowing you for example\
                     to precisely reach a splitting point. Try pressing one of the home keys and see the cursor move.</p>", {
    click: false,
    cover: true,
    y: "below",
    key: ["a", "s", "d", "f", "j", "k", "l", ";"]
  }).promise;

  await waveform.tte("<p>That's pretty much it for the home keys. \
                         Remember, they will work when focus is on the waveform window (framed keyboard icon).</p>\
                      <p>Feel free to practice a little more before moving to the next step.</p>", {
    click: true, cover: false, key: false
  }).promise;

  move_audio_segment();
});

/**
 * @description Steps related to keys which perform same action across both the windows
 */
const move_audio_segment = step("Move Across Audio Segments", async function () {
  dontOpenHelp();
  await openDialog(
    "Move Across Audio Segments",
    "A few keys perform the same action when pressed from <em>either</em> window.<br><br>\
       Pressing the up and down arrow keys from either window, for example, will move from one audio segment to another."
  );

  const keyboard_icon = await event.drew_keyboard_icon.rush;
  const waveform = await event.drew_waveform.rush;
  await waveform.tte("<p>First make sure your focus is either on the waveform window or on the text window.</p>", {
    click: false,
    y: "above",
    promise: r => [...allSegments, waveform, keyboard_icon].forEach(s=>s.addEventListener("click",r))
  }).promise;

  await waveform.tte("<p>Now press the <tt>Up</tt> arrow key to go to the last/previous segment,<br>\
                         or the <tt>Down</tt> arrow key to go the first/next segment.</p>", {
    click: false,
    y: "above",
    key: ["ArrowUp", "ArrowDown"]
  }).promise;

  await waveform.tte("<p>You can try switching focus and press <tt>Up</tt> or <tt>Down</tt> again if you'd like.</p>\
                      <p>Note that pressing either key will automatically bring focus back to the input window,\
                         so you need to toggle focus if you want to work from the waveform window.</p>\
                      Once you are ready, we will move to the next step.", {
    click: true,
    key: false,
    y: "above"
  }).promise;

  open_help();
});

let currentHelpMenu;
['opened_help','opened_help_waveform','opened_help_transcript',
 'opened_help_playback','opened_help_services','opened_help_sad']
.forEach(type=>{
  const no_open_type = type.replace(/^opened_help_?/,'');
  evt.addEventListener(type,e=>currentHelpMenu=no_open_type);
  evt.addEventListener('destroy_'+type,e=>currentHelpMenu==no_open_type && (currentHelpMenu=null));
});
const helpMenuOpen = sub=>currentHelpMenu===(typeof(sub)=="string"?sub:'');

/**
 * @description Describe the first 2 help menu options
 */
const open_help = step("Help Menu: General", async function () {
  await openDialog(
    "Help Menu: General",
    "You might forget some key bindings, and there are some that you are not familiar with yet.<br><br>\
     You can review the different key bindings from the help menu. Let us see how to do that."
  );

  const waveform = await event.drew_waveform.rush;
  await waveform.tte("<p>First, make sure your focus is on the waveform window (framed keyboard icon should be green).</p>\
                      <p>Then press the <tt>h</tt> key to open the help menu. </p>", {
    click: false,
    promise: r => event.opened_help.then(r)
  }).promise;

  const loseHelpScreen = async t =>{
    const channel = addTTE(waveform.parentElement);
    await channel.tte("<p>It looks like you quit the help menu. First, click the waveform window.</p>",{
      click: false, cover: true, y: 'below', promise: r=>waveform.addEventListener('click',r)
    }).promise;
    await channel.tte("<p>Now, press the <tt>h</tt> key.</p>",{
      click: false, cover: false, y: 'below', promise: r=>event.opened_help.then(r)
    }).promise;
    if (t) t._target = await event.opened_help.rush;
  }

  let mini_screen = await event.opened_help.rush;
  await mini_screen.tte("<p>Now press the number <tt>1</tt> on your keyboard to get help about the waveform window.</p>", {
    click: false,
    y: 'above',
    promise: r => event.opened_help_waveform.then(r),
    condition: helpMenuOpen,
    loseCondition: loseHelpScreen
  }).promise;

  const help_screen = await event.opened_help_waveform.rush;
  await help_screen.tte("<p>This page summarizes the keys and their actions from the waveform window.</p>\
                        <p>Press <tt>h</tt> when you are done reading to go back to the help menu.</p>", {
    promise: r=>event.opened_help.then(r),
    click: false,
    cover: false,
    y: "above",
    condition: ()=>helpMenuOpen('waveform'),
    loseCondition: async t=>{
      if (!helpMenuOpen()) await loseHelpScreen();
      const help_screen = await event.opened_help.rush;
      await help_screen.tte("<p>Now press <tt>1</tt> to get back to the summary page.</p>",{
        click: false, y: 'below', promise: r=>event.opened_help_waveform.then(r)
      }).promise;
      t._target = await event.opened_help_waveform.rush;
    }
  }).promise;

  mini_screen = await event.opened_help.rush;
  await mini_screen.tte("<p>Now press the number <tt>2</tt> key on your keyboard to get help about the text window.</p>", {
    promise: r => event.opened_help_transcript.then(r),
    click: false,
    y: 'below',
    condition: helpMenuOpen,
    loseCondition: loseHelpScreen
  }).promise;

  const transcript_help = await event.opened_help_transcript.rush;
  await transcript_help.tte("<p>This lists the key bindings from the text window. Press <tt>h</tt> again to go back.</p>", {
    promise: r=>event.destroy_opened_help_transcript.then(r),
    click: false,
    y: "above",
    condition: ()=>helpMenuOpen('transcript'),
    loseCondition: async t =>{
      if (!helpMenuOpen()) await loseHelpScreen();
      const help_screen = await event.opened_help.rush;
      await help_screen.tte("<p>Now press <tt>2</tt> to get back to the key bindings page.</p>",{
        click: false, cover: false, y: 'above', promise: r=>event.opened_help_transcript.then(r)
      }).promise;
      t._target = await event.opened_help_transcript.rush;
    }
  }).promise;
  close_file();
});

//
// const sad_help = step("Help Menu: SAD", async function(){
//   await openDialog(
//       "Help Menu: SAD",
//       "Another important option from the help menu is SAD.<br><br>\
//        SAD is the automatic segmentor. It can help you automatically divide the whole audio file in multiple segments.\
//        One thing to remember is that SAD is really good, but it is not perfect, so you will still need all the skills you have just learned."
//   );
//   const waveform = await appear(".node-waveform");
//   await waveform.tte("<p>To use SAD, first go to the help menu by pressing the <tt>h</tt> key when in the waveform window</p>", {
//       click: false,
//       promise:r=>$(".Root").keydown(e=>{if ($(".keyboard:focus").length && e.key=="h") r();})
//   }).promise;
//   const section_list = await appear("#section ~ ol li:nth-child(4)");
//   await section_list.tte("<p>Now press the number key <tt>4</tt> on your keyboard to open services menu.</p>", {
//       y: "below",
//       key: "4",
//       click: false
//   }).promise;
//   const sad = await appear("li:contains('SAD')");
//   await sad.tte("<p>Now press the number key <tt>1</tt> on your keyboard to use SAD.</p>", {
//       key: "1",
//       click: false
//   }).promise;
//   await waveform.tte("<p>Now just wait for SAD to finish up, and you will have your segmented file.</p>", {
//     y: "above", click: true
//   }).promise;
//   close_file();
// });
//

const close_file = step("Submit your work", async function(){
  await openDialog(
    "Help Menu: Submit",
    "We are almost done! There's one last thing we need to see: how to submit your transcription."
  );

  const submit = await event.drew_submit.rush;
  await submit.tte("<p>When you are done with the file, click this checkmark icon to submit your work.</p>", {
    click: false, cover: true,
    promise: r => event.drew_done.then(r)
  }).promise;
  
  let done = await event.drew_done.rush;
  await done.tte("<p>Unless there was a problem with the file, simply click on 'Done'.</p>", {
    click: false, cover: true, y: "above",
    condition:t=>t._target.isVisible(),
    loseCondition:async t =>{
      await submit.tte("<p>It looks like you closed the popup. Click on the checkmark icon to reopen it.</p>",{
        click: false, cover: true, y: 'below', promise: r=>event.drew_done.then(r)
      }).promise;
      done = await event.drew_done.rush;
      t._target = done;
    },
    promise: r=>done.addEventListener('click',r)
  }).promise;

  end();
});

/**
 * @description Describe the usage of SAD from help menu
 */
const end = step("End", async function () {
  await openDialog(
    "Training complete!",
    "<p>Thank you, this is the end of this transcription training guide!\
      Remember, you can always press <tt>h</tt> while in the waveform window to get help with the interface.</p>\
     <p>If you wish to take the tutorial again, simply leave this task and open it again.</p>"
  );

  // Add something to automatically reset this guide?
  return 'end';
});



// FUNCTION DEFINITIONS AND GUIDE PRIORITY HANDLING
//
let dialog = null;
const openDialog = (title, content, modal = true) => promise(r => {
  // if (dialog instanceof jQuery && dialog.is(":visible"))
  //   dialog.dialog("close");
  if (dialog && dialog.isVisible())
    dialog.dialog("close");
  // dialog = $("<div>").appendTo($("body")).html(content);
  dialog = document.createElement("DIV");
  dialog.innerHTML = content;
  document.body.append(dialog);
  dialog.dialog({
    title: title,
    resizable: true,
    width: 600,
    closeOnEscape: false,
    modal: modal,
    buttons: { Next: function () { this.dialog("close"); r(); } }
  });
  return dialog;
});

const getSelectionAndFocusBack = async ()=>{
  const rect = await event.drew_selection.rush;
  // if (rect.getAttribute('width')<5) {
  if (rect.offsetWidth<5) {
    const waveform = await event.drew_waveform.rush;
    const channel = addTTE(waveform.parentElement);
    await channel.tte("<p>It looks like you lost the selection. No worries, simply move your cursor over the waveform window,\
                           click, drag your cursor and then release.</p>", {
      click: false,
      cover: true,
      promise: r=>selectionHappened(r)
    }).promise;
  }
  else {
    const keyboard = await event.drew_keyboard_icon.rush;
    await keyboard.tte("<p>It looks like the waveform window lost focus. Please click on this keyboard icon.</p>", {
      click: false,
      cover: true,
      promise:r=>keyboard.addEventListener('click',r)
    }).promise;
  }
};

const selectionHappened=r=>{
  const callback = async ()=>{
    const selection = await event.drew_selection.rush, waveform = await event.drew_waveform.rush;
    if (selection.offsetWidth>5){
      waveform.addEventListener('mouseleave',r);
      document.addEventListener('mouseup',r);
    }
    else window.requestAnimationFrame(callback);
  };
  callback();
};

const modeAppears = mode => new Promise(async r=>{
  setTimeout( () => {
    const text = document.getElementsByClassName('mode')[0].firstElementChild.textContent;
    if(text == mode) r();
  }, 500);
  // const node = await event.drew_mode.rush;
  // console.log(node);
  // const check = ()=>(node.textContent==mode && r()) || window.requestAnimationFrame(check);
  // check();
});

const lostMode = async check_mode => {
  const filename = await event.drew_filename.rush;
  await filename.tte("<p>It looks like you quit <em>" + check_mode + "</em> mode. Let's get it back.</p>", {
    y: "below", x: 'right', cover: false, key: false, click: true
  }).promise;

  const segments = await event.drew_segments.rush;
  await segments.tte("<p>Click on one of the transcription lines below.</p>", {
    y: "above", cover: true, key: false, click: false,
    promise: r => allSegments.forEach(n=>n.addEventListener('click',r))
  }).promise;

  const waveform = await event.drew_waveform.rush;
  const channel = addTTE(waveform.parentElement); // Don't mess with any tte currently attached to waveform
  await channel.tte("<p>Now do NOT move your mouse cursor and press <tt>Tab</tt>.</p>", {
    y: "below", cover: false, key: "Tab", click: false
  }).promise;
  await channel.tte("<p>Keep NOT moving your mouse cursor and press <strong><tt>" + check_mode[0] + "</tt></strong>.</p>", {
    y: "below", cover: false, key: check_mode[0], click: false
  }).promise;

  await modeAppears(check_mode);
}

const dontOpenHelp = ()=> {
  let currentStep = tuto._currentStep;
  [
    'opened_help','opened_help_waveform','opened_help_transcript',
    'opened_help_playback','opened_help_services','opened_help_sad' 
  ].forEach(type=>evt.addEventListener(type, e=>currentStep==tuto._currentStep && addTTE(e.detail).tte(
    "You opened the help menu: close it by pressing <tt>Esc</tt>",
    {click:false,promise:r=>event['destroy_'+type].then(r)}
  )));
}

const bringFocusToRelevantWindow = async (currentTooltip, window, node) => {
  let p;
  if (window == "Waveform area"){
    node = await event.drew_waveform.rush;
    p = r=>node.addEventListener("click",r);
  }
  else if (window == "text window") {
    if (node===undefined) node = await event.created_segment.rush;
    node = addTTE(node);
    p = r=>document.addEventListener("focusin", e=>document.activeElement==node.querySelector("textarea")&&r());
  }
  else if (window == "Keyboard Icon area") {
    await new Promise(r=>setTimeout(r,200));  // Wait before checking active segments
    if (!allSegments.find(s=>s.querySelector("textarea"))){
      const segments = await event.drew_segments.rush;
      await segments.tte("You need to have a segment active. Click on a segment.",
            {click:false,cover:true,promise:r=>allSegments.forEach(s=>s.addEventListener('click',r))}).promise;
    }
    node = await event.drew_keyboard_icon.rush;
    p = r=>node.addEventListener("click", r);
  }

  await node.tte(
    "<p>It looks like you lost focus from the " + window +".</p>\
        <p>Let us bring it back: simply click here to bring focus back to the "+ window +".</p>", {
    click: false, cover: true,
    promise: p
  }).promise;

  // const oldText = $(currentTooltip.tooltips[0]).find('div.content').text().replace(/Focus is back on the \w+ window./,'');
  // $(currentTooltip.tooltips[0]).find('div.content').html(`<p>Focus is back on the ${window} window.</p><p>${oldText}</p>`);
  const contentDiv = currentTooltip.tooltips[0].querySelector("div.content");
  const oldText = contentDiv.innerText.replace(/Focus is back on the \w+ area./,'');
  contentDiv.innerHTML = `<p>Focus is back on the ${window}.</p><p>${oldText}</p>`;
}

Function.prototype.extend = function (newf) {
  let that = this;
  const returnfn = function (...args) {
    newf.apply(this, args);
    return that.apply(this, args);
  }
  return returnfn;
}

// Halt all other guides
let canInitOtherGuides = false;
Guide.before_init(() => {
  if (!isTaskPage()) return;
  for (let g in Guide.guides) {
    let i = Guide.guides[g].init;
    Guide.guides[g].init = () => {
      if (canInitOtherGuides || Guide.guides[g] == tuto) i.call(Guide.guides[g]);
    }
    Guide.guides[g].halt();
  }
});

const init_guides = () => {
  if (!isTaskPage()) return;
  canInitOtherGuides = true;
  for (let g in Guide.guides)
    if (Guide.guides[g] != tuto) {
      Guide.guides[g]._halted = false;
      Guide.guides[g].init();
    }
}
tuto.complete = tuto.complete.extend(init_guides);
tuto.dismiss = tuto.dismiss.extend(() => {
  if (dialog) dialog.dialog("close");
  init_guides();
});
// tuto._resetButton.click(() => {
tuto._resetButton.addEventListener('click', () => {
  // tuto._resetDialogBox.html("CAUTION: This will erase all your transcript lines\
  tuto._resetDialogBox.innerHTML = "CAUTION: This will erase all your transcript lines\
                                    and go back to the first step of this tutorial.\
                                    Are you sure you want to reset?";
                                    // Are you sure you want to reset?");
});
tuto.reset = tuto.reset.extend(()=>{
  deleteNodesAfter(3);
  try {
    const misc = JSON.parse(tuto._misc);
    misc.lastNodes = [];
    tuto._misc = JSON.stringify(misc);
  }
  catch {}
});
let ready_turoblinks_once = false;
const start = async () => {
  if (document.readyState!="complete") return window.requestAnimationFrame(start);
  if (ready_turoblinks_once) return;
  ready_turoblinks_once = true;
  if (!isTaskPage()) {
    canInitOtherGuides = true;
    return tuto.halt();
  }
  // Wait until after workflow_open, so that root.data.obj is defined
  const obj = await new Promise(r =>{
    const set_obj = ()=>{
      let o = $(".Root").data("obj");
      if (o === undefined) window.requestAnimationFrame(set_obj);
      else r(o);
    }
    set_obj();
  });
  if (!obj.task_meta || obj.task_meta.notes != "training")
    return init_guides();   // Don't start this guide if not a "training" task
  tuto._halted = false;
  tuto.init();
  tuto.after_data(data=>{
    if (data.complete===true) {
      tuto.reset();  // Restart the tuto automatically after completing it  
      tuto.launch();
    }
  });
  tuto._dismissButton.remove();
}
start();
