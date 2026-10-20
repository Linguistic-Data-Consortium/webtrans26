// app/frontend/entrypoints/application.js
console.log('Vite ⚡️ Ruby + Svelte 5 + Tailwind CSS is running')

// Import global CSS
// import './application.css'
import '../guides/guide.js'
import '../src/app.css'
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
