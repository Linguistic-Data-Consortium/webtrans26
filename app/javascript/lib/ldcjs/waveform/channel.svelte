<script>
    import { getp_wav } from '../getp';
    import { decode_audio_data } from '../audio/main';
    import { activeo, urls, cache, scache, cache2, srcache } from './shared.svelte';
    import { docid2channel } from './helpers';
    import { display_point_count } from './display_points';
    import Underlines from './underlines.svelte';
    let {
        i,
        mousedown_helper,
        mousemove_underlines,
        underline,
        wave_canvas_height,
        width,
        line,
        sample_skip,
        max_only,
        create_audio_hash_from_docid,
        create_audiok_from_docid,
        docids,
        debug,
        activate,
        u
    } = $props();

    let disable_waveform = false;

    let canvas;

    let wave_display_length;
    let wave_display_offset;
    let wave_scale;
    let wave_buffer_sample_rate;
    let wave_display_length_in_samples;
    let wave_display_offset_in_samples;
    let samples_per_pixel;
    const samples_per_pixel_threshold = 200; // for deciding whether to draw an envelope or a graph


    $effect(() => {
        wave_display_length = activeo.wave_display_length;
        wave_display_offset = activeo.wave_display_offset;
        wave_scale = wave_display_length / width;
        draw_waveformi();
    });


    let last_audio;
    let last_buffer;
    function convert_seconds_to_samples(seconds){
        return Math.floor(seconds * wave_buffer_sample_rate);
    }
    function get_audio_buffer_for_waveform(audio){
        let this_audio = [ audio.id.replace(/:[ABCD]$/, ''), audio.btime, audio.etime ].join(':');
        if(this_audio == last_audio){
            return Promise.resolve(last_buffer);
        }
        return get_audio_buffer(audio).then( (buffer) => {
            console.log(`SR ${buffer.sampleRate}`);
            wave_buffer_sample_rate = buffer.sampleRate;
            last_audio = this_audio;
            last_buffer = buffer;
            return buffer;
        } );
    }
    function get_audio_buffer(audio){
        // # url = "/audio_files2?audio_id=#{audio.id}&beg=#{audio.btime}&end=#{audio.etime}"
        // # get url, (data) ->
        // #     audio_context.decodeAudioData(data).then (data) ->
        // #         data
        // # url = "#{bucket}#{audio.id}.wav"
        const unit = audio.block_size;
        // # unit = 1
        // sr = 16000
        // sr = 8000
        const sr = audio.sample_rate;
        const header_size = audio.header_size;
        const b = Math.floor(audio.btime * sr) * unit + header_size;
        const e = Math.floor(audio.etime * sr) * unit + header_size - 1;
        
        return new Promise( (resolve, reject) => {
            // const urls = ldc.resources.urls;
            const k = (audio.uid || audio.id).replace(/:[ABCD]/,'');
            // return set_urls(k).then( (x) => {
            return getp_wav(urls[k], b, e).then( (data) => {
                const a = new Uint8Array(header_size + data.byteLength);
                console.log('HEAD');
                console.log(audio);
                a.set( new Uint8Array(audio.header), 0 );
                a.set( new Uint8Array(data), header_size );
                const f1 = (data) => resolve(data);
                decode_audio_data(a.buffer, f1);
                // # audio_context.decodeAudioData(a.buffer).then (data) ->
                // #     resolve(data)
            } );
            // } );
        } ) ;
    }

    function draw_bufferi(k, samples_per_pixel){
        let ctx = canvas.getContext("2d");
        // let ctx = canvas_ctx[ch][1];
        canvas.width = width; //t.width;
        canvas.height = wave_canvas_height;
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.strokeStyle = 'black';
        ctx.lineWidth = 1;
        ctx.beginPath();
        if(samples_per_pixel > samples_per_pixel_threshold){
            draw_waveform2(ctx, get_cache(k));
        }
        else{
            draw_waveform3(ctx, get_cache(k), samples_per_pixel);
        }
    }

    function draw_waveform2(ctx, points){
        const half_height = wave_canvas_height / 2;
        const quarter_height = half_height / 2;
        const three_quarters_height = half_height + quarter_height;
        // ctx.moveTo 0, half_height
        const scale =  width / ( wave_buffer_sample_rate * wave_display_length );
        let midpoint;
        // if(false && stereo){
        //     midpoint = quarter_height;
        // }
        // else{
            midpoint = half_height;
        // }
        if(!line){
            // console.log "drawing to #{width}"
            for(let i = 0; i <= width; i += sample_skip){
                let ii = i * 2;
                let mx = points[ii] * midpoint;
                // assume min/max symmetry for the moment
                let mn;
                if(max_only){
                    mn = mx * -1;
                }
                else{
                    mn = points[ii+1] * midpoint;
                }
                ctx.moveTo(i, midpoint + mn);
                ctx.lineTo(i, midpoint + mx);
                if(false && stereo){
                    // assume min/max symmetry for the moment
                    if(max_only){
                        mx = points[ii] * quarter_height;
                    }
                    ctx.moveTo(i, three_quarters_height - mx);
                    ctx.lineTo(i, three_quarters_height + mx);
                }
            }
        }
        // if display.line is false
        //     for i in [0..display.points.length-1]
        //         x = i / samples_per_pixel
        //         if display.max_only is true
        //             mx = display.points[i] * midpoint
        //         ctx.lineTo x, midpoint + mx
        ctx.stroke()
    }

    function draw_waveform3(ctx, points, samples_per_pixel){
        const pixels_per_sample = 1 / samples_per_pixel;
        const half_height = wave_canvas_height / 2;
        const quarter_height = half_height / 2;
        const three_quarters_height = half_height + quarter_height;
        // ctx.moveTo 0, half_height
        const scale =  width / ( wave_buffer_sample_rate * wave_display_length );
        let midpoint;
        // if(false && stereo){
        //     midpoint = quarter_height;
        // }
        // else{
            midpoint = half_height;
        // }
        if(!line){
            // console.log "drawing to #{width}"
            for(let i = 0; i <= points.length/2; i += 1){
                let ii = i*2;
                let mx = points[ii] * midpoint;
                ctx.lineTo(i*pixels_per_sample, midpoint + mx);
            }
        }
        ctx.stroke();
    }

    function fill_cache(k, buffer, width, w, wave_canvas_height, sample_skip, samples_per_pixel_threshold, samples_per_pixel){
        let b = samples_per_pixel > samples_per_pixel_threshold;
        let i = docid2channel(k.split('","')[0], docids);
        let x = fill_waveform_display_points(buffer, w, wave_canvas_height, i, !b, sample_skip, samples_per_pixel);
        cache[k] = x[0];
        scache[k] = x[1];
        // srcache[k] = samples_per_pixel;
    }
    function get_cache(k){
        return cache[k];
    }
    function get_scache(k){
        return scache[k];
    }
    function fill_waveform_display_points(buffer, w, wave_canvas_height, ii, line, sample_skip, samples_per_pixel){
        // that = this
        // wave_display_length_in_samples = convert_seconds_to_samples wave_display_length
        // wave_display_offset_in_samples = convert_seconds_to_samples wave_display_offset
        // samples_per_pixel = wave_display_length_in_samples / width
        const half_height = wave_canvas_height / 2;
        const pixels_per_sample = 1 / samples_per_pixel;
        // const ii = stereo ? i : 0;
        const wave_buffer_channel_data = buffer.getChannelData(ii);
        const points = [];
        if(line){
            // Only as many samples as the canvas can show. The buffer can cover
            // far more audio than the window when a fetch outlives the window
            // that asked for it — see display_point_count.
            const n = display_point_count(wave_buffer_channel_data.length, width, samples_per_pixel);
            for(let i = 0; i < n; i += 1){
                let ii = i*2;
                points[ii] = wave_buffer_channel_data[i];
                points[ii+1] = 0;
            }
        }
        else{
            for(let i = 0; i <= width; i += sample_skip){
                let ii = i*2;
                // wave_buffer_channel_data_i = Math.floor(i*samples_per_pixel+wave_display_offset_in_samples)
                let wave_buffer_channel_data_i = Math.floor(i*samples_per_pixel);
                // x = wave_buffer_channel_data[wave_buffer_channel_data_i]
                let mx = 0;
                let mn = 0;
                for(let iii = 0; iii < samples_per_pixel; iii += 1){
                    let xx = wave_buffer_channel_data[wave_buffer_channel_data_i+iii];
                    if(xx > mx) mx = xx;
                    if(xx < mn) mn = xx;
                }
                // points[ii] = if mx > Math.abs(mn) then mx else mn
                points[ii] = mx;
                points[ii+1] = mn;
                // if display.max_only is true
                //     display.points[ii+1] = x
                // if(false && stereo == true){
                //     x = wave_buffer_channel_data2[wave_buffer_channel_data_i]
                //     waveform_display.points2[ii] = x
                //     if waveform_display.max_only is true
                //         waveform_display.points2[ii+1] = x
            }
        }
        scale_points(points);
        return [ points, wave_buffer_channel_data ];
    }
    function scale_points(points){
        let mx = 0;
        let mn = 0;
        // let mx = Math.max(...points);
        // let mn = Math.min(...points);
        for(let i = 0; i < points.length; i++){
            if(points[i] > mx) mx = points[i];
            mn = Math.abs(points[i]);
            if(mn > mx) mx = mn;
        }
        for(let i = 0; i < points.length; i++ ) points[i] /= mx;
    }

    let lastk;
    function draw_waveformi(){
        const audio = create_audio_hash_from_docid(docids[i]);
        const k = create_audiok_from_docid(docids[i]);
        // if(!wave_buffer_sample_rate) return;
        // clear_buffer()
        // if(wave_docid.match(/^s3:/)) return;
        if(cache2[k]){
            if(debug) console.log(`cache hit ${k}`);
            if(k != lastk){
                draw_buffer(k, srcache[k]);
                // if(two){
                //     const docid2 = wave_docid.replace(/_A/g, '_B').replace(':A', ':B');
                //     draw_buffer(create_audiok_from_docid(docid2), 'B', t);
                // }
            }
        }
        else{
            if(debug) console.log(cache2);
            // cache2[k] = true;
            get_audio_buffer_helperi(k, audio);
            // if(wave_docid.match(/_A.wav$/)){
                // two = true;
            // if(two){
            //     w.update_cursor = true;
            //     // w.update_scrollbar = true;
            //     // w.update_underlines = true;
            //     w.update_play_head = true;
            //     // w.update_ticks = true;
            //     // w.update_tick_times = true;
            // 
            //     const docid2 = wave_docid.replace(/_A/g, '_B').replace(':A', ':B');
            //     get_audio_buffer_helper(create_audiok_from_docid(docid2), create_audio_hash_from_docid(docid2), 'B', t);
            // }
        }
        lastk = k;
    }
    function get_audio_buffer_helperi(k, audio){
        const w = null;
        get_audio_buffer_for_waveform(audio).then( (buffer) => {
            // The window moves while fetches are in flight — following the
            // active segment queues a draw per line, and clicking around does
            // the same. Whatever `activeo` says now may describe a different
            // span than the buffer that just arrived, so measure the buffer by
            // the request that asked for it...
            wave_display_length_in_samples = convert_seconds_to_samples(audio.etime - audio.btime);
            wave_display_offset_in_samples = convert_seconds_to_samples(audio.btime);
            srcache[k] = wave_display_length_in_samples / width;
            fill_cache(k, buffer, width, w, wave_canvas_height, sample_skip, samples_per_pixel_threshold, srcache[k]);
            cache2[k] = true;
            // ...and leave the drawing to the request that matches what's on
            // screen. Drawing a stale buffer paints audio the window isn't
            // showing, and pairing a long buffer with a zoomed-in
            // samples_per_pixel is what raised "RangeError: Invalid array
            // length" from fill_waveform_display_points.
            if(k != create_audiok_from_docid(docids[i])) return;
            draw_buffer(k, srcache[k]);
        } );
    }
    function draw_buffer(k, samples_per_pixel){
        lastk = k;
        if(disable_waveform) return;
        // samples_per_pixel = srcache[k];
        draw_bufferi(k, samples_per_pixel);
        // if(spectrogram_open) spectrogram.draw_buffer(get_scache(k));
    }

    function mousedown(e){
        // activeo.channel = i;
        activate(i);
        console.log('down ' + i)
        mousedown_helper(e, this);
    }
</script>

<style>
    .activech {
        box-shadow: inset 0 0 5px green;
    }
</style>

<div id="node-00-waveform-{i}" class="w-full node-waveform {activeo.channel == i ? 'activech': ''}">
    <canvas bind:this={canvas} class="waveform-waveform {activeo.channel == i ? 'active': ''}" onmousedown={mousedown}></canvas>
    <Underlines
        {i}
        {docids}
        {width}
        {mousemove_underlines}
        {underline}
        {u}
    />
</div>
