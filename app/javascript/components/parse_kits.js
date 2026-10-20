// The Kits tab's text dialog: one kit per line.
//
//   foo.wav                     -> { docid: 'foo.wav' }
//   foo.wav user_id=alice       -> { docid: 'foo.wav', user_id: 'alice' }
//
// The docid comes first; anything after it is `key=value`. user_id may be a
// user's id, name or email address — the server resolves it, and refuses the
// line if there's no such user rather than making a kit owned by nobody.
//
// A line that can't be read comes back carrying `error` rather than being
// dropped, so a typo is visible in the preview instead of quietly making
// fewer kits than were asked for.
export const KIT_FIELDS = [ 'user_id' ];

export function parse_kits(text){
    const kits = [];
    for(const line of String(text ?? '').split('\n')){
        const parts = line.trim().split(/\s+/).filter(Boolean);
        if(!parts.length) continue;
        const kit = { docid: parts.shift() };
        for(const part of parts){
            const at = part.indexOf('=');
            const key = at < 0 ? part : part.slice(0, at);
            if(at < 0)                          kit.error = `${part}: expected key=value`;
            else if(!KIT_FIELDS.includes(key))  kit.error = `${key}: not a field (${KIT_FIELDS.join(', ')})`;
            else if(part.slice(at + 1) === '')  kit.error = `${key}: no value`;
            else                                kit[key] = part.slice(at + 1);
        }
        kits.push(kit);
    }
    return kits;
}

// What an uploaded file looks like. A kit list is lines of text; the other
// thing this dialog accepts is a JSON array of kit objects. Told apart by the
// first character that isn't whitespace, rather than by whether the first line
// has a space in it — a line that names an owner has one.
export function looks_like_json(text){
    const head = String(text ?? '').trim();
    return head.startsWith('[') || head.startsWith('{');
}

export default parse_kits;
