// javascript file for chat channel
import consumer from "./consumer";

consumer.subscriptions.create("ChatChannel", {
  connected() {
    console.log("Chat Channel connection active");
  },

  disconnected() {
    console.log("Chat Channel connection terminated");
  },

  received(data) {


    $.post('/current_user', function(result){

      var current = result.name;
      var sender = data.content.user;

      var message_format = {
        'sender': 'you',
        'status': 'status green'
      };

      var is_me = (current == sender)

      if (is_me) {
        console.log(current + ' : ' + sender)
        console.log('ME1')
        message_format.sender = 'me'
        message_format.status = 'status blue'
      }

      // append message to 'chat' div

      var chat = document.getElementById("chat");

      var li = document.createElement('li');
      var sender = document.createElement('b')
      var time_span = document.createElement('span');
      var div1 = document.createElement('div');
      var div2 = document.createElement('div');
      var h2 = document.createElement('h2');
      var span = document.createElement('h2');

      li.setAttribute('class', message_format.sender);
      li.setAttribute('id', 'message-li')
      time_span.setAttribute('id', 'timestamp');
      div1.setAttribute('class', 'entete');
      div2.setAttribute('class', 'message');
      span.setAttribute('class', message_format.status);

      // TODO: fix frontend timestamp
      var date = new Date(data.content.created_at)

      time_span.innerHTML = date.getFullYear() + '-'
                  + (date.getMonth() + 1) + '-'
                  + date.getDate() + ' '
                  + date.getUTCHours() + ':'
                  + date.getUTCMinutes() + ':'
                  + date.getUTCSeconds() + ' UTC';

      sender.innerHTML = data.content.user + ':';
      div2.innerHTML = data.content.message;

      li.appendChild(div1);
      div1.appendChild(h2);
      h2.appendChild(sender);
      div1.appendChild(span);
      if (is_me) {

        li.appendChild(time_span);
        li.appendChild(div2);
      } else {
        li.appendChild(div2);
        li.appendChild(time_span);
      }

      chat.appendChild(li);

      // TODO: make sure chatbox scrolled to bottom
      $('#chat').scrollTop($('#chat')[0].scrollHeight);

      document.getElementById("chat_message").value = "";

    });


  },
});
