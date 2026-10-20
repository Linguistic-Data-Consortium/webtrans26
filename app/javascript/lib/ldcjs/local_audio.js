// Audio from the annotator's own disk, for a kit type carrying local_audio.
//
// Such a kit names its audio local://<file name>. The server never sees the
// file: the work page asks for it before the kit loads, and the File goes in
// here under a blob: url, which then stands in for the presigned S3 url in
// `urls`. Playback needs nothing else — an <audio> element plays a blob: url —
// and getp_wav reads its byte ranges straight off the File, so only the bytes
// on screen are read, as with S3.
//
// Once a file is registered the page counts as holding local audio, and SAD
// and ASR stay off: both work by sending the audio to a service.

const LOCAL_PREFIX = 'local://';

const files = new Map(); // blob url → File

export function is_local_docid(k){
    return typeof k === 'string' && k.startsWith(LOCAL_PREFIX);
}

export function local_docid(name){
    return LOCAL_PREFIX + name;
}

export function local_name(docid){
    return docid.slice(LOCAL_PREFIX.length);
}

export function register_local_file(file){
    const url = URL.createObjectURL(file);
    files.set(url, file);
    return url;
}

export function local_file_for(url){
    return files.get(url);
}

export function local_audio_active(){
    return files.size > 0;
}

// Bytes b..e inclusive, the way an HTTP Range header counts them. Reads only
// that slice from disk. Fails with NotReadableError if the file was changed
// or moved after it was picked.
export function read_local_range(file, b, e){
    return file.slice(b, e + 1).arrayBuffer();
}

// Why a picked file can't stand in for the kit's audio, or null if it can.
// The name is what the kit was made with; the size, when the kit recorded
// one, catches a different recording saved under the same name.
export function local_file_mismatch(file, expected_name, expected_size){
    if(file.name !== expected_name) return `This kit's audio is ${expected_name}, not ${file.name}.`;
    if(expected_size && file.size !== expected_size){
        return `${file.name} is ${file.size} bytes, but the kit was made from a file of ${expected_size} bytes.`;
    }
    return null;
}

// for tests
export function forget_local_files(){
    for(const url of files.keys()) URL.revokeObjectURL(url);
    files.clear();
}
