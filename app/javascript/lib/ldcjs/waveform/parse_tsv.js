let round_to_3_places = (num) => Math.round( num * 1000 ) / 1000;

// The two column layouts. "Kit" style leads with a kit id and a source name;
// "file" style leads with the audio file name.
const kit_columns  = { beg: 2, end: 3, text: 4, speaker: 5, section: 6 };
const file_columns = { beg: 1, end: 2, text: 3, speaker: 4, section: 5 };

// Header cell -> field. Covers both header styles:
//   Kit   Source  Begin  End  Text  [Speaker  [Section]]
//   file  beg     end    text       [speaker  [section]]
// Speaker and section may be omitted from either; unlisted columns (Kit,
// Source, file) simply have no field and are ignored.
const header_fields = {
    beg: 'beg', begin: 'beg',
    end: 'end',
    text: 'text',
    speaker: 'speaker',
    section: 'section'
};

// A first line is a header if it starts with Kit or file *and* its cells name
// at least the times and the text. Requiring the names means a "file" style
// data row whose file name happens to start with "file" isn't eaten as one.
function parse_header(cells){
    if(!/^(kit|file)/i.test(cells[0] || '')) return null;
    const columns = {};
    cells.forEach( (cell, i) => {
        const field = header_fields[cell.trim().toLowerCase()];
        if(field && !(field in columns)) columns[field] = i;
    } );
    return ('beg' in columns && 'end' in columns && 'text' in columns) ? columns : null;
}

// No header: tell the layouts apart by where the times are. Kit style has them
// in columns 2/3, file style in 1/2. Falls back to Kit, as before.
const is_time = (cell) => cell !== undefined && cell !== '' && Number.isFinite(Number(cell));
function infer_columns(cells){
    if(is_time(cells[2]) && is_time(cells[3])) return kit_columns;
    if(is_time(cells[1]) && is_time(cells[2])) return file_columns;
    return kit_columns;
}

function parse(text){
    let o = text.split("\n");
    let data = [];
    let columns = null;
    let i = 0;
    for(let x of o){
        const y = x.replace(/\r$/, '').split("\t");
        if(columns === null){
            const header = parse_header(y);
            columns = header || infer_columns(y);
            // A recognized header line isn't data; a headerless first line is.
            if(header){ i++; continue; }
        }
        if(y.length > 1){
            // Skips a repeated header and any other row without real times
            // (an empty time cell included — Number('') would be 0).
            if(is_time(y[columns.beg]) && is_time(y[columns.end])){
                data.push( {
                    id: `segment-${i}`,
                    beg: round_to_3_places(Number(y[columns.beg])),
                    end: round_to_3_places(Number(y[columns.end])),
                    text: y[columns.text] ?? '',
                    // Optional columns: absent from the header, or absent from
                    // this row (short rows) -> empty, never undefined.
                    speaker: ('speaker' in columns && y[columns.speaker]) || '',
                    section: ('section' in columns && y[columns.section]) || ''
                } );
            }
        }
        i++;
    }
    data.sort( (x, y) => x.beg - y.beg );
    return data;
}
export default parse;
