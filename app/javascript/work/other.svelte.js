class NodeValue {
    value = $state();
    constructor(value){
        this.value = value;
    }
}

function nodeable(value){
    return(new NodeValue(value));
}

const xnodes = {
    lists: new Map(),
    nodes: new Map(),
    values: new Map()
};

export {
    nodeable,
    xnodes
};
