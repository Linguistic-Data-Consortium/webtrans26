// javascript file for chat channel
import consumer from "./consumer";

var GuideChannel = {
  // This will return a handler with the update and on_data methods
  create: (gname, icallback, rcallback) => {
    let that, lastUpdate = {}, init_callback = [icallback], receive_callback = [rcallback];
    console.log("Will create channel", gname);
    consumer.subscriptions.create({channel: "GuideChannel", gname: gname}, {
      connected(data) {
        console.log("Guide Channel connection active");
        that = this;
        init_callback.map( f=>(f instanceof Function && f.call(this)) );
      },
      disconnected() {
        console.log("Guide Channel connection terminated");
      },
      received(data) {
        console.log("Received data", data);
        receive_callback.map( f=>(f instanceof Function && f.call(this, data)) );
      }
    });
    const handler = {
      update: data=>{
        if (that){
          let needUpdate = false;
          // Only send update if data differs from last time
          for (let attr in data)
            if (!(attr in lastUpdate) || lastUpdate[attr] != data[attr]) needUpdate = true;
          if (needUpdate) that.perform("update", data);
          lastUpdate = data;
        }
        return handler;
      },
      get: ()=>[handler,that&&that.perform("get")],
      on_init: f=>[handler,init_callback.push(f)][0],
      on_data: f=>[handler,receive_callback.push(f)][0]
    };
    return handler;
  }
};

export { GuideChannel };
