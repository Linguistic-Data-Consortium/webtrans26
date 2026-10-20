<script>
  let { name = "Guest" } = $props();

  let count = $state(0);

  function increment() {
    count += 1;
  }

  // Svelte 5 effect using $effect rune (optional, for demonstration)
  // $effect(() => {
  //   console.log(`hello_world component received name: ${name}, count is: ${count}`);
  // });
</script>

<div class="p-6 max-w-md mx-auto bg-white rounded-xl shadow-lg flex flex-col items-center space-y-4 border border-blue-200">
  <div class="text-3xl font-bold text-blue-600">
    Hello, <span class="italic">{name}</span>!
  </div>
  <p class="text-slate-600">This is a Svelte 5 component styled with Tailwind CSS.</p>
  <button
    class="px-6 py-2 bg-green-500 hover:bg-green-600 text-white font-semibold rounded-lg shadow-md focus:outline-none focus:ring-2 focus:ring-green-400 focus:ring-opacity-75 transition duration-150 ease-in-out"
    onclick={increment}
  >
    Clicked {count} {count === 1 ? 'time' : 'times'}
  </button>
</div>
