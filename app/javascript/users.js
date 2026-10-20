import { mount } from 'svelte';
// import App from './work/users.svelte'
import Index from './users/index.svelte'
// import { Browser } from './work/browser'
window.gdata = (sel) => $(sel).data();
export var ldc_users = function(){

    //path to the check username api
    var username_api_path = '/users/1/check_username';

    //this function sets up validation for a username field, given a selector
    function add_user_name_validation(selector, saveButton){
        //when changing focus from the name field, check for username validity
        $(selector).on('blur', function(){
            var value = $(this).val();

            //first check if length is 4..50
            if(value.length >= 4 && value.length <=50){

                //then check if username is valid (alphanumerics and start with letter)
                var username_valid = ldc_lui.valid_username_regex.test(value.toLowerCase());
                if(username_valid){

                    //then check if the username is already taken in a JSON call
                    $.get(username_api_path, {username: value}, function(data) {
                        if(data.user_exists){
                            $('#name-alert').html('Username already taken');
                            ldc_lui.toggle_button(saveButton, false);
                        }else{
                            $('#name-alert').html('');
                            ldc_lui.toggle_button(saveButton, true);
                        }
                    }, 'json');
                }else{
                   $('#name-alert').html('Username can only contain alphanumeric characters, and must start with a letter');
                   ldc_lui.toggle_button(saveButton, false);
                }
            }else{
                $('#name-alert').html('Username can only be 4-50 characters long');
                ldc_lui.toggle_button(saveButton, false);
            }
        });
    };

    //sets up the validation for password/password confirmation
    function add_password_validation(password_selector, confirmation_selector, saveButton){
        //listener on the password to ensure the length is within our range
        $(password_selector).on('blur', function(){
            var password_valid = $(this).val().length >= 6;
            $('#password-alert').html(password_valid ? '' : 'Password must have length >= 6');
            ldc_lui.toggle_button(saveButton, password_valid);
        });

        //listener on the password/password confirmation to ensure their values match
        $(password_selector + ', ' + confirmation_selector).on('blur', function(){
            var password = $(password_selector).val();
            var password_confirmation = $(confirmation_selector).val();
            var passwords_match = password === password_confirmation;

            $('#password_confirm-alert').html(passwords_match ? '' : 'Password and confirmation must match');

            //check to make sure we aren't overriding the previous listener
            if($('#password-alert').html().length === 0)
                ldc_lui.toggle_button(saveButton, passwords_match);
        });
    };

    //sets up validation for the user's email address
    function add_email_validation(selector, saveButton){
      //listener to check for email address validity when focus is lost
        $(selector).on('blur', function(){
            var email_valid = ldc_lui.valid_email_regex.test($(this).val());
            $('#email-alert').html(email_valid ? '' : 'Invalid Email Address');
            ldc_lui.toggle_button(saveButton, email_valid);
        });
    };

    return{
        //this function is called when initializing the edit view
        init_edit: function(){
            //navigates to a particular tab based on hash in url
            // var activeTab = $('[href=' + location.hash + ']');
            // activeTab && activeTab.tab('show');

            $('#user_activated').on('click', function(){
                $('#user_deactivated_for, strong:contains(Deactivated For)').toggleClass('hidden');
            });

            //used for language user tab
            $('.display').dataTable({sPaginationType: "full_numbers", bJQueryUI: true});

            //listener to check for email address validity when focus is lost
            add_email_validation('#pii_profile_email', '#save_pii');

            //when changing focus from the name field, check for username validity
            add_user_name_validation('#user_name', '#submit_name');

            //add password validation functionality
            add_password_validation('#user_password', '#user_password_confirmation', '#submit_password');
        },

        //this function is called when initializing the show view
        init_show: function(){
        //   const permissions = document.getElementById('permissions').dataset;
        //   // const browser = new Browser();
        //   const app = mount(App, {
        //       target: document.getElementById('main'),
        //       props: {
        //           admin: (permissions.admin == 'true'),
        //           portal_manager: (permissions.portal_manager == 'true'),
        //           project_manager: (permissions.project_manager == 'true')
        //           // browser: browser
        //       }
        //   });
          
          // The old `.jtro` input was replaced by an admin-only popup
          // triggered by pressing `j` (see users.svelte).
          $('#main').on( 'click', '.browser_link', function(){
              // # task_id = Number($(this).attr('class').split(' ')[1])
              // const h = {};
              // h.task_id = $(this).data().task_id;
              // h.user_id = $(this).data().user_id;
              // h.work_path = $(this).data().work_path;
              // h.bucket = $(this).data().bucket;
              app.browse();
            });
            $('body').on("ajax:success", (e, data, status, xhr) => {
                app.uploads(e);
                let id = e.detail[0].id;
                browser.id = id;
                // console.log e.detail[0]
                // $('.upload3').append ldc_nodes.array2html [ 'div', [
                //     [ 'div', 'to create a url for this file in ruby code use:' ]
                //     [ 'div', "url_for(Source.find(#{id}).file)" ]
                // ]]
            });
        },

        //this function is called when initializing the index view
        init_index: function(){
            const app = mount(Index, {
                target: document.getElementById('main'),
                props: {
                  name: 'SvelteX',
                  admin: false // $('#action_specific_admin').attr('class')
                }
              });

            //create jquery ui dialog for name resets
            $('#name_reset_dialog').dialog({ autoOpen: false,
                buttons:  {"Ok": function() {
                        $('#reset_name_form').submit();
                        $(this).dialog('close');
                    },
                    "Cancel": function() {
                        $(this).dialog('close');
                    }
                }
            });

            //listener to open the name reset dialog
            $('#main').on('click', '.toggle_name_reset', function(e){
                e.preventDefault();
                $('#name_reset_dialog').dialog('open');
                $('#user_name').val($(this).attr('user_name'));
            });

        },

        //this function is called when initializing the new view (the user signup page)
        init_new: function(){
            //listener to check for email address validity when focus is lost
            add_email_validation('#user_email');

            //when changing focus from the name field, check for username validity
            add_user_name_validation('#user_name');

            //add password/password confirmation vaildation
            add_password_validation('#user_password', '#user_password_confirmation');
            // $('form').on('keypress', e => {
            //     if (e.keyCode == 13) {
            //         return false;
            //     }
            // });
        }
    }
}();
