// app/frontend/entrypoints/application.js
console.log('Vite ⚡️ Ruby + Svelte 5 + Tailwind CSS is running')

// Import global CSS
// import './application.css'
import '../src/app.css'
// The screen lock, on every signed-in page (lib/idle_lock.js).
import { start_idle_lock_from_page } from '../lib/idle_lock';
start_idle_lock_from_page();
import './custom.css'
// import { mount } from 'svelte'
// import Header from '../header.svelte'
// const h = {}
// const header = mount(Header, {
//   target: $('.Header')[0],
//   props: h
// });

// --- Stimulus Setup ---
import { Application } from '@hotwired/stimulus'
const stimulusApp = Application.start()
// Configure Stimulus development experience
stimulusApp.debug = false // Set to true for debugging
window.Stimulus = stimulusApp // Expose for convenience

// Import and register your Stimulus controllers
// (Assuming hello_controller.js is in app/javascript/controllers/)
import HelloController from '../../javascript/controllers/hello_controller.js'
stimulusApp.register('hello', HelloController)
// Register other Stimulus controllers here

// --- Svelte Component Mounting ---
import { mountSvelteComponents } from '../mount.js'
mountSvelteComponents()
