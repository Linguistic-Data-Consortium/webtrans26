// A Svelte component loader that works with data attributes and Turbo
import { mount } from 'svelte';

// Import all Svelte components from the components directory using Vite's import.meta.glob
const svelteComponentModules = import.meta.glob('./components/**/*.svelte', { eager: true });
const svelteComponentModules2 = import.meta.glob('./lib/**/*.svelte', { eager: true });

function findComponent(name) {
  let path = `./components/${name}.svelte`;
  let module = svelteComponentModules[path];
  if (module && module.default) {
    return module.default;
  }
  path = `./lib/ldcjs/waveform/${name}.svelte`;
  module = svelteComponentModules2[path];
  if (module && module.default) {
    return module.default;
  }
  console.error(`Svelte component "${name}" not found at ${path}. Available:`, Object.keys(svelteComponentModules));
  return null;
}

function mountComponent(element) {
  if (element.dataset.svelteMounted) return;

  const componentName = element.dataset.svelteComponent;
  const Component = findComponent(componentName);

  if (Component) {
    const props = JSON.parse(element.dataset.props || '{}');
    props.ldc = window.ldc;
    element.innerHTML = '';
    mount( Component, { target: element, props } );
    element.dataset.svelteMounted = true;
  }
}

export function mountSvelteComponents() {
  const svelteComponents = document.querySelectorAll('[data-svelte-component]');
  for (const component of svelteComponents) {
    mountComponent(component);
  }
}

// Re-run mounting after Turbo navigates
document.addEventListener('turbo:load', () => {
  mountSvelteComponents();
});

// Initial mount on DOMContentLoaded
document.addEventListener('DOMContentLoaded', () => {
  mountSvelteComponents();
});
