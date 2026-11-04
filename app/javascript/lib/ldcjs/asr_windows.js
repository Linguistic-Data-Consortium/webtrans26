// How many windows the speech-recognition pipeline will cut a recording into,
// so a run can say "part 2 of 5". Mirrors the loop in transformers.js's
// automatic-speech-recognition pipeline (_call_whisper): windows of
// chunk_length_s, each starting chunk − 2·stride after the last, until one
// reaches the end.
export function window_count(n_samples, { sampling_rate = 16000, chunk_length_s = 30, stride_length_s = 5 } = {}){
    const window = sampling_rate * chunk_length_s;
    const jump = window - 2 * sampling_rate * stride_length_s;
    let n = 1;
    for(let offset = 0; offset + window < n_samples; offset += jump) n++;
    return n;
}

// The pipeline calls the model's generate once per 30 s window. With
// timestamps, Whisper's generate may then make more than one pass inside it —
// a seek loop that re-encodes the rest of a window the model stopped short of
// (modeling_whisper.js, _generate_with_seek) — and each pass ends the
// streamer, so a streamer counts passes, not windows. Windows are counted
// here, at the call the pipeline makes: `on_window` is called as each one's
// generate returns. Wrapped once per model, however many runs use it.
export function count_windows(model, on_window){
    if(model.__counts_windows) return;
    const generate = model.generate.bind(model);
    model.generate = async (args) => {
        const out = await generate(args);
        on_window();
        return out;
    };
    model.__counts_windows = true;
}

// Whisper's decoder holds 448 tokens (max_target_positions) and a window's
// prompt takes a few; this leaves room for them.
export const SINGLE_PASS_MAX_NEW_TOKENS = 440;

// What the pipeline is asked for. 30 s windows overlapping by 5 s either side
// are what let a recording longer than Whisper's own window be transcribed at
// all; return_timestamps is what makes the result segments rather than one
// string.
//
// `single_pass` (experimental, per browser): one pass of the model per
// window. With timestamps, transformers.js otherwise runs a seek loop inside
// each window, encoding and generating again over whatever the model stopped
// short of — measured at a second pass on every window, about 30% of a run.
// The pipeline's overlap covers most of that tail anyway; what it can't is a
// model that stops early inside a window. Setting max_new_tokens is what makes
// the library skip the seek loop (modeling_whisper.js, generate).
//
// `language` (a code) tells a multilingual model what it's hearing — it can't
// detect it — and asks it to transcribe, not translate. Never given for an
// English-only model, which refuses one (local_asr.js, run_language).
export function pipeline_options({ timestamps = true, single_pass = false, language = null } = {}){
    const o = { chunk_length_s: 30, stride_length_s: 5, return_timestamps: timestamps !== false };
    if(o.return_timestamps && single_pass) o.max_new_tokens = SINGLE_PASS_MAX_NEW_TOKENS;
    if(language){
        o.language = language;
        o.task = 'transcribe';
    }
    return o;
}

