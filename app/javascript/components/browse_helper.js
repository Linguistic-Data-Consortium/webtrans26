import { getp } from 'https://cdn.jsdelivr.net/gh/Linguistic-Data-Consortium/ldcjs@0.0.9/src/getp.js'
function get_open_tasks(x, open_tasks, b){
  let browse_tasks = [];
  console.log('open')
  console.log(x)
  for(let y of x){
    if(y.free){
      browse_tasks.push(getp(
        b ? `/browser?blobs=audio&task_id=${y.task_id}` : `/tasks/${y.task_id}?existing=true`
      ));
      open_tasks[y.task_id] = y;
      open_tasks[y.task_id].has_kit = y.state == 'has_kit' ? y.kit_uid : false;
    }
  }
  return Promise.all(browse_tasks).then(a => {
    let b = [];
    for(let x of a){
      for(let y of x){
        if(y.source_id){
          y.type = 'file';
          y.uid = y.key;
        }
        else{
          y.type = 'kit';
        }
      }
      b = b.concat(x);
    }
    return b;
  });
}
export { get_open_tasks }
