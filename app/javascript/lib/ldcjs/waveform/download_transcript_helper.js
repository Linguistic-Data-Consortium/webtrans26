import { create_download_tsv } from '../download_helper';
import { graph_segments, compare_segments } from './graph_transcript';

// The transcript can be flattened two ways, and a file should only be written
// when they agree.
//
// `segs` are the live rows: made once and mutated in place ever after, by
// refold_graph as messages arrive. graph_segments() flattens the same graph
// from scratch, holding nothing between reads. So a row that should have been
// dropped, a value that never got written, a bad sort — anything the mutating
// side can get wrong and the pure one can't — shows up as a disagreement here
// instead of as a wrong line in someone's TSV.
//
// After Rebuild the check is worth more still: the rows then come from the
// server's replay of the annotation log, so the comparison covers the client's
// own write path too.
//
// Compares beg, end, text and speaker — what both sides derive. docid and
// section are assigned outside either flattening (index_segments builds the
// section index) and aren't covered. Read-only and virtual rows have no graph
// counterpart and are skipped; they still go into the file.
function transcript_disagreement(segs, graph){
    const check = compare_segments(segs, graph_segments(graph));
    if(check.matches) return null;

    const parts = [];
    for(const d of check.differing.slice(0, 5)) parts.push(`iid ${d.iid}: ${d.fields.join(', ')}`);
    if(check.differing.length > 5) parts.push(`and ${check.differing.length - 5} more rows`);
    if(check.only_live.length) parts.push(`in the transcript but not the graph: ${check.only_live.slice(0, 5).join(', ')}`);
    if(check.only_derived.length) parts.push(`in the graph but not the transcript: ${check.only_derived.slice(0, 5).join(', ')}`);
    return `the transcript and the annotation graph disagree — ${parts.join('; ')}`;
}

// Pass `graph` wherever there is one (the waveform tool) and the two
// flattenings are checked against each other first, throwing rather than
// writing a file that doesn't match the record. The dashboard has rows from
// the server's own projection and no graph in hand, so it omits it.
function create_transcript(kit_uid, include_speaker, include_section, include_headers, segs, graph = null){
  if(graph){
    const disagreement = transcript_disagreement(segs, graph);
    if(disagreement){
      console.error('[transcript]', disagreement, { segs, graph });
      throw new Error(disagreement);
    }
  }
  let rows = [];
  let columns = [
    [ 'Kit', 'kit' ],
    [ 'Audio', 'docid' ],
    [ 'Beg', 'beg' ],
    [ 'End', 'end' ],
    [ 'Text', 'text' ]
  ];
  if(include_speaker){
    columns.push([ 'Speaker', 'speaker' ]);
  }
  if(include_section){
    columns.push([ 'Section', 'section' ]);
  }
  const docids = {};
  for(let x of segs){
    if(!x.docid) x.docid = '';
    if(!docids[x.docid]) docids[x.docid] = x.docid.replace(/.+\//, '');
    let h = {
      kit: kit_uid,
      docid: docids[x.docid],
      beg: x.beg,
      end: x.end,
      text: x.text
    };
    if(include_speaker){
      h.speaker = x.speaker;
    }
    if(include_section){
      h.section = x.section ? x.section.name : '';
    }
    rows.push(h);
  }
  return create_download_tsv(rows, columns, include_headers, 'yes', null);
}
export { create_transcript, transcript_disagreement }
