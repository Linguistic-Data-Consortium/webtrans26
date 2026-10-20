// The groups this tool builds, and what each one is made of.
//
// An "add" message names a whole group at once — "5:SegmentListItem,6:Arc,
// 7:Text,8:Speaker" — and that string is the record. The server logs it,
// replays it and projects it without knowing what any of these names mean: a
// group with an N child is a time anchor, anything else is a span between two
// anchors with one label per remaining child. That's the only structure it
// knows, so the vocabulary is ours to choose.
//
// Adding a kind of annotation is therefore an entry here plus something to
// render it — CommentList below was this file's worked example before it was
// a feature, and became one without the server changing. The segments/sections
// export ignores what it doesn't recognise, by design: that projection is the
// readable transcript, and graph_nodes / graph_arcs / graph_labels is the
// general one.
//
// The list item is named after the list — SegmentList → SegmentListItem — and
// the children are in the order they're allocated iids.
export const groups = {
    NList: { children: [ 'N' ] },
    SegmentList: { children: [ 'Arc', 'Text', 'Speaker' ] },
    SectionList: { children: [ 'Arc', 'Name' ] },
    // A remark about a stretch of audio: one span, one label, and no part of
    // the transcript. Nothing that exports a transcript knows the name, so it
    // stays out of every one of them without being filtered anywhere.
    CommentList: { children: [ 'Arc', 'Comment' ] }
};

export default groups;
