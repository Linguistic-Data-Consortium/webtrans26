// Roll the task's kit list (the /kits/task/<id> payload used by the Kits and
// Done Kits tabs) up per source, for the task view's Sources tab.
//
// One row per unique source. done_users counts the *distinct* users with at
// least one kit for that source in the done state — a user with several done
// kits on the same source counts once.
function aggregate_sources(kits){
    const by_source = new Map();
    for(const kit of kits || []){
        const source = kit.source_uid || 'none';
        let o = by_source.get(source);
        if(!o){
            o = { source, kits: 0, done_kits: 0, user_set: new Set() };
            by_source.set(source, o);
        }
        o.kits++;
        if(kit.state == 'done'){
            o.done_kits++;
            // kits_controller#get_kit_username returns the string 'none' for an
            // unassigned kit.
            if(kit.user && kit.user != 'none') o.user_set.add(kit.user);
        }
    }
    return [ ...by_source.values() ]
        .map( (o) => ({
            source: o.source,
            kits: o.kits,
            done_kits: o.done_kits,
            done_users: o.user_set.size,
            users: [ ...o.user_set ].sort().join(', '),
        }) )
        .sort( (a, b) => String(a.source).localeCompare(String(b.source)) );
}

export { aggregate_sources };
