import "./guides.css";
import { GuideChannel } from "../channels/guide_channel";

// helper function
const maxZ = ()=>Math.max(...[...document.querySelectorAll("body *")].map(n=>{
  const s = window.getComputedStyle(n), z = parseInt(s['z-index']);
  if (s.position!='static'&&z<999999999) return z||1;
  else return 1;
}));
const extend = function(old, incoming){
  const newobject = {};
  if (old) 
    Object.keys(old).forEach( p => newobject[p] = old[p] );
  if (incoming)
    Object.keys(incoming).forEach( p => !newobject.hasOwnProperty(p) && (newobject[p] = incoming[p]) );
  return newobject;
}


window.Node.prototype.inDOM = function(){ return document.documentElement.contains(this); }
window.Node.prototype.isVisible = function(){
  if (!this.inDOM()) return false;
  const rect = this.getBoundingClientRect();
  if (rect.width==0 && rect.height==0) return false;
  if (rect.bottom<0||rect.top>window.innerHeight||rect.right<0||rect.left>window.innerWidth)
    return false;
  return true;
}
window.Node.prototype.hide = function(){
  this._oldDisplay = window.getComputedStyle(this).display;
  this.style.display = "none";
}
window.Node.prototype.show = function(){
  if (this._oldDisplay) this.style.display = this._oldDisplay;
  else this.style.display = "block";
}
window.Node.prototype.dialog = function(params){
  if (params=="close"){
    if (this._dialogElement) this._dialogElement.close();
    return;
  }
  const container = document.createElement("DIV");
  container.classList.add("ui-dialog","ui-widget","ui-widget-content","ui-corner-all",
                          "ui-front","ui-dialog-buttons","ui-draggable","ui-resizable");
  const titleBar = document.createElement("DIV");
  titleBar.classList.add("ui-dialog-titlebar","ui-widget-header","ui-corner-all","ui-helper-clearfix");
  const titleSpan = document.createElement("SPAN");
  titleSpan.classList.add("ui-dialog-title");
  titleSpan.innerHTML = params.title;
  // const closeButton = document.createElement("BUTTON");
  // closeButton.classList.add("ui-button","ui-widget","ui-state-default",
  //                           "ui-corner-all","ui-button-icon-only","ui-dialog-titlebar-close");
  titleBar.append(titleSpan);
  // titleBar.append(closeButton);
  container.append(titleBar);
  this.classList.add("ui-dialog-content","ui-widget-content");
  container.append(this);
  const footerDiv = document.createElement("DIV");
  footerDiv.classList.add("ui-dialog-buttonpane","ui-widget-content","ui-helper-clearfix");
  const buttonSet = document.createElement("DIV");
  buttonSet.classList.add("ui-dialog-buttonset");
  for (let b in params.buttons){
    const button = document.createElement("BUTTON");
    button.classList.add("ui-button","ui-widget","ui-state-default","ui-corner-all","ui-button-text-only");
    const buttonSpan = document.createElement("SPAN");
    buttonSpan.classList.add("ui-button-text");
    buttonSpan.innerText = b;
    button.append(buttonSpan);
    if (params.buttons[b] instanceof Function)
      button.addEventListener('click', ()=>params.buttons[b].apply(this));
    buttonSet.append(button);
  }
  footerDiv.append(buttonSet);
  container.append(footerDiv);
  container.style.width = (params.width?params.width+"px":"auto");
  container.style.height = (params.height?params.height+"px":"auto");
  container.style.position = 'absolute';
  container.style.display = 'block';
  const overlay = document.createElement("DIV");
  overlay.classList.add("ui-widget-overlay","ui-front");
  const closeThis = ()=>{
    if (params.beforeClose instanceof Function) params.beforeClose.apply(this);
    container.remove();
    overlay.remove();
  }
  if (params.closeOnEscape) document.addEventListener('keydown', e=>{
    if (e.key=="Escape") closeThis();
  });
  if (params.resizable){
    // create buttons...
  }
  container.close = closeThis;
  this._dialogElement = container;
  document.body.append(overlay);
  document.body.append(container);
  return this;
};


let route = {};
if (window.Guide && window.Guide.route) route = window.Guide.route;

const before_init = [], after_init = [];

let guides_initiated = false;

// A step is basically a promise associated to a guide
class Step {
  constructor(guide, f, name){
    this._guide = guide;
    this._action = f;
    this._name = name;
    const n = this._guide._steps.length;
    const label = (typeof name==="string"?`${n+1}: ${this._name}`:`Step #${n+1}`);
    const option = document.createElement("OPTION");
    option.value = n;
    option.innerText = label;
    this._guide._stepsNavigator.appendChild(option);
  }
  run(){
    if (!this._guide._launched||this._guide._complete===true||this._guide._dismissed===true||this._guide._active===false) return;
    this._guide._counterpid = (this._guide._counterpid||0) + 1;
    this._pid = this._guide._counterpid;
    // Update guide's step index first
    const stepIndex = this._guide._steps.indexOf(this);
    this._guide._currentStep = stepIndex;
    // Append the guide's dismiss button while a step is running
    document.querySelector("body").appendChild( this._guide._bottomBar );
    this._guide._stepsNavigator.querySelectorAll('option').forEach(n=>{
      if (n.value==stepIndex) n.selected = true;
      else n.selected=false;
    });
    this._guide._stepsNavigator.dispatchEvent(new Event('change'));
    
    // This will run after the step's function has run
    const completeIfLastStep = () => {
      // If _currentStep has changed, a new step was called
      if (this._guide._currentStep != stepIndex) return;
      // If not, the guide is complete
      else this._guide.complete();
    };
    // Run action
    if (this._action instanceof Function){
      const action = this._action.call(this._guide);
      // action is a promise if _action is async or explicitly returns a Promise
      if (action instanceof Promise)
        action.then( completeIfLastStep ).catch( ()=>this._guide._bottomBar.hide() );
      else // if not a promise, immediately check if complete
        completeIfLastStep();
    }
    else // If steps are properly created, this 'else' should never happen
      completeIfLastStep();
  }
}

// Keep track of guides to avoid re-creating them (esp. with Guide.reset)
const guides = {};

// A guide encapsulates steps and has a few properties
class Guide {
  // Guides are (re-)created on each page load, with localStorage+server for persistency
  constructor(name){
    if (guides.hasOwnProperty(name)) return guides[name];
    // Properties prefixed with _ (unlike methods)
    this._name = name;
    this._steps = [];
    this._docReady = false; // Whether DOM has been loaded
    this._init = false;     // Whether the server responded
    this._gotData = false;  // Whether the server sent data
    this._launched = false; // Whether the guide started

    // Callbacks for channel -- see init_channel below
    this._before_init = [];
    this._after_init = [];
    this._before_data = [];
    this._after_data = [];
  
    // To declare a property using the proxy above
    const local = {};
    const localProperty = p => Object.defineProperty(this,p, {
      get(){ return local[p]; },
      set(value){ 
        local[p] = value;
        this.update_channel();  // Send update to server
        return true;
      }
    });
    localProperty("_currentStep");  // Index of current step
    localProperty("_firstStep");    // Index of first step
    localProperty("_complete");     // Whether the last step was reached*
    localProperty("_active");       // If false, guide won't start*
    localProperty("_dismissed");    // Just a flag, no effect in guide.js
    localProperty("_misc");         // A string (possibly a JSONed hash) to store misc values as needed
    // * {_complete: true, _dismissed: true, _active: false} means permanent dismissal


    this._resetButton = document.createElement("BUTTON");
    this._resetButton.classList.add("resetButton");
    this._resetButton.innerText = 'Reset';
    this._resetDialogBox = document.createElement("DIV");
    this._resetDialogBox.classList.add("resetDialogBox");
    let resetDialogOpen = false;
    this._resetButton.addEventListener('click', () => {
      if (resetDialogOpen) return;
      resetDialogOpen = true;
      let diaglogClose = false;      //Created this variable so that default X/cross of the dialog box don't close it, and make user use the cancel button instead
      // $(this._resetDialogBox).dialog({
      this._resetDialogBox.dialog({  
        title: "Are You Sure?",
        // appendTo: ".tooltip.cover",
        resizable: true,
        width: 350,
        closeOnEscape: false,
        modal: true,
        buttons: {
          Reset: () => {
            diaglogClose = true;
            this.reset(/*launch=*/true);
            // $(this._resetDialogBox).dialog( "close" );
            this._resetDialogBox.dialog( "close" );
          },
          Cancel: () => {
            diaglogClose = true;
            // $(this._resetDialogBox).dialog( "close" );
            this._resetDialogBox.dialog( "close" );
          }
        },
        beforeClose: function () {
          resetDialogOpen = false;
          return diaglogClose;
        }
      });
      this._resetDialogBox.innerHTML = `This will go back to the first step of <em>${name}</em>.`;
    });

    this._dismissButton = document.createElement("BUTTON");
    this._dismissButton.classList.add("dismissButton");
    this._dismissButton.innerText = "Dismiss";
    this._dismissDialogBox = document.createElement("DIV");
    this._dismissDialogBox.classList.add("dialogBox");
    this._dismissButton.addEventListener('click', () => {
      let diaglogClose = false;      //Created this variable so that default X/cross of the dialog box don't close it, and make user use the cancel button instead
      // $(this._dismissDialogBox).dialog({
      this._dismissDialogBox.dialog({
        title: "Are You Sure?",
        // appendTo: ".tooltip.cover",
        resizable: true,
        width: 350,
        closeOnEscape: false,
        modal: true,
        buttons: {
          Dismiss: () => {
            diaglogClose = true;
            this.dismiss()            // To Dismiss the guide
            // $(this._dismissDialogBox).dialog( "close" );
            this._dismissDialogBox.dialog( "close" );
          },
          Cancel: () => {
            diaglogClose = true;
            // $(this._dismissDialogBox).dialog( "close" );
            this._dismissDialogBox.dialog( "close" );
          }
        },
        beforeClose: function () {
          return diaglogClose;
        }
      });
      this._dismissDialogBox.innerHTML = `This will terminate <em>${name}</em>.`;
    });

    this._stepsNavigator = document.createElement("SELECT");
    const nameSpan = document.createElement("SPAN");
    nameSpan.classList.add("guide","name");
    nameSpan.innerText = `${name} Guide`;
    const buttonsDiv = document.createElement("DIV");
    buttonsDiv.classList.add("buttons");
    buttonsDiv.appendChild(this._resetButton);
    buttonsDiv.appendChild(this._dismissButton);
    this._bottomBar = document.createElement("DIV");
    this._bottomBar.classList.add("guide","bottomBar");
    this._bottomBar.appendChild(nameSpan);
    this._bottomBar.appendChild(this._stepsNavigator);
    this._bottomBar.appendChild(buttonsDiv);
    
    this._stepsNavigator.addEventListener("change", ()=>{
      if (this._complete===true||this._dismissed===true||this._active===false||this._halted===true) return;
      const n = this._stepsNavigator.value;
      if (n>=0 && n<this._steps.length && n!=this._currentStep){
        this.closeTooltips();
        this._steps[n].run();
        console.log("Moving to step #"+n);
      }
      // Resizing
      const select = this._stepsNavigator;
      const text = select.querySelector(`option[value='${n}']`).innerText;
      const test = document.createElement("SELECT");
      const option = document.createElement("OPTION");
      option.selected = true;
      option.innerText = text;
      test.appendChild(option);
      this._bottomBar.appendChild(test);
      const width = window.getComputedStyle(test).width;
      test.remove();
      select.style.width = width;
    });

    const keepDialogOrBottomBarOnTop = ()=>{
      const z = maxZ();
      if (this._dismissDialogBox.isVisible()){
        const container = this._dismissDialogBox.parentElement, overlay = container.previousSibling;
        if (window.getComputedStyle(container)["z-index"]!=z) container.style["z-index"] = z+1;
        if (overlay && window.getComputedStyle(overlay)["z-index"]!=z) overlay.style["z-index"] = z;
      }
      else if (this._resetDialogBox.isVisible()){
        const container = this._resetDialogBox.parentElement, overlay = container.previousSibling;
        if (window.getComputedStyle(container)["z-index"]!=z) container.style["z-index"] = z+1;
        if (overlay && window.getComputedStyle(overlay)["z-index"]!=z) overlay.style["z-index"] = z;
      }
      else if (this._bottomBar.isVisible() && window.getComputedStyle(this._bottomBar)["z-index"]!=z)
        this._bottomBar.style["z-index"] = z+1;
      window.requestAnimationFrame( keepDialogOrBottomBarOnTop );
    }
    keepDialogOrBottomBarOnTop();
 
    guides[name] = this;

    if (guides_initiated)
      this.init();
  }
  // Close all of the guide's tooltips
  closeTooltips(){
    if (this._tooltips instanceof Array)
      for (let i = 0; i < this._tooltips.length; i++)
        if (this._tooltips[i] instanceof Node) this._tooltips[i].parentElement.remove();
        // if (this._tooltips[i] instanceof jQuery) this._tooltips[i].parent().remove();
  }
  // Complete the guide
  complete(){
    console.log("Completing "+this._name);
    this.closeTooltips();
    this._currentStep = -1;
    this._complete = true;
    this._bottomBar.hide();
    // if (this._bottomBar instanceof jQuery) this._bottomBar.hide();
  }
  // Dismisse the guide
  dismiss(){
    this._bottomBar.hide();
    this._dismissed = true;
    this.closeTooltips();
  }
  // Initiate the guide after all the guide scripts have been processed
  init(){
    if (this._halted) return;
    this.channel = GuideChannel.create( this._name , 
    () => {                   // on_init
      this._before_init.map( f=>f instanceof Function && f.call(this) );
      this._init = true;
      this.channel.get();
      this._after_init.map( f=>f instanceof Function && f.call(this) );
    }, 
    data => {                 // on_data
      data = JSON.parse(data);
      this._before_data.map( f=>f instanceof Function && f.call(this, data) );
      // Priority to the server's settings (in case localStorage was wiped)
      if (data.currentstep!==null&&data.currentstep>=0&&data.currentstep<this._steps.length) 
        this._currentStep = data.currentstep;
      if (data.complete!==null) this._complete = data.complete;
      if (data.active!==null) this._active = data.active;
      if (data.dismissed!==null) this._dismissed = data.dismissed;
      if (data.misc!==null) this._misc = data.misc;
      this._gotData = true;
      this.launch();          // Try to launch
      this._after_data.map( f=>f instanceof Function && f.call(this, data) );
    });
  }
  // Prevent the guide from initiating
  halt() {
    this._halted = true;
  }
  before_init(f) { 
    this._before_init.push(f);
    return this;
  }
  after_init(f) { 
    this._after_init.push(f);
    return this;
  }
  before_data(f) { 
    this._before_data.push(f);
    return this;
  }
  after_data(f) { 
    this._after_data.push(f);
    return this;
  }
  // Send localStorage's data to the server
  update_channel() {
    if (!this.channel || !this._gotData) return;
    this.channel.update({
      firststep: this._firstStep,
      nsteps: this._steps.length,
      currentstep: this._currentStep,
      active: this._active,   // Hardcoded for now
      complete: this._complete,
      dismissed: this._dismissed,
      misc: this._misc
    });
  }
  // Add a step to the guide
  step(name, f) {
    if (f===undefined && name instanceof Function)
      f = name;
    const s = new Step(this, f, name);
    this._steps.push(s);
    return ()=>s.run();
  }
  // Sets which step runs first
  startWith(step){
    if (step instanceof Step){
      let index = this._steps.indexOf(step);
      // Add step if not part of guide yet
      if (index<0) {
        index = this._steps.length;
        this._steps.push(step);
      }
      this._firstStep = index;
    }
  }
  // Try to launch the guide
  launch(){
    console.log("Trying to launch", this._name);
    if (this._launched || !this._steps.length || this._complete || this._dismissed || !this._init || !this._gotData || this._active===false) 
      return;
    console.log("Launching", this._name);
    // Run current step if defined
    // $(document).ready( () => {
    const callback = ()=>{
      if (this._launched) return;
      this._launched = true;
      if (!isNaN(this._currentStep) && this._currentStep>=0 && this._currentStep<this._steps.length)
        this._steps[this._currentStep].run();
      // Run first step otherwise
      else
        this._steps[this._firstStep||0].run();
    };
    if (document.readyState === "complete" || (document.readyState !== "loading" && !document.documentElement.doScroll))
      callback();
    else
      document.addEventListener("DOMContentLoaded", callback);
  }
  // This resets the guide, both on localStorage and on the server
  reset(launch=false){
    this.closeTooltips();
    this._currentStep = this._firstStep||0;
    this._complete = false;
    this._active = true;
    this._dismissed = false;
    this._launched = false;
    if (launch) this.launch();
    return this;
  }
  // Returns the dictionary of guides
  static guides = guides;
  // This checks the page's "route" as represented in rails (see views/layouts/application.html)
  static route(...args){
    if (route===undefined) return false;
    if (args[0] && args[0] instanceof Array){
      const params = Object.keys(route);
      for (let i = 0; i < args[0].length && i < params.length; i++)
        if (route[params[i]] != args[0][i]) return false;
      return true;
    }
    else if (route && route.hasOwnProperty(args[0])) return route[args[0]];
    else return undefined;
  }
  static get tte() { return tte; }
  static set tte(v) { /* void */ }
  // Helper function to extend objects
  static extend(old,incoming){ return extend(old,incoming); }
  // Before any init method is called (but all scripts were run)
  static before_init(f){
    before_init.push(f);
  }
  // After all init methods have been called
  static after_init(f){
    after_init.push(f);
  }
  debug(on=true){
    this._debug = on;
  }
  promise(f){
    const pid = this._counterpid;
    const promise = new Promise(f);
    return new Promise(r=>promise.then( e=>this._counterpid==pid&&r(e) ));
  }
  // This returns a promise that gets resolved when an element matching selector is added on the page
  async wait(selector,disappear,xpath=false){
    const check = r=>{
      if (this._complete===true || this._dismissed===true || this._active===false) return;
      let element;
      if (xpath) 
        element = document.evaluate(selector,document,null,XPathResult.FIRST_ORDERED_NODE_TYPE,null).singleNodeValue;
      else 
        element = document.querySelector(selector);
      if (element && element.isVisible()){
        element._tooltip = extend({guide: this}, element._tooltip);
        element._selector = [selector,xpath];
        element.tte = (text, ...args) => tte.call(element, text, ...args);
        if (disappear) window.requestAnimationFrame(()=>check(r));
        else r(element);
      }
      else {
        if (disappear) r(element);
        else window.requestAnimationFrame(()=>check(r));
      }
    }
    return this.promise(r=>check(r));
  }
}

export { Guide };


// Require all the (other) js files in this directory
const guideScripts = import.meta.glob("./*.js");
const initGuides = ()=>{
  // Callback before init
  before_init.map( f=>f instanceof Function && f.call() );
  // Initiate the guides' channels
  for (let g = 0; g < guides.length; g++) guides[g].init();
  guides_initiated = true;
  after_init.map( f=>f instanceof Function && f.call() );
}
let loadedGuides = 0;
for (const key in guideScripts) {
  if (key === "./guide.js") continue;
  guideScripts[key]().then(()=>{
    loadedGuides++;
    if (loadedGuides>=Object.keys(guideScripts).length) initGuides();
  });
}

// Comment this out when done debugging
window.Guide.reset = name => guides[name]&&guides[name].reset().update_channel();

// The code below adds a custom tte "tooltip" jQuery method
//
const parseTTParam = function(p,q,o) {
  if (typeof(p)=="string"){
    if (p.match(/^click$/i)) this.click = ">>";
    else if (p.match(/^cover/i)) this.cover = true;
    else if (p.match(/^pointer/i)) this.pointer = true;
    else if (p.match(/^(outline|border)/i)) this.outline = true;
    else if (p.match(/^hover/i)) this.hover = true;
    else if (p.match(/^top|above$/i)) this.y = 'above';
    else if (p.match(/^center|middle$/i)) {
      if (typeof(q)=="string" && q.match(/^top|above|bottom|below$/i) || 
          typeof(o)=="string" && o.match(/^top|above|bottom|below$/i))
        this.x = 'center';
      else if (typeof(q)=="string" && q.match(/^left|right$/i) || 
               typeof(o)=="string" && o.match(/^left|right$/i))
        this.y = 'center';
      else if (typeof(q)=="string" && q.match(/^center|middle$/i))
        this.y = 'center';
      else if (typeof(o)=="string" && o.match(/^center|middle$/i))
        this.x = 'center';
      else {
        this.x = 'center';
        this.y = 'center';
      }
    }
    else if (p.match(/^bottom|below$/i)) this.y = 'below';
    else if (p.match(/^left$/i)) this.x = 'left';
    else if (p.match(/^right$/i)) this.x = 'right';
    else if (this.click !== false && !p.match(/\s/)) this.key = p;
    else this.click = p;
  }
  else if (!isNaN(p) && p > 0)
    this.timeout = p;
  else if (p instanceof Object) {
    for (let n in p)
      this[n] = p[n];
  }
  return this;
}
//
const tooltips = [];
if (window.jQuery)
  jQuery.prototype.tte = function(text, ...args){ 
    let r = null;
    this.each( (i,n) => r = e.tte(text,...args) );
    return $(r);
  }
const tte = function(text, ...args){
  const ttobj = this._tooltip;
  ttobj._target = this;
  if (ttobj.guide && ttobj.guide instanceof Guide && (
        ttobj.guide._dismissed===true ||
        ttobj.guide._active===false ||
        ttobj.guide._complete===true
  )) return this;

  let params = {};
  for (let i = 0; i < args.length; i++)
    parseTTParam.call(params, args[i], i==args.length-1||args[i+1], i==0||args[i-1]);

  if (typeof(text)=="string") params.content = text;
  else parseTTParam.call(params, text);

  let currentTooltips = [];

  const resolve = [()=>null];
  const tooltip = document.createElement("DIV");
  tooltip.classList.add("tooltip","container");
  const cover = document.createElement("DIV");
  cover.classList.add("tooltip","cover");
  cover.appendChild(tooltip);
  const existingParams = ttobj.params;
  if (!isNaN(existingParams) && existingParams>-1 && existingParams < tooltips.length)
    ttobj.params = extend(params, tooltips[existingParams]);
  else {
    ttobj.params = extend(params, {
      content: "", 
      click: "&raquo;", 
      key: false, 
      timeout: false,
      hover: false,
      x: 'center', y: 'below', 
      cover: false, 
      outline: false,
      promise: null
    });
    ttobj.data = {tooltip: tooltips.length};
    tooltips.push(ttobj.params);
  }
  
  if (params.promise===undefined) ttobj.params.promise = undefined;
  if (params.condition===undefined) ttobj.params.condition = ()=>true;
  else if (typeof params.condition != "function") throw Error("tte.condition should be a function");
  if (params.loseCondition===undefined) ttobj.params.loseCondition = undefined;

  tooltip.innerHTML = '';
  const content = document.createElement("DIV");
  content.classList.add("content");
  content.innerHTML = ttobj.params.content;
  tooltip.appendChild(content);
  if (ttobj.params.click) {
    const button = document.createElement("DIV");
    button.classList.add("submit");
    resolve.push(r=>button.addEventListener('click',r));
    if (typeof(ttobj.params.click)=="string") button.innerHTML = ttobj.params.click;
    else button.innerHTML = "&raquo;";
    tooltip.appendChild(button);
  }
  if (ttobj.params.key)
    resolve.push(r=>document.addEventListener('keydown', ev=>{
        if (
            ttobj.params.key === true
            ||
            (typeof(ttobj.params.key)=="string" && ttobj.params.key.toLowerCase() == ev.key.toLowerCase())
            ||
            (ttobj.params.key instanceof Array && ttobj.params.key.filter(k=>String(k).toLowerCase() == ev.key.toLowerCase()).length)
          )
          r();
      }));
  if (!isNaN(ttobj.params.timeout) && ttobj.params.timeout > 0)
    resolve.push(r=>setTimeout(r,ttobj.params.timeout));
  if (ttobj.params.hover)
    resolve.push(r=>ttobj._target.addEventListener('mouseenter', r));
  if (ttobj.params.promise)
    resolve.push(ttobj.params.promise);

  // Resolve promise only if still running the same step('s instance)
  let conditionMet = ttobj.params.condition.call(ttobj,ttobj);
  const pid = ttobj.guide._counterpid;
  let promiseMarker = {};
  ttobj.promiseMarker = promiseMarker;
  let tryToResolve;
  // ttobj.promise = new Promise(r=>{
  ttobj._target.promise = new Promise(r=>{
    tryToResolve = marker=>{
      if (ttobj.guide._counterpid==pid&&conditionMet&&ttobj.promiseMarker==marker)
        r();
    }
  });
  // Evaluate promiseMarker right away
  (m=>Promise.any(resolve.map(p=>new Promise(p))).then(()=>tryToResolve(m)))(promiseMarker);
  
  // $(document.body).append(cover);
  document.body.appendChild(cover);

  let assisting = false, resolved = false;
  if (ttobj.params.loseCondition instanceof Function){
    const callbackCondition = async ()=>{
      if (resolved || ttobj.guide._counterpid!=pid || assisting) return;
      if (!tooltip.inDOM()) return;
      conditionMet = ttobj.params.condition.call(ttobj,ttobj);
      if (!conditionMet){
        assisting = true;
        // Don't solve this promise while assisting
        promiseMarker = {};
        ttobj.promiseMarker = promiseMarker;
        cover.hide();
        await ttobj.params.loseCondition.call(ttobj,ttobj);
        if (!ttobj._target || !ttobj._target.inDOM()){
          if (this._selector && this._selector[1])
            ttobj._target = document.evaluate(this._selector[0],document,null,XPathResult.FIRST_ORDERED_NODE_TYPE,null).singleNodeValue
          else if (this._selector)
            ttobj._target = document.querySelector(this._selector[0]);
        }
        cover.show();
        updateDisplay();
        assisting = false;
        (m=>Promise.any(resolve.map(p=>new Promise(p))).then(()=>{
          resolved=true;
          cover.remove();
          tryToResolve(promiseMarker);
        }))(promiseMarker); // Evaluate promiseMarker right away
        window.requestAnimationFrame(callbackCondition);
      }
      else
        window.requestAnimationFrame(callbackCondition);
    }
    callbackCondition();
  }
  
  const pointer = document.createElement("DIV");
  pointer.classList.add("pointer");
  cover.append(pointer);

  let offset, ownoffset;
  const old_scroll = [0,0];
  const updateDisplay = ()=>{
    if (!ttobj._target.inDOM()){
      if (this._selector && this._selector[1])
        ttobj._target = document.evaluate(this._selector[0],document,null,XPathResult.FIRST_ORDERED_NODE_TYPE,null).singleNodeValue
      else if (this._selector)
        ttobj._target = document.querySelector(this._selector[0]);
    }
    // Stop updating once an element disappears
    if (!ttobj._target || !ttobj._target.isVisible() || !tooltip.isVisible())
      return;
    let new_offset = ttobj._target.getBoundingClientRect(), 
        new_ownoffset = tooltip.getBoundingClientRect();
    const new_scroll = [window.scrollX,window.scrollY];
    window.requestAnimationFrame(updateDisplay);
    // Don't need to update if no param has changed
    if (JSON.stringify(offset)==JSON.stringify(new_offset) &&
        JSON.stringify(ownoffset)==JSON.stringify(new_ownoffset) &&
        new_scroll[0]==old_scroll[0] && new_scroll[1]==old_scroll[1])
      return;
    old_scroll[0] = new_scroll[0];
    old_scroll[1] = new_scroll[1];
    offset = new_offset;
    ownoffset = new_ownoffset;
    let width = offset.width, height = offset.height;
    let ownWidth = ownoffset.width, ownHeight = ownoffset.height;
    let xTimes, yTimes, xMargin = 0, yMargin = 0;
    let newtop = 0, newleft = 0;
    if (ttobj.params.x.match(/right/i)){
      tooltip.classList.add('right');
      xTimes = 1;
      xMargin = parseInt(window.getComputedStyle(tooltip)["margin-left"]);
      newleft = new_offset.right;
      if (ttobj.params.pointer) {
        pointer.style.left = new_offset.right+"px";
        pointer.style.top = Number(new_offset.top+new_offset.width/2)+"px";
        pointer.classList.add("right");
      }
    }
    else if (ttobj.params.x.match(/center|middle/i)){
      tooltip.classList.add('center');
      xTimes = 0.5;
      newleft = new_offset.left + (new_offset.width/2) - ownWidth/2;
    }
    else {
      tooltip.classList.add('left');
      xTimes = 0;
      xMargin = -1 * parseInt(window.getComputedStyle(tooltip)["margin-right"]);
      newleft = new_offset.left - ownWidth;
      if (ttobj.params.pointer) {
        pointer.style.left = new_offset.left+"px";
        pointer.style.top = Number(new_offset.top+new_offset.width/2)+"px";
        pointer.classList.add("left");
      }
    }
    if (ttobj.params.y.match(/above|top/i)){
      tooltip.classList.add('above');
      yTimes = 1;
      yMargin = -1 * parseInt(window.getComputedStyle(tooltip)["margin-bottom"]);
      newtop = new_offset.top - ownHeight;
      if (ttobj.params.pointer) {
        pointer.style.top = new_offset.top+"px";
        pointer.style.left = Number(new_offset.left+new_offset.width/2)+"px";
        pointer.classList.add("above");
      }
    }
    else if (ttobj.params.y.match(/center|middle/i)){
      tooltip.classList.add('vertical-center');
      yTimes = 0.5;
      newtop = new_offset.top + (new_offset.height/2) - ownHeight/2;
    }
    else {
      tooltip.classList.add('below');
      yTimes = 0;
      yMargin = parseInt(window.getComputedStyle(tooltip)["margin-bottom"]);
      newtop = new_offset.bottom;
      if (ttobj.params.pointer) {
        pointer.style.top = new_offset.bottom+"px";
        pointer.style.left = Number(new_offset.left+new_offset.width/2)+"px";
        pointer.classList.add("below");
      }
    }
    if (newtop<0) newtop = 20;
    if (newtop+ownHeight>window.innerHeight) newtop = window.innerHeight-ownHeight-20;
    if (newleft<0) newleft = 20;
    if (newleft+ownWidth>window.innerWidth) newleft = window.innerWidth-ownWidth-20;
    tooltip.style.top = newtop+"px";
    tooltip.style.left = newleft+"px";
    tooltip.style['z-index'] = maxZ()+2;
    cover.style['z-index'] = maxZ();

    cover.childNodes.forEach( n => n.nodeName=="CANVAS" && n.remove() );
    if (ttobj.params.cover){
      const docWidth = window.innerWidth, docHeight = window.innerHeight;
      const canvas = document.createElement("CANVAS");
      canvas.width = docWidth;
      canvas.height = docHeight;
      const ctx = canvas.getContext("2d");
      ctx.beginPath();
      ctx.fillRect(0, 0, offset.left-10, docHeight);
      ctx.fillRect(0, 0, docWidth, offset.top-10);
      ctx.fillRect(offset.left+width+10, 0, docWidth, docHeight);
      ctx.fillRect(0, offset.top+height+10, docWidth, docHeight);
      canvas.style.position = "absolute";
      canvas.style['pointer-events'] = 'none';
      canvas.style.opacity = 0.5;
      cover.prepend(canvas);
    }
    if (ttobj.params.outline){
      let border = "solid 2px cyan";
      if (typeof(ttobj.params.outline)=="string") border = ttobj.params.outline;
      cover.childNodes.forEach( n => n.classList.contains("outline") && n.remove() );
      const outline = document.createElement("DIV");
      outline.style.position = 'absolute';
      outline.classList.add("outline");
      cover.append(outline);
      outline.style.top = offset.top-1;
      outline.style.left = offset.left-1;
      outline.style.width = width+2;
      outline.style.height = height+2;
      outline.style.border = border;
      outline.style['z-index'] = maxZ()+1;
    }
  }
  updateDisplay();

  if (ttobj.guide && ttobj.guide instanceof Guide)
    ttobj.guide._dismissButton.style["z-index"] = maxZ()+3;

  ttobj._target.promise.then( ()=>cover.remove() );
  
  currentTooltips.push(tooltip);

  ttobj._target.tooltips = currentTooltips;
  if (ttobj.guide && ttobj.guide instanceof Guide){
    if (ttobj.guide._tooltips===undefined) ttobj.guide._tooltips = [];
    ttobj.guide._tooltips = [...ttobj.guide._tooltips, ...currentTooltips];
  }
  return ttobj._target;
};

export const event = new EventTarget();
event.dispatch = function(node,type){
  event.dispatchEvent(new CustomEvent(type, {detail:node}));
  return {
    // update(){

    // },
    destroy() {
      event.dispatchEvent(new CustomEvent('destroy_'+type, {detail: node}));
    }
  }
}
