// Aligns the transcripts several annotators produced for the same source, so
// they can be read against each other (the Sources tab's comparison view).
//
// The output reads like a transcript: one line per segment, labelled with the
// annotator who wrote it — never several annotators' text on one line. Lines
// are grouped into blocks by time: every segment from every annotator goes on
// one timeline, and segments that overlap — directly or through a chain of
// overlaps — land in the same block. A block is therefore a stretch of audio
// that everyone's versions can be read against, and annotators who split or
// merge differently still line up.

// Number(null) and Number('') are both 0, which would turn a done kit's empty
// row into a real segment at time zero — rule those out before converting.
const num = (x) => {
    if(x === null || x === undefined || x === '') return null;
    const n = Number(x);
    return Number.isFinite(n) ? n : null;
};

// Two texts "agree" if they differ only in case, surrounding space, internal
// runs of whitespace, or punctuation. Annotators disagreeing on punctuation
// alone isn't what this view is for.
function normalize_text(text){
    return String(text == null ? '' : text)
        .toLowerCase()
        .replace(/[^\p{L}\p{N}\s']/gu, '')
        .replace(/\s+/g, ' ')
        .trim();
}

// [{ uid, user, segments: [{ beg, end, text }] }] -> { columns, rows }
//
// columns: [{ uid, user }] — the annotators, by name; used for the header count.
// rows:    [{ beg, end, present: n, differs: bool,
//             lines: [{ uid, user, beg, end, text }] }]  one line per segment
function align_transcripts(kits){
    const columns = (kits || [])
        .map( (k) => ({ uid: k.uid, user: k.user || 'none' }) )
        .sort( (a, b) => String(a.user).localeCompare(String(b.user)) || String(a.uid).localeCompare(String(b.uid)) );

    // One flat list of every segment, tagged with the kit it came from.
    const all = [];
    for(const kit of kits || []){
        for(const s of kit.segments || []){
            const beg = num(s.beg);
            const end = num(s.end);
            // Done kits with no transcript come back as a single empty row.
            if(beg === null || end === null) continue;
            all.push({ uid: kit.uid, beg, end: Math.max(beg, end), text: s.text == null ? '' : String(s.text) });
        }
    }
    all.sort( (a, b) => a.beg - b.beg || a.end - b.end );

    // Merge overlapping spans into clusters. A segment joins the open cluster
    // when it starts before that cluster ends; touching endpoints don't count,
    // matching the reference-caption rule elsewhere in the editor.
    const clusters = [];
    let open = null;
    for(const s of all){
        if(open && s.beg < open.end){
            open.end = Math.max(open.end, s.end);
            open.segments.push(s);
        }
        else{
            open = { beg: s.beg, end: s.end, segments: [ s ] };
            clusters.push(open);
        }
    }

    const user_of = new Map(columns.map( (c) => [ c.uid, c.user ] ));

    // Each cluster becomes a block of transcript lines — one line per segment,
    // never several annotators' text on one line. Lines run in time order, so a
    // block reads the way a transcript does; ties break on annotator name to
    // keep the same annotator's split segments adjacent and the order stable.
    const rows = clusters.map( (c) => {
        const lines = c.segments
            .map( (s) => ({ uid: s.uid, user: user_of.get(s.uid) || 'none', beg: s.beg, end: s.end, text: s.text.trim() }) )
            .sort( (a, b) => a.beg - b.beg || String(a.user).localeCompare(String(b.user)) || a.end - b.end );

        // Disagreement is still judged per annotator, over everything each of
        // them said in the block — one annotator splitting a sentence in two
        // isn't a disagreement with someone who kept it whole.
        const joined = new Map();
        for(const line of lines){
            if(!line.text.length) continue;
            joined.set(line.uid, [ joined.get(line.uid), line.text ].filter(Boolean).join(' '));
        }
        const texts = [ ...joined.values() ].map(normalize_text).filter( (t) => t.length );
        return {
            beg: c.beg,
            end: c.end,
            lines,
            present: texts.length,
            differs: texts.length > 1 && texts.some( (t) => t !== texts[0] ),
        };
    } );

    return { columns, rows };
}

export { align_transcripts, normalize_text };
