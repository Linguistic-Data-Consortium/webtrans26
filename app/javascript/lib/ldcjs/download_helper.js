// One TSV cell. A tab or line break inside it would shift the rest of the row
// (parse_tsv.js splits on both), so they become spaces. Nothing else changes:
// a cell starting with = + - @ is written as typed, since these files are read
// back by the tool and a leading - is ordinary transcript text. The guide says to
// import them into a spreadsheet as text rather than open them directly.
function tsv_cell(v){
    return v == null ? '' : String(v).replace(/[\t\r\n]+/g, ' ');
}

// One CSV cell, RFC 4180. Unlike the TSV side this is lossless: a comma, quote
// or line break inside a cell is quoted rather than replaced, because nothing
// reads these files back by splitting on a separator — the table download is
// read by a spreadsheet, and parse_tsv.js is for the waveform's transcript
// upload, not for this.
//
// The leading = + - @ policy is deliberately the same as TSV's: written as
// typed. Prefixing or stripping them would silently alter a value the table
// displayed, and the guide already says to import rather than open.
function csv_cell(v){
    if(v == null) return '';
    const s = String(v);
    return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

const FORMATS = {
    tsv: { sep: '\t', cell: tsv_cell, mime: 'text/tab-separated-values', ext: 'tsv' },
    csv: { sep: ',',  cell: csv_cell, mime: 'text/csv',                  ext: 'csv' }
};

// `format` defaults to tsv, which is what every caller got before csv existed
// and what the dialog still selects.
function create_download_tsv(rows, columns, include_headers, include_full, matched, format = 'tsv'){
    const f = FORMATS[format] || FORMATS.tsv;
    let a = [];
    let b = [];
    if(include_headers){
        for(let y of columns){
            b.push(f.cell(y[0]));
        }
        a.push(b.join(f.sep))
    }
    let rs;
    if(include_full == 'yes'){
        rs = rows;
    }
    else if(include_full == 'no'){
        rs = matched;
    }
    for(let x of rs){
        b = [];
        for(let y of columns){
            b.push(f.cell(x[y[1]]));
        }
        a.push(b.join(f.sep));
    }
    // CRLF for CSV, which is what RFC 4180 specifies and what Excel expects on
    // Windows; LF for TSV, unchanged from before.
    const eol = format == 'csv' ? '\r\n' : '\n';
    return a.join(eol) + eol;
}

function create_download_url(text, format = 'tsv'){
    const f = FORMATS[format] || FORMATS.tsv;
    return URL.createObjectURL(new Blob([text], {type : f.mime}));
}

// The name the <a download> gets. A filename the user typed with an extension
// is left alone; one without gets the format's, so a CSV arrives as a .csv
// rather than as an extensionless file the OS opens with something random.
function download_filename(filename, format = 'tsv'){
    const f = FORMATS[format] || FORMATS.tsv;
    const name = (filename == null ? '' : String(filename)).trim();
    if(name == '') return 'table.' + f.ext;
    return /\.[A-Za-z0-9]+$/.test(name) ? name : name + '.' + f.ext;
}

export { create_download_tsv, create_download_url, download_filename, tsv_cell, csv_cell }
