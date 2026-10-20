const action = document.querySelector('#action_specific_js').className;

import { ldc_users } from '../users';

function find_work(){
  if(action == 'users_init_show'){
    ldc_users.init_show();
  }
  else{
    setTimeout( find_work, 500 );
  }
}
find_work();
