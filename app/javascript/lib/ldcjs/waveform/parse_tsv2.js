let round_to_3_places = (num) => Math.round( num * 1000 ) / 1000;
function parse(text){
    let o = text.split("\n");
    let data = [];
    let i = 0;
    for(let x of o){
        // console.log(x);
        // if(i == 100) break;
        const y = x.split("\t");
        if(y[0].match(/^(utterance|Kit)/)) continue;
        if(y.length > 1){
            data.push( {
                id: `segment-${i}`,
                beg: round_to_3_places(Number(y[4])),
                end: round_to_3_places(Number(y[5])),
                text: y[6],
                speaker: y[3],
                section: ''
            } );
        }
        i++;
    }
    data.sort( (x, y) => x.beg - y.beg );
    return data;
}
export default parse;
