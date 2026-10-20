import { Guide } from "./guide";

const TASKNAME = 'KitsTutorial';

const tuto = new Guide("Kit Creation");
console.log("kit creation tuto", tuto);

// Helper functions
const xpath = sel => document.evaluate(sel,document,null,XPathResult.FIRST_ORDERED_NODE_TYPE,null).singleNodeValue;
const appear = (...args) => tuto.wait(...args), disappear = s => appear(s, /*disappear:*/true);
const promise = f => tuto.promise(f);
const step = (t, f) => tuto.step(t, async () => await f() );
const pause = (duration=200)=>promise(r=>setTimeout(r,duration));
const tte = async (el, params, ...args) => {
  for (let p in params)
    for (let i = 0; i < args.length; i++)
      if (args[i] instanceof Object)
        if (!args[i].hasOwnProperty(p)) 
          args[i][p] = params[p];
  await el.tte(...args).promise;
};
const xtte = async (sel, ...args) => {
  const params = {
    condition: ()=>{
      const newel = xpath(sel);
      return newel && newel.isVisible();
    },
    loseCondition: async()=>await appear(sel, /*disappear:*/false, /*xpath:*/true)
  };
  for (let i = 0; i < args.length; i++)
      if (args[i] instanceof Object && args[i].hasOwnProperty('clickit'))
        params.promise = r=>document.addEventListener('click', e=>{
          let success = false;
          if (args[i].clickit instanceof Function) 
            success = args[i].clickit(e,sel,el);
          else 
            success = e.target == xpath(sel);
          if (success)
            r();
        });
  const el = await appear(sel, /*disappear:*/false, /*xpath:*/true);
  await tte(el, params, ...args);
};

// Fix CSS, but don't interfere with other guides' aesthetics
const fixCSS = ()=>{
  if (tuto._tooltips) tuto._tooltips.forEach(c=>c.style['min-height']='unset');
  window.requestAnimationFrame(fixCSS);
};

// Don't automatically start the tuorial:
// wait for the task to appear on screen
Guide.before_init(() => tuto.halt());
appear("//div[.='KitsTutorial']",/*disappear:*/false,/*xpath:*/true).then( ()=>{
  tuto._halted=false;
  tuto.init();
  fixCSS();
});

const opendemotask = step("Open the Demo task", async () => {
  tuto._bottomBar.style.visibility = 'hidden';
  
  await xtte(`//div[.='${TASKNAME}']`, `<p>Click '${TASKNAME}' to learn to create kits</p>`, "middle","right",
              {click:false, clickit: (e,sel)=>xpath(sel)&&xpath(sel).parentElement == e.target.parentElement});
  await pause();

  tuto._bottomBar.style.visibility = 'visible';

  await xtte("//button[.='Open']", `<p>Great! In this tutorial, you will learn to create kits<br>
                                       for audio files with (valid) S3 bucket URLs.</p>
                                    <p>Click 'Open' so can add kits to the ${TASKNAME} task</p>`, "bottom","cover", 
              {click:false, clickit: e=>e.target.nodeName=="BUTTON"&&e.target.innerText=="Open"});
  await pause();

  createnewkit();
});

const createnewkit = step("Create a new kit", async () => {
  await xtte("//summary[.='Create Kits']", `<p>Click 'Create Kits' to open an interface<br>
                                               where you can provide a list of S3 URLs</p>`,
              "below","cover", {click:false, clickit:true});
  await pause();

  xtte("//button[.='upload']", "Click 'upload' to load the content of the file", "middle", "right", {click:false,clickit:true});

  await xtte( "//div[.='type here, or upload a file']"  ,
      "<p>Type some text in this box<br>or upload a .txt file from your device</p>"+
      "<p>Each line should be a valid S3 URL, for example<br><tt>s3://my-bucket/demos/CarrieFisher10s.wav</tt></p>",
      "left",{click:false, promise: r=>appear("//button[.='parse as text']",/*disappear:*/false,/*xpath:*/true).then(r)});

  let firstentry = "";
  await xtte("//button[.='parse as text']", "Once you have provided a list of valid S3 URLs,<br>"+
                                            "(e.g. <tt>s3://my-bucket/demos/CarrieFisher10s.wav</tt>)<br>"+
                                            "click 'parse as text'",
            "middle", "right",{click:false, clickit: e=>e.target.nodeName=="BUTTON"&&e.target.innerText=="parse as text"});
  appear("//pre[contains(.,'docid')]",/*disappear:*/false,/*xpath:*/true)
    .then(e=>firstentry = JSON.parse(e.innerText.split("\n").filter(v=>v.match(/\w/))[0]).docid);
  await pause();

  await xtte("//button[.='Create Kits']",   "Now click 'Create Kits'", "middle", "right", {click:false, clickit: true});

  await xtte(`//div[.='${firstentry}']`, "<p>Great! As you can see, your kit now appears in the list</p>", "cover", "top");

  await xtte(`//div[.='${firstentry}']`, "Click the new kit to select it", "cover", "top", 
              {click:false, clickit: (e,sel)=>xpath(sel)&&xpath(sel).parentElement == e.target.parentElement});
  await pause();

  await xtte("//button[.='Open']",  "Now click 'Open'", "cover", "left", 
             {click:false, clickit: e=>e.target.nodeName=="BUTTON"&&e.target.innerText=="Open"});
             
  const user = await appear("//label[.='User']",/*disappear:*/false,/*xpath:*/true);
  const selectuser = await appear(`#${user.parentNode.nextElementSibling.childNodes[0].id}`);
  await selectuser.tte("Now assign this kit to a user", "cover", "left", "middle", {
    click:false, promise: r=>{selectuser.addEventListener("change", r);selectuser.addEventListener("blur", r);}
  }).promise;
  await pause();

  await xtte("//button[.='Return to task list']", "<p>And that's it! The tutorial is now over<br>"+
                                                     "You can click this button to return to the list of tasks</p>",
    "middle", "left", "cover", {click:false, clickit: e=>e.target.innerText='Return to task list'});

  return "end";
});

// FUNCTION DEFINITIONS AND GUIDE PRIORITY HANDLING
//
// Function.prototype.extend = function (newf) {
//   let that = this;
//   const returnfn = function (...args) {
//     newf.apply(this, args);
//     return that.apply(this, args);
//   }
//   return returnfn;
// }
