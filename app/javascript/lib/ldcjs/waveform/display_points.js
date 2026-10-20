// How many samples of a decoded buffer the canvas can actually plot, one point
// per sample (the zoomed-in "line" drawing mode).
//
// The buffer and the window it's drawn against are computed at different
// moments — a fetch is in flight while the window moves — so a buffer covering
// far more audio than the window can arrive. Plotting all of it built an array
// of two entries per sample; past 2^31 samples that throws "RangeError:
// Invalid array length", and long before that it's just wasted work, since only
// width * samples_per_pixel samples are visible.
function display_point_count(buffer_length, width, samples_per_pixel){
  const length = Number(buffer_length);
  if(!Number.isFinite(length) || length <= 0) return 0;
  const visible = Number(width) * Number(samples_per_pixel);
  if(!Number.isFinite(visible) || visible <= 0) return 0;
  return Math.min(Math.floor(length), Math.ceil(visible) + 1);
}

export { display_point_count };
