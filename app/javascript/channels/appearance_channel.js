// javascript file for chat channel
import consumer from "./consumer";

consumer.subscriptions.create("AppearanceChannel", {
  connected() {
    console.log("Appearance Channel connection active");
  },

  disconnected() {
    console.log("Appearance Channel connection terminated");
  },

  // called when data is received from channel
  received(data) {
    //console.log("appearance channel receiving data:");
    //console.log(data.content);
    //$('#' + data.content.user).remove();
  },
});
