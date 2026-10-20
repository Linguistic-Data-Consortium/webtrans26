let round_to_3_places = (num) => Math.round( num * 1000 ) / 1000;
function parse(text){
    let o = text;
    let data = [];
    let i = 0;
    for(let x of o){
        // console.log(x);
        // if(i == 100) break;
        const y = x;
        if(y[2] == 'nonspeech') continue;
        if(y.length > 1){
            data.push( {
                id: `segment-${i}`,
                beg: round_to_3_places(Number(y[0])),
                end: round_to_3_places(Number(y[1])),
                text: y[3],
                speaker: '',
                section: ''
            } );
        }
        i++;
    }
    data.sort( (x, y) => x.beg - y.beg );
    return data;
}
export default parse;
