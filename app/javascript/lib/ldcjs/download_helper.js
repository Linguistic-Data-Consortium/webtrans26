// One TSV cell. A tab or line break inside it would shift the rest of the row
// (parse_tsv.js splits on both), so they become spaces. Nothing else changes:
// a cell starting with = + - @ is written as typed, since these files are read
// back by the tool and a leading - is ordinary transcript text. The guide says to
// import them into a spreadsheet as text rather than open them directly.
function tsv_cell(v){
    return v == null ? '' : String(v).replace(/[\t\r\n]+/g, ' ');
}

function create_download_tsv(rows, columns, include_headers, include_full, matched){
    let a = [];
    let b = [];
    if(include_headers){
        for(let y of columns){
            b.push(y[0]);
        }
        a.push(b.join('\t'))
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
            b.push(tsv_cell(x[y[1]]));
        }
        a.push(b.join('\t'));
    }
    return a.join('\n') + "\n";
}

function create_download_url(tsv){
    return URL.createObjectURL(new Blob([tsv], {type : 'text/tab-separated-values'}));
}

export { create_download_tsv, create_download_url, tsv_cell }
