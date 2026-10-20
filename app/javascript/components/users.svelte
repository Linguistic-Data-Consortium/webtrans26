<script>
    import { Toaster } from "$lib/components/ui/sonner";
    import * as Tabs from "$lib/components/ui/tabs";
    import TaskDocids from './task_docids.svelte';
    import CopyTaskMembers from './copy_task_members.svelte';
    import { parse_kits, looks_like_json } from './parse_kits';
    import * as Tooltip from "$lib/components/ui/tooltip";
    import * as Dialog from "$lib/components/ui/dialog";
    import { Label } from "$lib/components/ui/label";
    import { Input } from "$lib/components/ui/input";
    import { Textarea } from "$lib/components/ui/textarea";
    import { Button, buttonVariants } from "$lib/components/ui/button";
    import { btn, cbtn, dbtn } from '../lib/ldcjs/work/buttons';
    import { s3_configured } from '../lib/ldcjs/service_config';
    import { getp, getp_no_catch, postp, postp_no_catch, postpf_no_catch } from '../lib/ldcjs/getp';
    import Help from './help.svelte';
    import Browse from './browse_f.svelte';
    import Spinner from '../lib/ldcjs/work/spinner.svelte';
    import Table from '../lib/ldcjs/work/table.svelte';
    import Patch from './patch.svelte';
    import InputText from './input_text.svelte';
    import InputSelect from './input_select.svelte';
    import InputCheckbox from './input_checkbox.svelte';
    import {
        controller_actions,
        get_kits_for_task,
        get_kits_for_task_all,
        reassign_kits_for_task,
        show_kit,
        create_kits_from_kits_tab
    } from './controllers';
    import { toast } from "svelte-sonner";
    import { response, ok_reload } from './helpers';
    import { aggregate_sources } from './kit_sources';
    import { align_transcripts } from './source_comparison';
    import { create_transcript } from '../lib/ldcjs/waveform/download_transcript_helper';
    import { tick } from 'svelte';
    import { refreshToken, getSignedUrlPromise, s3url, gets3 } from '../lib/ldcjs/aws_helper';
    import { fromCognitoIdentity } from "@aws-sdk/credential-provider-cognito-identity";
    import { CognitoIdentityClient } from "@aws-sdk/client-cognito-identity";
    import { TranscribeClient } from "@aws-sdk/client-transcribe";
    import { S3Client, GetObjectCommand, HeadObjectCommand, ListObjectsV2Command, PutObjectCommand } from "@aws-sdk/client-s3";
    import { Upload } from "@aws-sdk/lib-storage";
    import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
    import { request_animation_frame_loop_init } from '../lib/ldcjs/request_animation_frame_loop';
    import {
		set_audio_element_with_url,
		play_src_with_audio_id,
		getUserMedia,
		create_blob,
		filename_from_date,
		create_node_graph,
		get_audio_context
        // play_callback,
        // callf,
        // is_playing,
        // set_playback_rate,
        // set_audio_element,
        // set_audio_id_to_channel,
        // decode_audio_data,
        // stop_playing
    } from '../lib/ldcjs/audio/main';
	import { WaveRiff } from '../lib/ldcjs/audio/wave_riff';
    import AudioPlayer from './audio_player.svelte'
    import BaseDialog from '../lib/ldcjs/waveform/dialogs/BaseDialog.svelte';
    import { mark as guide_mark } from '../lib/guide_state';
    // refreshToken({
    //     fromCognitoIdentity,
    //     CognitoIdentityClient,
    //     TranscribeClient,
    //     S3Client,
    //     GetObjectCommand,
    //     HeadObjectCommand,
    //     ListObjectsV2Command,
    //     PutObjectCommand,
    //     Upload,
    //     getSignedUrl
    // });
    
    let {
        authenticated,
        user,
        kitid,
        kituid,
        locked,
        admin,
        portal_manager,
        project_manager,
        tus,
        links,
        bucket_test,
        extra
    } = $props();
    let lead_annotator = $state(project_manager);
    let help = $state(false);
    // Hides the floating Help button in the top-right corner. The help mode and
    // all the per-tab <Help> panels are untouched — flip this back to true to
    // put the toggle back.
    const show_help_button = false;
    // let page = 1;
    // function pagef(e){ page = e.detail }
    // let pages = [
    //     [ 'Work',        'all',            "your tasks with links to start" ],
    //     [ 'Projects',    'all',            'projects, tasks, kits' ],
    //     [ 'Browse',      'all',            'browse uploaded files' ],
    //     [ 'Kit Types',   'lead_annotator', 'tasks require a kit type' ],
    //     [ 'Namespaces',  'lead_annotator', 'kit types require a namespace' ],
    //     [ 'Tools',       'lead_annotator', 'kit types require a namespace' ],
    //     [ 'Data Sets',   'lead_annotator', 'tasks can have a data set' ],
    //     [ 'Invites',     'lead_annotator', 'invite people to the site' ],
    //     [ 'Scripts',     'lead_annotator', 'write scripts' ],
    //     [ 'Features',    'admin',          'features for different objects' ],
    //     [ 'Services',    'admin',          'services' ],
    //     [ 'Workflows',   'admin',          'workflows' ],
    //     [ 'Groups',      'admin',          'groups' ],
    //     [ 'Permissions', 'all',            'explore roles and permissions' ]
    // ];
    // let goto_project = $state();
    function goto(x, y){
        if(x.task_id){
            tab = 'projects';
            if(y == 'project') project(x);
            if(y == 'task') task(x);
        }
    }
    function project(e){
        actions.project.get_all();
        all_label = (lead_annotator ? "All" : "My") + " Projects";
        if(e){
            models.project.id = e.project_id;
            models.task.id = null;
            actions.project.get_one('tasks');
        }
    }
    // let goto_task = $state();
    function task(e){
        project(e);
        models.task.id = e.task_id;
        actions.task.get_one('kits');
    }
    // document.getElementById('work1').hidden = true;
    function helpf(e){
        alert(e.detail);
    }
    
    export function browse(x){
        tab = 'browse';
        // browse_a.step1(x);
    }
    let browsex = $state();
    export function uploads(e){
        // page5();
        // browsex.get(e);
    }
    // let p = getp(window.location);
    console.log('USERS');
    // p.then( (x) => console.log(x) )
    let tab = $state('tasks');
    let tabp = $state(Promise.resolve([]));
    let pp = $state();
    let taskpp = $state();
    let taskuserpp = $state();
    let kitsp = $state();
    let kitspp = $state();
    let donekitsp = $state();
    let sourcesp = $state();
    // Account tab: the signed-in user changing their own password. The server
    // checks the current password and drops the user's other sessions.
    let account_current_password = $state('');
    let account_new_password = $state('');
    let account_confirm_password = $state('');
    let account_password_busy = $state(false);
    function change_password(){
        if(account_password_busy) return;
        account_password_busy = true;
        controller_actions.account.change_password({
            current_password: account_current_password,
            password: account_new_password,
            password_confirmation: account_confirm_password
        })
        .then( (x) => {
            if(!x){
                toast.error('bad response');
            }
            else if(x.errors){
                toast.error(x.errors.join(', '));
            }
            else if(x.error){
                toast.error(x.error);
            }
            else{
                toast.success(x.ok);
                account_current_password = '';
                account_new_password = '';
                account_confirm_password = '';
            }
        } )
        .finally( () => account_password_busy = false );
    }
    // One-time sign-in links (Invites tab). Admins and portal managers create
    // an account by name + email and hand over the returned URL; opening it
    // activates that account and signs the person in, once.
    let access_link_name = $state('');
    let access_link_email = $state('');
    let access_link_url = $state('');
    let access_link_copied = $state(false);
    let access_links_p = $state(Promise.resolve({ users: [] }));
    function load_access_links(){
        access_links_p = controller_actions.access_link.get_all();
    }
    function create_access_link(){
        access_link_url = '';
        access_link_copied = false;
        controller_actions.access_link.create({
            name: access_link_name,
            email_address: access_link_email
        })
        .then( (x) => {
            if(!x){
                toast.error('bad response');
            }
            else if(x.errors){
                toast.error(x.errors.join(', '));
            }
            else if(x.error){
                toast.error(x.error);
            }
            else{
                // The URL is shown once — only its digest is stored, so it
                // can't be looked up again. Minting a new one is the remedy.
                access_link_url = x.url;
                access_link_name = '';
                access_link_email = '';
                toast.success(x.ok);
                load_access_links();
            }
        } );
    }
    async function copy_access_link(){
        if(!access_link_url) return;
        try{
            await navigator.clipboard.writeText(access_link_url);
            access_link_copied = true;
        }
        catch(_){
            toast.error('could not copy — select the link and copy it by hand');
        }
    }
    // Portal-manager-only Activations tab: promise for the current list of
    // users still awaiting activation. Reloaded on tab switch and after
    // each activation.
    let activations_p = $state(Promise.resolve({ users: [] }));
    let style = $state();
    let style_timeout;
    function set_style(e){
        style = `position: absolute; left: ${e.pageX-20}px; top: ${e.pageY+20}px; z-index: 10`;
        if(style_timeout) clearTimeout(style_timeout);
        style_timeout = setTimeout( () => style = null, 2000);
    };
    let member_timeout;
    let memberp = $state(Promise.resolve([]));
    let member_name = $state();
    // Candidates for the Add Member dialog. Keyed off the model whose dialog is
    // open — NOT off which tabs happen to be on 'members'. Tab state persists
    // per model, so a stale models.task.tab == 'members' used to make the
    // project dialog list *task* candidates, whose objects carry user_id
    // instead of id; adding one then posted no user_id at all.
    function memberf(model, name){
        if(model == 'task')    return controller_actions.task_user.not_in(models.task.id, name);
        if(model == 'project') return controller_actions.project_user.not_in(models.project.id, name);
        if(model == 'group')   return controller_actions.group_user.not_in(models.group.id, name);
        return Promise.resolve([]);
    }
    function check_member_name(model, name){
        if(member_timeout) clearTimeout(member_timeout);
        if(!name || name.length < 3){
            memberp = Promise.resolve([]);
            return;
        }
        member_timeout = setTimeout(() => memberp = memberf(model, name), 500);
    }
    function clear_member_name(){
        if(member_timeout) clearTimeout(member_timeout);
        member_name = null;
        memberp = Promise.resolve([]);
    }
    function create_name(){
        return { name: document.getElementById('dialog_create_name').value };
    }
    function create_category(){
        return { category: document.getElementById('dialog_create_category').value };
    }
    function member_create(model, x){
        // Candidate lists name the user differently: /users_not_in_task returns
        // user_id, /users_not_in_project and the group list return id.
        const user_id = x.user_id ?? x.id;
        if(user_id == null){
            toast.error('could not add member: the candidate list carries no user id');
            return;
        }
        const o = { user_id };
        o[model + '_id'] = models[model].id;
        controller_actions[model + '_user'].create(o)
        .then(x => ok_reload(x, () => actions[model].get_one('members')))
        .then(() => {
            clear_member_name();
            if (model === 'task') guide_mark('task_member_added'); // getting-started step 8 done
        });
    }
    function member_delete(model){
        controller_actions[model + '_user'].delete(models[model].user_id)
        .then(x => ok_reload(x, () => actions[model].get_one('members')))
        .then(models[model].user_id = null);
    }
    function selectedfmember(model, x){
        models[model].user_id = x;
        if(model == 'task') taskuserpp = x && controller_actions.task_user.get_one(x);
    }
    let all_label = $state();
    // Reacts to tab changes anywhere in the user dashboard (top-level,
    // project-level, task-level) and emits getting-started milestones. Each
    // milestone marks the matching step as DONE — the guide advances to
    // the next step. We use "moved to the next tab" as a proxy for "this
    // tab's work is complete", because we don't yet hook the actual
    // create/save events (project create, task create, kit create, etc).
    //
    // Guards prevent initial-mount false-fires: the top-level tab uses a
    // previous-value tracker (it defaults to 'tasks'), the project/task
    // effects only fire once an actual project/task is open (id != null).
    let prev_top_tab;
    $effect(() => {
        const t = tab;
        if (prev_top_tab !== undefined && t !== prev_top_tab) {
            if (t === 'projects') guide_mark('projects_tab_open'); // step 0 done
            if (t === 'tasks')    guide_mark('work_started');      // step 11 done (back to Work → Ready to go / Action column)
        }
        prev_top_tab = t;
    });
    let prev_project_id;
    $effect(() => {
        const id = models?.project?.id;
        if (prev_project_id == null && id != null) {
            guide_mark('project_open'); // step 2 done — project row clicked
        }
        prev_project_id = id;
    });
    $effect(() => {
        if (models?.project?.id && models.project.tab === 'tasks') {
            guide_mark('project_tasks_tab_open'); // step 3 done
        }
    });
    let prev_task_id;
    $effect(() => {
        const id = models?.task?.id;
        if (prev_task_id == null && id != null) {
            guide_mark('task_open'); // step 5 done — task row clicked
        }
        prev_task_id = id;
    });
    $effect(() => {
        if (!models?.task?.id) return;
        const t = models.task.tab;
        // Every tab click advances PAST the step that talks about that tab.
        if (t === 'members') guide_mark('task_members_tab_open'); // step 7 done → step 8
        if (t === 'kits')    guide_mark('kits_tab_open');         // step 9 done → step 10
    });

    function tabs(tab){
        pp = null;
        taskpp = null;
        switch(tab){
            case 'projects':
                project();
                break;
            case 'kit_types':
                actions.kit_type.get_all();
                all_label = "All Kit Types";
                break;
            case 'features':
                actions.feature.get_all();
                all_label = "All Features";
                break;
            case 'workflows':
                actions.workflow.get_all();
                all_label = "All Workflows";
                break;
            case 'groups':
                actions.group.get_all();
                all_label = "All Groups";
                break;
            case 'invites':
                actions.invite.get_all();
                all_label = "All Invites";
                if(portal_manager) load_access_links();
                break;
            case 'activations':
                activations_p = controller_actions.user.get_unactivated();
                break;
        }
    }


    const models = $state({
        kit_type: {
            label: 'Kit Type',
            desc: 'A Kit Type holds parameters for kit behavior.',
            id: null,
            index: null
        },
        kit: {
            label: 'Kit',
            desc: 'A Kit is a unit of work.',
            id: null,
            index: null
        },
        donekit: {
            label: 'Done Kit',
            desc: 'A Kit is a unit of work.',
            id: null,
            index: null
        },
        project: {
            label: 'Project',
            desc: 'A Project is a set of Tasks and a set of Users.',
            id: null,
            index: null,
            tab: 'info',
            user_id: null,
            user_index: null
        },
        task: {
            label: 'Task',
            desc: 'A Task is a set of Kits and a set of Users.',
            id: null,
            index: null,
            tab: 'info',
            user_id: null,
            user_index: null
        },
        feature: {
            label: 'Feature',
            desc: 'A Feature is an attribute of an object.',
            id: null,
            index: null
        },
        workflow: {
            label: 'Workflow',
            desc: 'A Workflow controls kit assignment.',
            id: null,
            index: null
        },
        group: {
            label: 'Group',
            desc: 'A Group is a set of Users.',
            id: null,
            index: null,
            tab: 'info',
            user_id: null,
            user_index: null
        },
        invite: {
            label: 'Invite',
            desc: 'An invitation for a new user.',
            id: null,
            index: null
        }
    });
    const actions = $derived.by(() => {
        const model_actions = {};
        for(let x in controller_actions){
            model_actions[x] = {};
            model_actions[x].get_all = () => {
                tabp = controller_actions[x].get_all();
                models[x].id = null;
            };
            model_actions[x].get_one = () => pp = controller_actions[x].get_one(models[x].id);
            model_actions[x].create = () => controller_actions[x].create(create_name()).then(y => response(y, model_actions[x].get_all));
            model_actions[x].delete = () => controller_actions[x].delete(models[x].id).then(y => response(y, model_actions[x].get_all, () => models[x].id = null));
            model_actions[x].patch = (y) => controller_actions[x].patch(models[x].id, y);
        }
        // overrides
        model_actions.project.get_one = (x) => {
            pp = controller_actions.project.get_one(models.project.id);
            taskpp = null;
            models.project.user_id = null;
            models.project.tab = x || 'info';
            // memberf = (name) => controller_actions.project_user.not_in(models.project.id, name);
        };
        // Fire the getting-started milestone after a project is created so
        // the guide moves past the "Create a project" step.
        model_actions.project.create = () =>
            controller_actions.project.create(create_name())
                .then((y) => response(y, model_actions.project.get_all))
                .then(() => guide_mark('project_created'));
        model_actions.project_user.patch = (x) => controller_actions.project_user.patch(models.project.user_id, x);
        model_actions.task.get_one = (x) => {
            console.log(x)
            taskpp = controller_actions.task.get_one(models.project.id, models.task.id)
            .then(x => {
                x.statuses = [ 'active', 'inactive' ];
                x.workflow = null;
                x.workflows_menu = [];
                for(let y of x.workflows){
                    if(
                        (
                            y.name != 'Bucket' &&
                            y.name != 'BucketUser' &&
                            y.name != 'SecondPass'
                        )
                        ||
                        y.id == x.workflow_id
                    ){
                        x.workflows_menu.push(y);
                    }
                    if(y.id == x.workflow_id){
                        x.workflow = y;
                        // break;
                    }
                }
                for(let y of x.kit_types){
                    if(y.id == x.kit_type_id){
                        x.kit_type = y;
                        break;
                    }
                }
                x.data_sets = [ { id: null, name: 'none'} ].concat(x.data_sets);
                for(let y of x.data_sets){
                    if(y.id == x.data_set_id){
                        x.data_set = y;
                        break;
                    }
                }
                x.menu_tasks = [ { id: 0, name: 'none'} ].concat(x.tasks);
                if(x.meta['1p_task_id']){
                    for(let y of x.tasks){
                        if(y.id == Number(x.meta['1p_task_id'])){
                            x.menu_task = y;
                            break;
                        }
                    }
                }
                else{
                    x.menu_task = x.menu_tasks[0];
                }
                x.constraintb = {};
                for(let y of x.features){
                    if(y.name == y.value) x.constraintb[y.name] = x.meta[y.name] == y.name;
                    else                  x.constraintb[y.name] = x.meta[y.name];
                }
                console.log('taskusers', x)
                // models.task.task_admin_bool = x.task_admin_bool;
                // models.task.members = x.members;
                return x;
            });
            models.task.user_id = null;
            models.task.tab = x || 'info';
            taskuserpp = null;
            kitsp = null;
            donekitsp = null;
            // memberf = (name) => controller_actions.task_user.not_in(models.task.id, name);
        };
        model_actions.task.create = () => {
            controller_actions.task.create(models.project.id, create_name())
            .then(y => response(y, () => model_actions.project.get_one('tasks')))
            .then(() => guide_mark('task_created')); // getting-started step 4 done
        };
        // Fire workflow_changed the moment the user actually changes the
        // workflow (instead of waiting for them to navigate to the next
        // tab). The Patch component passes a payload like {workflow_id: N}.
        model_actions.task.patch = (y) => {
            const promise = controller_actions.task.patch(models.task.id, y);
            if (y && Object.prototype.hasOwnProperty.call(y, 'workflow_id')) {
                guide_mark('workflow_changed'); // getting-started step 6 done
            }
            return promise;
        };
        model_actions.task.delete = () => {
            controller_actions.task.delete(models.task.id)
            .then(y => response(y, () => model_actions.project.get_one('tasks'), () => models.task.id = null));
        };
        model_actions.task_user.patch = (x) => controller_actions.task_user.patch(models.task.user_id, x);
        model_actions.kit_type.get_one = () => {
            pp = controller_actions.kit_type.get_one(models.kit_type.id)
            .then(x => {
                for(let y of x.node_classes){
                    if(y.id == x.node_class_id){
                        x.node_class = y;
                        break;
                    }
                }
                x.constraintb = {};
                for(let y of x.features){
                    if(y.name == y.value) x.constraintb[y.name] = x.constraints[y.name] == y.name;
                    else                  x.constraintb[y.name] = x.constraints[y.name];
                }
                return x;
            });
        };
        model_actions.feature.create = () => {
            const { category } = create_category();
            const { name } = create_name();
            controller_actions.feature.create({ category, name })
            .then(x => response(x, model_actions.feature.get_all));
        };
        // model_actions.group.get_one = () => {
        //     pp = controller_actions.group.get_one(models.group.id);
        //     .then( x => {
        //         x.group_admin_bool
        //     });
        //     // memberf = (name) => controller_actions.group_user.not_in(models.group.id, name);
        // };
        return model_actions;
    });

    const task_user_states = [ null, 'needs_kit', 'has_kit', 'hold', 'paused' ];

    // let kitsp = $derived( () => models.task.tab == 'kits' ? getp(`/kits/task/${task_id}`));
    $effect( () =>  {
        if(models.task.tab == 'kits'){
            // taskpp.then( (x) => get_kitsp(x.id) );
            // taskpp.then( console.log('there'))
            get_kitsp();
        }
    } );
    $effect( () =>  {
        if(models.task.tab == 'done'){
            get_donekitsp();
        }
    } );
    $effect( () =>  {
        if(models.task.tab == 'sources'){
            get_sourcesp();
        }
    } );
    // export let reload;
    // let name;
    // setInterval( () => {
    //     console.log(models.task.task_admin_bool);
    // }, 1000)
    function get_kitsp(task_id){
        // setTimeout( () => console.log(task_id), 1000);
        // return;
        kitspp = null;
        // console.log(models.task.members)
        kitsp = get_kits_for_task(models.task.id).then( (x) => {
            return x;
        } );
        // donekitsp = kitsp.then(x => x.filter(x => x.state == 'done'));
    }
    function get_donekitsp(task_id){
        kitspp = null;
        // console.log(models.task.members)
        donekitsp = get_kits_for_task(models.task.id).then( (x) => {
            return x;
        } ).then(x => x.filter(x => x.state == 'done'));
    }
    // Sources tab: same kit list as the Kits / Done Kits tabs, rolled up per
    // source instead of per kit (see components/kit_sources.js).
    function get_sourcesp(task_id){
        kitspp = null;
        comparison_source = null;
        sourcesp = get_kits_for_task(models.task.id).then(aggregate_sources);
    }
    // Clicking a source row swaps the table for a read-only comparison of every
    // done annotation of that source, aligned by time. No waveform, no editing.
    let comparison_source = $state(null);
    let comparisonp = $state();
    function open_comparison(source){
        comparison_source = source;
        const task_id = models.task.id;
        comparisonp = Promise.all([
            get_kits_for_task(task_id),      // uid -> annotator, state, source
            get_kits_for_task_all(task_id)   // uid -> segments (done kits only)
        ]).then( ([ meta, transcripts ]) => {
            const wanted = new Map();
            for(const k of meta || []){
                if(k.state == 'done' && (k.source_uid || 'none') == source) wanted.set(k.uid, k.user);
            }
            const kits = (transcripts || [])
                .filter( (t) => wanted.has(t.kit_uid) )
                .map( (t) => ({ uid: t.kit_uid, user: wanted.get(t.kit_uid), segments: t.segments }) );
            // A done kit with no segments at all never reaches /kits/all, so add
            // the annotator back as an empty column rather than dropping them.
            for(const [ uid, user ] of wanted){
                if(!kits.some( (k) => k.uid == uid )) kits.push({ uid, user, segments: [] });
            }
            return align_transcripts(kits);
        } );
    }
    function close_comparison(){
        comparison_source = null;
        comparisonp = null;
    }
    
    function data_error_join(data){
        if(typeof data.error === String) return data.error;
        else                             return data.error.join(' ');
    }

    function responsex(data){
        let flash_value;
        if(!data){
            toast.error('bad response');
        }
        else if(data.error){
            flash_value = data_error_join(data);
            toast.error(flash_value);
        }
        else{
            if(data.deleted){
                flash_value = data.deleted;
            }
            else if(data.uids){
                flash_value = `${data.uids.success.length} modified, ${data.uids.error.length} failed`;
                get_kitsp();
            }
            else{
                flash_value = "created " + data.task.name;
            }
            toast.success(flash_value);
            // setTimeout( () => reload() , 1000 );
        }
    }
    function open_kit(){
        kitspp = show_kit(models.kit.id);
    }
    function back(){
        kitspp = null;
    }
    let kits_for_task_table = $state();
    let donekits_for_task_table = $state();
    function reassign(project_id, task_id){
        let uids = [];
        for(let x of kits_for_task_table.get_matched()){
            uids.push(x.uid);
        }
        let o = { uids: uids.join(',') };
        if(!kits_for_task_table.match_attempted()){
            toast.error("you haven't matched any kits");
        }
        else if(new_user || new_state){
            if(new_user){
                o.new_user = new_user.name;
            }
            if(new_state){
                o.new_state = new_state;
            }
            reassign_kits_for_task(project_id, task_id, o).then(responsex);
        }
        else{
            toast.error('neither user nor state specified');
        }
    }
    let new_user = $state();
    let new_state = $state();
    let states = [ 'unassigned', 'assigned', 'done', 'broken', 'excluded', 'priority' ];
    let emptyv = { name: '' };






    const parse_jsonn = (x) => JSON.parse(x);
    let typed = $state();
    let json_typed = $state();
    let files = $state();
    let text_upload = $state();
    let json_upload = $state();
    const parsed_errors = $derived((json_typed || []).filter( (x) => x.error ));
    const parsed_errors_upload = $derived((json_upload || []).filter( (x) => x.error ));
    // Which of the two shapes the uploaded file is. It used to be "docids" only
    // when the first line had no spaces in it, which a line naming an owner
    // does — such a file fell through to "unknown format" with no way to parse
    // it. Anything that isn't JSON is a kit list now.
    let tdf = $state(false);
    let jsonn = $state(false);
    function upload(){
        const r = new FileReader();
        r.onload = function(e){
            text_upload = e.target.result;
            jsonn = looks_like_json(text_upload);
            tdf = !jsonn && String(text_upload).trim().length > 0;
        }
        r.readAsText(files[0]);
    }
        // that.w.add_timestamps2 data
        // $('#browse_b').html 'working...'
        // ldc_annotate.add_callback ->
        //     $('.Root').show()
        //     $('#browse_b').hide()
    // What the server made, and what it wouldn't. Shown under the Kits table,
    // since the dialog has closed by the time the answer comes back.
    let kit_creation = $state(null);
    function add(task_id, json){
        const j = { task_id: task_id, kits: json };
        kit_creation = null;
        create_kits_from_kits_tab(j).then( (data) => {
            console.log(data);
            kit_creation = data;
            get_kitsp();
            guide_mark('kit_created'); // getting-started step 9 done
        });
    }


    let textt = $state();
    let json_download = $state(false);
    let include_headers = $state(false);
    let filename = $state();
    let link = $state();
    let url = $state();
    let downloadp = $state(Promise.resolve({}));
    function create_download(task_id){
        downloadp = get_kits_for_task_all(task_id).then( (data) => {
            const t = [];
            const zip = new JSZip();
            const folder = zip.folder('transcripts');
            let text;
            for(let kit of data){
                for(let s of kit.segments){
                    s.section = { name: s.section };
                }
                let text = create_transcript(kit.kit_uid, include_speaker, include_section, include_headers, kit.segments);
                if(!textt) textt = text;
                folder.file(`${kit.kit_uid}.tsv`, text);
            }
            zip.generateAsync({type: 'blob'}).then( (blob) => {
                url = URL.createObjectURL(blob);
                tick().then( () => link.href = url );
            })
        });
    }
    let include_speaker = $state(false);
    let include_section = $state(false);

    const user_none = { user_id: 0, name: 'none'};
    function menu_userf(user_id, task_users){
        if(user_id){
            for(let x of task_users){
                if(x.user_id == user_id) return x;
            }
            // error if not found?
        }
        else{
            return user_none;
        }
    }


    // const h = {
    //     name: 'create_invitation_modal',
    //     // delegate: ns,
    //     // b: 'DELETE',
    //     // f: "delete_section_from_modal",
    //     // ff: delete_selected,
    //     title: 'Send Invitation',
    //     h: '',
    //     buttons: [
    //         [ 'Send', cbtn, create_invite ]
    //     ]
    // };
    // let email = $state();
    // let role = $state();
    // let project_id = $state();
    // let task_id = $state();
    // function create_invite(){
    //     postp(
    //         "/invites",
    //         {
    //             email: email,
    //             role: role,
    //             task_id: task_id,
    //             project_id: project_id
    //         }
    //       ).then( (data) => {
    //             let flash_value;
    //             if(!data){
    //                 toast.error('bad response');
    //             }
    //             if(data.errors){
    //                 flash_value = data.errors.join(' ');
    //                 toast.error(flash_value);
    //             }
    //             else{
    //                 flash_value = "sent to " + data.invite.email;
    //                 toast.success(flash_value);
    //                 get();
    //             }
    //         }
    //       );
    // }

    // ─── Admin jump-to-readonly popup ───────────────────────────────────────
    // Triggered by pressing `j` on the page (admin only). Replaces the old
    // always-visible "jump to readonly" input under the help button.
    let jump_dialog = $state();
    let jump_input  = $state();
    let jump_value  = $state('');

    function jump_submit() {
        const value = jump_value.trim();
        if (!value) return;
        window.location = `/workflows/3/read_only/${value}`;
    }
    function jump_dialog_keydown(e) {
        if (e.key === 'Enter') {
            e.preventDefault();
            jump_submit();
        } else if (e.key === 'Escape') {
            e.preventDefault();
            jump_dialog?.close();
        }
    }
    function jump_window_keydown(e) {
        if (!admin) return;
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        if (document.querySelector('dialog[open]')) return;
        const t = document.activeElement;
        if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable)) return;
        if (e.key !== 'j') return;
        e.preventDefault();
        jump_value = '';
        jump_dialog?.showModal();
        // Focus the input after the dialog finishes opening.
        setTimeout(() => jump_input?.focus(), 0);
    }
    $effect(() => {
        window.addEventListener('keydown', jump_window_keydown);
        return () => window.removeEventListener('keydown', jump_window_keydown);
    });

</script>

<style>
</style>

<Toaster richColors expand={true} />

<Help {help}>
    {#snippet content()}
    <div>
        <p>Help Mode On</p>
        <p>more info can be found on each tab</p>
    </div>
    {/snippet}
</Help>

<!-- Floating Help button pinned to the top-right so it doesn't push the
     tabs down. Currently hidden — see show_help_button. -->
{#if show_help_button}
    <button class="{btn} bg-blue-200 fixed top-2 right-4 z-30" onclick={() => help = !help}>Help</button>
{/if}

{#if admin}
    <BaseDialog bind:dialogRef={jump_dialog} size="sm:max-w-md" title="Jump to readonly" showClose={false} onKeydown={jump_dialog_keydown}>
        {#snippet children({ dialog })}
            <div class="p-5 text-sm" onkeydown={jump_dialog_keydown} role="presentation">
                <p class="text-gray-700 mb-3">Enter a kit / source ID to open it in readonly mode.</p>
                <input
                    bind:this={jump_input}
                    bind:value={jump_value}
                    class="block w-full rounded-md border border-gray-300 px-3 py-2 text-sm shadow-sm focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 outline-none"
                    placeholder="kit / source ID"
                />
                <div class="flex justify-end gap-2 mt-4">
                    <button
                        type="button"
                        onclick={() => jump_dialog?.close()}
                        class="inline-flex items-center gap-1 px-3 py-1.5 rounded border border-gray-300 bg-white text-gray-700 text-sm font-medium hover:bg-gray-50"
                    >
                        Cancel
                        <kbd class="ml-1 px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded font-mono text-[10px] text-gray-500">esc</kbd>
                    </button>
                    <button
                        type="button"
                        onclick={jump_submit}
                        class="inline-flex items-center gap-1 px-3 py-1.5 rounded bg-indigo-600 text-white text-sm font-semibold hover:bg-indigo-700"
                    >
                        Jump
                        <kbd class="ml-1 px-1.5 py-0.5 bg-indigo-700/40 border border-indigo-300/40 rounded font-mono text-[10px] text-white/90">↵</kbd>
                    </button>
                </div>
            </div>
        {/snippet}
    </BaseDialog>
{/if}

{#snippet dialog_create(model)}
    <Dialog.Root>
        <Dialog.Trigger class={buttonVariants({ variant: "secondary" })} data-guide-target="create_{model}">Create {models[model].label}</Dialog.Trigger>
        <Dialog.Content>
            <Dialog.Header>
                <Dialog.Title>Create {models[model].label}</Dialog.Title>
                <Dialog.Description>
                    {models[model].desc}
                </Dialog.Description>
            </Dialog.Header>
            {#if model == 'feature'}
                <Label for="dialog_create_category">Category</Label>
                <Input type="text" id="dialog_create_category" placeholder="Category" />
            {/if}
            <Label for="dialog_create_name">Name</Label>
            <Input type="text" id="dialog_create_name" placeholder="Name" />
            <Dialog.Footer>
                <Button variant="secondary" onclick={actions[model].create}>Create</Button>
            </Dialog.Footer>
        </Dialog.Content>
    </Dialog.Root>
{/snippet}

{#snippet dialog_delete(model)}
    <Dialog.Root>
        <Dialog.Trigger class={buttonVariants({ variant: "secondary" })}>Delete {models[model].label}</Dialog.Trigger>
        <Dialog.Content>
            <Dialog.Header>
                <Dialog.Title>Delete {models[model].label}</Dialog.Title>
                <Dialog.Description>
                    This will delete the {models[model].label} {models[model].index[models[model].id].name}, are you sure you want to do this?
                </Dialog.Description>
            </Dialog.Header>
            <Dialog.Footer>
                <Button variant="destructive" onclick={actions[model].delete}>Delete</Button>
            </Dialog.Footer>
        </Dialog.Content>
    </Dialog.Root>
{/snippet}

{#snippet access_links()}
    <div class="mb-4">
        <div class="flex justify-around">
            <div>Access links</div>
        </div>
        <p class="mx-auto max-w-3xl py-2 text-sm text-gray-600">
            Creates the account and gives you a link to pass on. Whoever opens it is
            signed in as that user and the link is then spent — no password is ever
            needed. Someone who signs out needs a fresh link, or a password reset.
        </p>
        <form class="flex flex-wrap items-end justify-around gap-2" onsubmit={(e) => e.preventDefault()}>
            <div>
                <Label for="access_link_name">Name</Label>
                <Input type="text" id="access_link_name" placeholder="Name" bind:value={access_link_name} />
            </div>
            <div>
                <Label for="access_link_email">Email</Label>
                <Input type="text" id="access_link_email" placeholder="Email" bind:value={access_link_email} />
            </div>
            <Button variant="secondary" onclick={create_access_link}>Create Link</Button>
        </form>
        {#if access_link_url}
            <div class="mx-auto mt-4 max-w-3xl rounded-md border border-gray-300 bg-gray-50 p-3">
                <div class="text-sm text-gray-600">Copy this now — it isn't shown again.</div>
                <div class="mt-2 flex items-center gap-2">
                    <input class="flex-1 rounded-md border-2 border-gray-300 p-2 font-mono text-sm" readonly value={access_link_url} />
                    <button type="button" class="{btn}" onclick={copy_access_link}>{access_link_copied ? 'Copied' : 'Copy'}</button>
                </div>
            </div>
        {/if}
        {#await access_links_p}
            <div class="mx-auto w-8 h-8"><Spinner /></div>
        {:then v}
            {#if v && v.users && v.users.length}
                <div class="mt-4">
                    <div class="flex justify-around">Links not used yet</div>
                    <Table
                        columns={[
                            [ 'Name', 'name', 'col-1' ],
                            [ 'Email', 'email', 'col-2' ],
                            [ 'Created', 'created_at', 'col-1' ],
                            [ 'By', 'created_by', 'col-1' ],
                        ]}
                        rows={v.users}
                        height="200"
                        selectedf={(x, y) => set_style(y)}
                    />
                </div>
            {/if}
        {/await}
    </div>
{/snippet}

{#snippet source_comparison()}
    <div class="flex items-start justify-between gap-4 mb-2">
        <div class="min-w-0">
            <div class="font-medium break-all">{comparison_source}</div>
            <div class="text-sm text-gray-600">
                Done annotations of this source as a transcript — one line per segment,
                grouped by time so versions of the same audio read together. Read-only.
            </div>
        </div>
        <button class="{btn} shrink-0" onclick={close_comparison}>Return to source list</button>
    </div>
    {#await comparisonp}
        <div class="mx-auto w-8 h-8"><Spinner /></div>
    {:then v}
        {#if !v || !v.columns.length}
            <hr>
            <div class="p-4 text-center text-gray-600">No done kits for this source yet.</div>
        {:else}
            <div class="flex justify-around mb-2 text-sm">
                <div>{v.columns.length} annotator{v.columns.length == 1 ? '' : 's'}</div>
                <div>{v.rows.length} block{v.rows.length == 1 ? '' : 's'}</div>
                <div>
                    <span class="px-1 bg-yellow-100">{v.rows.filter( (r) => r.differs ).length}</span>
                    where they disagree
                </div>
            </div>
            <hr>
            <div class="clear-both overflow-auto max-h-[32rem]">
                <table class="relative w-full">
                    <thead>
                        <tr>
                            <th class="sticky top-0 bg-blue-100 p-2 text-left w-32">Time</th>
                            <th class="sticky top-0 bg-blue-100 p-2 text-left w-40">Annotator</th>
                            <th class="sticky top-0 bg-blue-100 p-2 text-left">Text</th>
                        </tr>
                    </thead>
                    <tbody>
                        <!-- One line per segment. Blocks (segments that overlap in
                             time) are separated by a rule so versions of the same
                             stretch of audio read together. -->
                        {#each v.rows as r}
                            {#each r.lines as line, j}
                                <tr class="{r.differs ? 'bg-yellow-100' : ''} {j == 0 ? 'border-t-2 border-gray-300' : ''}">
                                    <td class="p-2 align-top whitespace-nowrap font-mono text-xs">
                                        {line.beg.toFixed(2)}–{line.end.toFixed(2)}
                                    </td>
                                    <td class="p-2 align-top whitespace-nowrap text-sm text-gray-700">{line.user}</td>
                                    <td class="p-2 align-top">{line.text}</td>
                                </tr>
                            {/each}
                        {/each}
                    </tbody>
                </table>
            </div>
        {/if}
    {/await}
{/snippet}

{#snippet dialog_create_member(model)}
    <Dialog.Root>
        <Dialog.Trigger class={buttonVariants({ variant: "secondary" })} data-guide-target="add_{model}_member">Add Member</Dialog.Trigger>
        <Dialog.Content style="width: 800px; max-width: 800px;">
            <Dialog.Header>
                <Dialog.Title>Add Member</Dialog.Title>
                <Dialog.Description>
                    Add User to {models[model].label}
                </Dialog.Description>
            </Dialog.Header>
            <div class="grid grid-cols-2">
                <div>
                    <Label for="dialog_create_member_name">Name</Label>
                    <!-- Search this dialog's model explicitly, so the candidate
                         list can't come from another model's members tab. -->
                    <Input
                        type="text"
                        id="dialog_create_member_name"
                        placeholder="Name"
                        bind:value={member_name}
                        oninput={(e) => check_member_name(model, e.currentTarget.value)}
                    />
                </div>
                <div>
                    {#await memberp}
                        names
                    {:then v}
                        {#each v as x}
                            {#if member_name && x.name.includes(member_name)}
                                <button class="{buttonVariants({ variant: "secondary" })} m-2" onclick={() => member_create(model, x)}>{x.name}</button>
                            {/if}
                        {/each}
                    {/await}
                </div>
            </div>
            <!-- <Dialog.Footer>
                <Button variant="secondary" onclick={f}>Create</Button>
            </Dialog.Footer> -->
        </Dialog.Content>
    </Dialog.Root>
{/snippet}

{#snippet dialog_copy_members(v)}
    <!-- The members table refreshes when the dialog closes, not when the copy
         finishes: reloading it re-renders this subtree, which takes the dialog
         — and the summary of who was added — with it. -->
    <Dialog.Root onOpenChange={(open) => { if(!open) actions.task.get_one('members'); }}>
        <Dialog.Trigger class={buttonVariants({ variant: "secondary" })}>Add Members from Task</Dialog.Trigger>
        <Dialog.Content class="max-w-2xl w-[92vw]">
            <Dialog.Header>
                <Dialog.Title>Add Members from Task</Dialog.Title>
                <Dialog.Description>
                    Every member of the task you choose is added to {v.name}. Anyone already a
                    member is left as they are, and nobody becomes an admin here.
                </Dialog.Description>
            </Dialog.Header>
            <CopyTaskMembers task_id={v.id} />
        </Dialog.Content>
    </Dialog.Root>
{/snippet}

{#snippet dialog_delete_member(model)}
    <Dialog.Root>
        <Dialog.Trigger class={buttonVariants({ variant: "secondary" })}>Remove Member</Dialog.Trigger>
        <Dialog.Content>
            <Dialog.Header>
                <Dialog.Title>Remove Member</Dialog.Title>
                <Dialog.Description>
                    This will remove {models[model].user_index[models[model].user_id].name}, are you sure you want to do this?
                </Dialog.Description>
            </Dialog.Header>
            <Dialog.Footer>
                <Button variant="destructive" onclick={() => member_delete(model)}>Delete</Button>
            </Dialog.Footer>
        </Dialog.Content>
    </Dialog.Root>
{/snippet}

{#snippet boiler1(model)}
    {@render boiler2(model)}
    {#await pp}
        <div class="mx-auto w-8 h-8"><Spinner /></div>
    {:then v}
        {@render boiler4(v)}
        {@render boiler5(model, v)}
    {/await}
{/snippet}

{#snippet boiler2(model)}
    <div class="float-right">
        <button class="{btn}" onclick={() => (pp = null) || actions[model].get_all()}>Return to {models[model].label} list</button>
    </div>
{/snippet}

{#snippet boiler4(v)}
    <div class="float-right p-2">{v && v.name}</div>
{/snippet}

{#snippet boiler5(model, v)}
    <div class="w-96 mx-auto">
        <div>ID: {v.id}</div>
        {#if model == 'feature'}
            <Patch type="input" urlf={actions[model].patch} label="Category" key="category" value={v.category} />
        {/if}
        {#if model == 'project' && !v.project_owner_bool}
            <div>Name: {name}</div>
        {:else}
            <Patch type="input" urlf={actions[model].patch} label="Name" key="name" value={v.name} />
        {/if}
        {#if model == 'task'}
            {models.task.tab}
            <Patch type="select" urlf={actions[model].patch} label="Status" key="status" value={v.status} values={v.statuses} />
            <div data-guide-target="task_workflow_setting">
                <Patch type="select" urlf={actions[model].patch} label="Workflow" key="workflow_id" value={v.workflow} values={v.workflows_menu} att="name" />
            </div>
            <Patch type="select" urlf={actions[model].patch} label="KitType" key="kit_type_id" value={v.kit_type} values={v.kit_types} att="name" />
            <Patch type="select" urlf={actions[model].patch} label="DataSet" key="data_set_id" value={v.data_set} values={v.data_sets} att="name" />
            {#each v.features as x}
                {#if x.name == x.value}
                    <Patch type="checkbox" urlf={actions[model].patch} label={x.label} key={x.name} value={v.constraintb[x.name]} meta="meta" />
                {:else if x.name == '1p_task_id'}
                    <Patch type="select" urlf={actions[model].patch} label={x.label} key={x.name} value={v.menu_task} values={v.menu_tasks} att="name" meta="meta" />
                {:else if x.name == 'docid' || x.name == 'notes' || x.name == 'dual_percentage' || x.name == 'dual_minimum_duration'}
                    <Patch type="input" urlf={actions[model].patch} label={x.label} key={x.name} value={v.constraintb[x.name]} meta="meta" />
                {:else}
                    <Patch type="input" urlf={actions[model].patch} label={x.label} key={x.name} value={v.constraintb[x.name]} />
                {/if}
            {/each}
            <div>
                {#if v.bucket}
                    Bucket {v.bucket} has {v.bucket_size} files
                {:else}
                    no bucket for this task
                {/if}
            </div>
        {/if}
        {#if model == 'kit_type'}
            <Patch type="select" urlf={actions[model].patch} label="Namespace" key="node_class_id" value={v.node_class} values={v.node_classes} att="name" />
            {#each v.features as x}
                {#if x.name == x.value}
                    <Patch type="checkbox" urlf={actions[model].patch} label={x.label} key={x.name} value={v.constraintb[x.name]} meta="constraints" />
                {:else if x.value == 'comma'}
                    <Patch type="input" urlf={actions[model].patch} label={x.label} key={x.name} value={v.constraintb[x.name]} meta="constraints" split="," />
                {:else}
                    <Patch type="input" urlf={actions[model].patch} label={x.label} key={x.name} value={v.constraintb[x.name]} meta="constraints" />
                {/if}
            {/each}
        {:else if model == 'feature'}
            <Patch type="input" urlf={actions[model].patch} label="Value" key="value" value={v.value} />
            <Patch type="input" urlf={actions[model].patch} label="Label" key="label" value={v.label} />
            <Patch type="textarea" urlf={actions[model].patch} label="Description" key="description" value={v.description} textarea={true} />
        {:else if model == 'workflow'}
            <Patch type="textarea" urlf={actions[model].patch} label="Description" key="description" value={v.description} textarea={true} />
            <Patch type="select" urlf={actions[model].patch} label="Type" key="type" value={v.type} values={v.types} />
        {/if}
    </div>
{/snippet}

{#snippet boiler3(model, p1, p2)}
    <div class="flex justify-around">
        <div>{all_label}</div>
        {#if models[model].id && models[model].index}
            <div>
                <button class={buttonVariants({ variant: "secondary" })} onclick={() => actions[model].get_one()}>Open</button>
            </div>
            {@render boiler7(model)}
            {#if p1}
                {@render dialog_delete(model)}
            {/if}
        {:else}
            Select a {models[model].label} in the table for more options.
        {/if}
        {#if p2}
            {@render dialog_create(model)}
        {/if}
    </div>
{/snippet}

{#snippet member_table(model, v, columns)}
    <Table
        indexf={x => models[model].user_index = x}
        {columns}
        rows={v.members}
        selectedf={(x) => selectedfmember(model, x)}
    />
{/snippet}


{#snippet member_tab(model, v)}
    {#if models[model].tab == "members"}
        <div class="flex justify-around">
            <div>Members</div>
            {#if v[model + '_admin_bool']}
                {#if models[model].user_id}
                    {@render dialog_delete_member(model)}
                {/if}
                {@render dialog_create_member(model)}
                {#if model == 'task'}
                    {@render dialog_copy_members(v)}
                {/if}
            {/if}
        </div>
        <div class="flex justify-aroundx p-6">
            <div class="float-leftx col-6 w-1/2">
                {#if model == 'project'}
                    {@render member_table(model, v, [
                        [ 'User ID', 'user_id', 'col-1' ],
                        [ 'Name', 'name', 'col-2' ],
                        [ 'Owner', 'owner', 'col-1' ],
                        [ 'Admin', 'admin', 'col-1' ]
                    ])}
                {:else if model == 'task'}
                    {@render member_table(model, v, [
                        [ 'User ID', 'user_id', 'col-1' ],
                        [ 'Name', 'name', 'col-2' ],
                        [ 'State', 'state', 'col-1' ],
                        [ 'Admin', 'admin', 'col-1' ]
                    ])}
                {:else if model == 'group'}
                    {@render member_table(model, v, [
                        [ 'User ID', 'user_id', 'col-1' ],
                        [ 'Name', 'name', 'col-2' ]
                    ])}
                {/if}
            </div>
            <div class="float-leftx col-6 p-6 w-1/2">
                {#if models[model].user_id && (v.project_owner_bool || v.task_admin_bool)}
                    {#each v.members as x}
                        {#if x.id == models[model].user_id}
                            {#if model == 'project'}
                                <div class="flex items-center space-x-4">
                                    <Patch type="checkbox" urlf={actions[model + '_user'].patch} label="Owner" key="owner" value={x.owner} reload={() => actions[model].get_one('members')} />
                                    <Patch type="checkbox" urlf={actions[model + '_user'].patch} label="Admin" key="admin" value={x.admin} reload={() => actions[model].get_one('members')} />
                                </div>
                            {:else if model == 'task'}
                                <div class="w-1/2">
                                    <Patch type="checkbox"   urlf={actions[model + '_user'].patch} label="Admin" key="admin" value={x.admin} reload={() => actions[model].get_one('members')} />
                                    {#if task_user_states.includes(x.state)}
                                        <Patch type="select" urlf={actions[model + '_user'].patch} label="State" key="state" value={x.state} reload={() => actions[model].get_one('members')} values={task_user_states} />
                                    {:else}
                                        Error
                                    {/if}
                                </div>
                                <div class="my-4">
                                    {#if taskuserpp}
                                        {#await taskuserpp}
                                            <div class="mx-auto w-8 h-8"><Spinner /></div>
                                        {:then v}
                                            <pre>
                                                {v.ok}
                                            </pre>
                                        {/await}
                                    {/if}
                                </div>
                            {/if}
                        {/if}
                    {/each}
                {/if}
            </div>
        </div>
    {/if}
{/snippet}

{#snippet boiler7(model)}
    {#if style}
        <div {style}>
            {#if model == 'project'}
                <div><button class={buttonVariants({ variant: "secondary" })} onclick={() => actions[model].get_one()}>Open Project Info</button></div>
                <div><button class={buttonVariants({ variant: "secondary" })} onclick={() => actions[model].get_one('tasks')} data-guide-target="open_task_list">Open Task List</button></div>
            {:else if model == 'task'}
                <div><button class={buttonVariants({ variant: "secondary" })} onclick={() => actions[model].get_one()} data-guide-target="open_task_info">Open Task Info</button></div>
                <div><button class={buttonVariants({ variant: "secondary" })} onclick={() => actions[model].get_one('kits')} data-guide-target="open_kit_list">Open Kit List</button></div>
            {:else}
                <div><button class={buttonVariants({ variant: "secondary" })} onclick={() => actions[model].get_one()}>Open</button></div>
            {/if}
        </div>
    {/if}
{/snippet}

<!-- <PageTabs {pages} {page} on:page={pagef} {admin} {lead_annotator} {help} on:help={helpf} /> -->

<!-- Reserved strip above the tabs (≈ tabs height) for a future banner. -->
<div class="h-10"></div>

<Tabs.Root bind:value={tab} class="w-full justify-center" onValueChange={tabs}>
    <Tabs.List>
        <Tabs.Trigger value="tasks" data-guide-target="work_tab">
            <Tooltip.Provider>
                <Tooltip.Root>
                    <Tooltip.Trigger>Work</Tooltip.Trigger>
                    <Tooltip.Content>your tasks with links to start</Tooltip.Content>
                </Tooltip.Root>
            </Tooltip.Provider>
        </Tabs.Trigger>
        <Tabs.Trigger value="projects" data-guide-target="projects_tab">
            <Tooltip.Provider>
                <Tooltip.Root>
                    <Tooltip.Trigger>Projects</Tooltip.Trigger>
                    <Tooltip.Content>projects, tasks, kits</Tooltip.Content>
                </Tooltip.Root>
            </Tooltip.Provider>
        </Tabs.Trigger>
        <Tabs.Trigger value="browse">
            <Tooltip.Provider>
                <Tooltip.Root>
                    <Tooltip.Trigger>Browse</Tooltip.Trigger>
                    <Tooltip.Content>browse uploaded files</Tooltip.Content>
                </Tooltip.Root>
            </Tooltip.Provider>
        </Tabs.Trigger>
        <Tabs.Trigger value="kit_types">
            <Tooltip.Provider>
                <Tooltip.Root>
                    <Tooltip.Trigger>Kit Types</Tooltip.Trigger>
                    <Tooltip.Content>tasks require a kit type</Tooltip.Content>
                </Tooltip.Root>
            </Tooltip.Provider>
        </Tabs.Trigger>
        <Tabs.Trigger value="features">
            <Tooltip.Provider>
                <Tooltip.Root>
                    <Tooltip.Trigger>Features</Tooltip.Trigger>
                    <Tooltip.Content>features for different objects</Tooltip.Content>
                </Tooltip.Root>
            </Tooltip.Provider>
        </Tabs.Trigger>
        <Tabs.Trigger value="workflows">
            <Tooltip.Provider>
                <Tooltip.Root>
                    <Tooltip.Trigger>Workflows</Tooltip.Trigger>
                    <Tooltip.Content>workflows</Tooltip.Content>
                </Tooltip.Root>
            </Tooltip.Provider>
        </Tabs.Trigger>
        <Tabs.Trigger value="groups">
            <Tooltip.Provider>
                <Tooltip.Root>
                    <Tooltip.Trigger>Groups</Tooltip.Trigger>
                    <Tooltip.Content>users can be added to groups</Tooltip.Content>
                </Tooltip.Root>
            </Tooltip.Provider>
        </Tabs.Trigger>
        <Tabs.Trigger value="invites">
            <Tooltip.Provider>
                <Tooltip.Root>
                    <Tooltip.Trigger>Invites</Tooltip.Trigger>
                    <Tooltip.Content>users can be invited</Tooltip.Content>
                </Tooltip.Root>
            </Tooltip.Provider>
        </Tabs.Trigger>
        <Tabs.Trigger value="permissions">
            <Tooltip.Provider>
                <Tooltip.Root>
                    <Tooltip.Trigger>Permissions</Tooltip.Trigger>
                    <Tooltip.Content>explore roles and permissions</Tooltip.Content>
                </Tooltip.Root>
            </Tooltip.Provider>
        </Tabs.Trigger>
        {#if portal_manager}
            <Tabs.Trigger value="activations">
                <Tooltip.Provider>
                    <Tooltip.Root>
                        <Tooltip.Trigger>Activations</Tooltip.Trigger>
                        <Tooltip.Content>activate pending users</Tooltip.Content>
                    </Tooltip.Root>
                </Tooltip.Provider>
            </Tabs.Trigger>
        {/if}
        <Tabs.Trigger value="account">
            <Tooltip.Provider>
                <Tooltip.Root>
                    <Tooltip.Trigger>Account</Tooltip.Trigger>
                    <Tooltip.Content>your own account settings</Tooltip.Content>
                </Tooltip.Root>
            </Tooltip.Provider>
        </Tabs.Trigger>
    </Tabs.List>
    <Tabs.Content value="tasks">
        <Help {help}>
            {#snippet content()}
            <div>
                <p>These are your tasks</p>
                <p>The Action column contains links to annotation tools, if work is available</p>
                <p>Clicking on a Project or Task name will jump to the appropriate tab</p>
            </div>
            {/snippet}
        </Help>
            <!-- <UsersTasks {help} {admin} {lead_annotator} {p} {project} {task} /> -->
        <!-- {#await p}
            <div class="mx-auto w-8 h-8"><Spinner /></div>
        {:then v} -->
            <Table
                indexf={x => null}
                columns={[
                    [ 'Project',   'project', 'col-1', 'f', (x, y) => goto(x, y) ],
                    [ 'Task',      'task',    'col-2', 'f', (x, y) => goto(x, y) ],
                    [ 'Action',    'action',  'col-1', 'html' ],
                    [ 'Status',    'state',   'col-1' ],
                    [ 'Done Kits', 'done',    'col-1' ]
                ]}
                rows={tus}
                key_column="task"
                selectedf={() => null}
            />
        <!-- {/await} -->
    </Tabs.Content>
    <Tabs.Content value="projects">
        {#if tab == 'projects'}
    <!-- <Projects   {help} {admin} {lead_annotator} {goto_project} {goto_task} {reload2} /> -->
            <Help {help}>
                {#snippet content()}
                    <div>
                        <p>Projects contain Tasks, which in turn contain Kits</p>
                        <p>Select and Open a Project from the table</p>
                        {#if lead_annotator}
                            <p>You also have permission to create a new Project</p>
                        {/if}
                    </div>
                {/snippet}
            </Help>
            {#await tabp}
                <div class="mx-auto w-8 h-8"><Spinner /></div>
            {:then v}
                {#if pp}
                    {@render boiler2('project')}
                    {#await pp}
                        <div class="mx-auto w-8 h-8"><Spinner /></div>
                    {:then v}
                        {@render boiler4(v)}
                        <Tabs.Root bind:value={models.project.tab} class="w-full">
                            <Tabs.List>
                                <Tabs.Trigger value="info">Project Info</Tabs.Trigger>
                                <Tabs.Trigger value="tasks" data-guide-target="project_tasks_tab">Project Tasks</Tabs.Trigger>
                                <Tabs.Trigger value="members">Project Members</Tabs.Trigger>
                            </Tabs.List>
                            <Tabs.Content value="info">
                                {@render boiler5('project', v)}
                            </Tabs.Content>
                            <Tabs.Content value="tasks">
                                <Help {help}>
                                    {#snippet content()}
                                        <div>
                                            <p>Tasks contain Kits</p>
                                            <p>Select and Open a Task from the table</p>
                                            {#if v.project_admin_bool}
                                                <p>You also have permission to create a new Task</p>
                                            {/if}
                                        </div>
                                    {/snippet}
                                </Help>
                                {#if taskpp}
                                    <div class="float-right">
                                        <button class="{btn}" onclick={() => (taskpp = null) || actions.project.get_one('tasks')}>Return to Task list</button>
                                    </div>
                                    {#await taskpp}
                                        <div class="mx-auto w-8 h-8"><Spinner /></div>
                                    {:then vv}
                                        {#if vv.error}
                                            <div>Error: {vv.error}</div>
                                        {:else}
                                            <div class="float-right p-2">
                                                {vv.name} {vv.id}
                                            </div>
                                            <!-- <Task {help} {project_admin} {project_id} {task_id} {...v} {project_users} reload={open} {info} /> -->
                                            <!-- {task_id} {task_index[task_id].name} -->
                                            <Tabs.Root bind:value={models.task.tab} class="w-full justify-center">
                                                <Tabs.List>
                                                    <Tabs.Trigger value="info" data-guide-target="task_info_tab">Task Info</Tabs.Trigger>
                                                    <Tabs.Trigger value="kits" data-guide-target="kits_tab">Kits</Tabs.Trigger>
                                                    <Tabs.Trigger value="done">Done Kits</Tabs.Trigger>
                                                    <Tabs.Trigger value="sources">Sources</Tabs.Trigger>
                                                    <Tabs.Trigger value="duals">Duals</Tabs.Trigger>
                                                    <Tabs.Trigger value="members" data-guide-target="task_members_tab">Task Members</Tabs.Trigger>
                                                    <Tabs.Trigger value="docids">Docid List</Tabs.Trigger>
                                                    <Tabs.Trigger value="batches">Batches</Tabs.Trigger>
                                                    <Tabs.Trigger value="nodes">Nodes</Tabs.Trigger>
                                                    <Tabs.Trigger value="nb">New Batches</Tabs.Trigger>
                                                </Tabs.List>
                                                <Tabs.Content value="info">
                                                    {#if models.task.tab == 'info'}
                                                        {#if v.project_admin_bool}
                                                            {@render boiler5('task', vv)}
                                                        {:else}
                                                            <div class="col-3 mx-auto">
                                                                <div>ID: {vv.id}</div>
                                                                <div>Name: {vv.name}</div>
                                                            </div>
                                                        {/if}
                                                    {/if}
                                                </Tabs.Content>
                                                <Tabs.Content value="kits">
                                                    {#if models.task.tab == 'kits'}
                                                        <!-- <Kits
                                                            {help}
                                                            project_id={v.id}
                                                            task_id={vv.id}
                                                            task_admin={vv.task_admin_bool}
                                                            task_users={vv.members}
                                                        /> -->
                                                        {#await kitsp}
                                                            <div class="mx-auto w-8 h-8"><Spinner /></div>
                                                        {:then rows}
                                                            {#if kitspp}
                                                                <div class="float-right">
                                                                    <button class="{btn}" onclick={back}>Return to kit list</button>
                                                                </div>
                                                                {#await kitspp}
                                                                    <div class="mx-auto w-8 h-8"><Spinner /></div>
                                                                {:then vvv}
                                                                    <!-- <Kit
                                                                        task_admin={vv.task_admin_bool}
                                                                        task_users={vv.members}
                                                                        {...vvv}
                                                                    /> -->
                                                                    {#if vv.task_admin_bool}
                                                                        <div class="col-3 mx-auto">
                                                                            <div>ID: {vvv.id}</div>
                                                                            <div>UID: {vvv.uid}</div>
                                                                            <form onsubmit={()=>null} onpreventDefault={()=>null}>
                                                                                <InputSelect
                                                                                    url={`/kits/${vvv.id}/update`}
                                                                                    label="User"
                                                                                    key="user_id"
                                                                                    value={menu_userf(vvv.user_id, vv.members)}
                                                                                    values={[ user_none ].concat(vv.members)}
                                                                                    att="name"
                                                                                    idk="user_id"
                                                                                />
                                                                            </form>
                                                                        </div>
                                                                    {:else}
                                                                        <div class="col-3 mx-auto">
                                                                            <div>ID: {vvv.id}</div>
                                                                            <div>Name: {vvv.name}</div>
                                                                        </div>
                                                                    {/if}
                                                                        <!-- {project_id} -->
                                                                        <!-- {task_id} -->
                                                                    <!-- {task_id} {kit_index[task_id].name} -->
                                                                {/await}
                                                            {:else}
                                                                {#if kit_creation}
                                                                    <!-- The dialog has closed by the time the server answers, so
                                                                         what it made — and what it wouldn't — is reported here. -->
                                                                    <div class="mb-3 text-sm rounded p-2 {kit_creation.errors && kit_creation.errors.length ? 'bg-red-50 border border-red-200' : 'bg-green-50 border border-green-200'}">
                                                                        <div>{kit_creation.created ?? 0} kit{(kit_creation.created ?? 0) === 1 ? '' : 's'} created</div>
                                                                        {#each (kit_creation.errors || []) as e}
                                                                            <div class="font-mono text-xs text-red-800">{e}</div>
                                                                        {/each}
                                                                    </div>
                                                                {/if}
                                                                <div class="flex justify-around mb-4">
                                                                    {#if vv.task_admin_bool}
                                                                        <div>All Kits</div>
                                                                        <!-- A drawing of what this task's kits have annotated:
                                                                             the graph tables on a timeline, a lane per kind of
                                                                             span. Its own page rather than a tab, so it can be
                                                                             linked to. Task admins only, like the page itself. -->
                                                                        <a class={buttonVariants({ variant: "secondary" })}
                                                                           href="/projects/{v.id}/tasks/{vv.id}/graph">Annotation Graph</a>
                                                                        <!-- <UploadKitList task_id={vv.id} reload2={get_kitsp} /> -->
                                                                        <Dialog.Root>
                                                                            <Dialog.Trigger class={buttonVariants({ variant: "secondary" })} data-guide-target="create_kits_text">Create Kits (Text Input)</Dialog.Trigger>
                                                                            <Dialog.Content class="max-w-2xl w-[92vw]">
                                                                                <Dialog.Header>
                                                                                    <Dialog.Title>Create Kits</Dialog.Title>
                                                                                    <Dialog.Description>
                                                                                            Type here
                                                                                    </Dialog.Description>
                                                                                </Dialog.Header>
                                                                                <div class="space-y-3 min-w-0">
                                                                                    <textarea
                                                                                    bind:value={typed}
                                                                                    rows="6"
                                                                                    class="block w-full rounded-md border border-gray-300 p-2 font-mono text-sm shadow-sm focus:ring-indigo-500 focus:border-indigo-500 box-border"
                                                                                    ></textarea>
                                                                                    <div>
                                                                                        {#if typed}
                                                                                            {#if json_typed}
                                                                                                {#if parsed_errors.length}
                                                                                                    <div class="text-sm text-red-700 mb-2">
                                                                                                        {parsed_errors.length} line{parsed_errors.length === 1 ? '' : 's'} can't be read:
                                                                                                        {#each parsed_errors.slice(0, 5) as x}
                                                                                                            <div class="font-mono text-xs">{x.docid} — {x.error}</div>
                                                                                                        {/each}
                                                                                                    </div>
                                                                                                {:else}
                                                                                                    <button class="{btn}" onclick={() => add(vv.id, json_typed)} data-close-dialog>Create Kits</button>
                                                                                                {/if}
                                                                                            {:else}
                                                                                                <span class="text-sm text-gray-600 mr-2">
                                                                                                    one docid per line, optionally followed by user_id=&lt;id, name or email&gt;
                                                                                                </span>
                                                                                                <button class="{btn}" onclick={() => json_typed = parse_kits(typed)}>parse as text</button>
                                                                                            {/if}
                                                                                        {/if}
                                                                                    </div>
                                                                                    {#if json_typed}
                                                                                        <pre class="bg-gray-50 border border-gray-200 rounded p-2 text-xs font-mono whitespace-pre-wrap break-all max-h-64 overflow-auto min-w-0">{#each json_typed as x}{JSON.stringify(x) + "\n"}{/each}</pre>
                                                                                    {:else if typed}
                                                                                        {#if jsonn}
                                                                                            <h5 class="text-sm font-semibold text-gray-700">Original, first 1000 characters</h5>
                                                                                            <pre class="bg-gray-50 border border-gray-200 rounded p-2 text-xs font-mono whitespace-pre-wrap break-all max-h-64 overflow-auto min-w-0">{typed.substr(0,999)}</pre>
                                                                                        {:else}
                                                                                            <h5 class="text-sm font-semibold text-gray-700">Original, first 10 lines</h5>
                                                                                            <pre class="bg-gray-50 border border-gray-200 rounded p-2 text-xs font-mono whitespace-pre-wrap break-all max-h-64 overflow-auto min-w-0">{typed.split("\n").slice(0,9).join("\n")}</pre>
                                                                                        {/if}
                                                                                    {/if}
                                                                                </div>
                                                                                <!-- <Dialog.Footer>
                                                                                    <Button variant="secondary" onclick={() => reassign(v.id, vv.id)}>Reassign</Button>
                                                                                </Dialog.Footer> -->
                                                                            </Dialog.Content>
                                                                        </Dialog.Root>
                                                                        <Dialog.Root>
                                                                            <Dialog.Trigger class={buttonVariants({ variant: "secondary" })}>Create Kits (File Input)</Dialog.Trigger>
                                                                            <Dialog.Content class="max-w-2xl w-[92vw]">
                                                                                <Dialog.Header>
                                                                                    <Dialog.Title>Create Kits</Dialog.Title>
                                                                                    <Dialog.Description>
                                                                                            Upload a file
                                                                                    </Dialog.Description>
                                                                                </Dialog.Header>
                                                                                <div class="space-y-3 min-w-0">
                                                                                    <input
                                                                                    type="file"
                                                                                    bind:files
                                                                                    class="block w-full rounded-md border border-gray-300 p-2 text-sm shadow-sm focus:ring-indigo-500 focus:border-indigo-500 box-border"
                                                                                    >
                                                                                    <div>
                                                                                        {#if files && files[0]}
                                                                                            {#if json_upload}
                                                                                                {#if parsed_errors_upload.length}
                                                                                                    <div class="text-sm text-red-700 mb-2">
                                                                                                        {parsed_errors_upload.length} line{parsed_errors_upload.length === 1 ? '' : 's'} can't be read:
                                                                                                        {#each parsed_errors_upload.slice(0, 5) as x}
                                                                                                            <div class="font-mono text-xs">{x.docid} — {x.error}</div>
                                                                                                        {/each}
                                                                                                    </div>
                                                                                                {:else}
                                                                                                    <button class="{btn}" onclick={() => add(vv.id, json_upload)} data-close-dialog>Create Kits</button>
                                                                                                {/if}
                                                                                            {:else if text_upload}
                                                                                                {#if tdf}
                                                                                                    <span class="text-sm text-gray-600 mr-2">
                                                                                                        one docid per line, optionally followed by user_id=&lt;id, name or email&gt;
                                                                                                    </span>
                                                                                                    <button class="{btn}" onclick={() => json_upload = parse_kits(text_upload)}>parse as text</button>
                                                                                                {:else if jsonn}
                                                                                                    <span class="text-sm text-gray-600 mr-2">file appears to be JSON</span>
                                                                                                    <button class="{btn}" onclick={() => json_upload = parse_jsonn(text_upload)}>parse as JSON</button>
                                                                                                {:else}
                                                                                                    <span class="text-sm text-gray-600">unknown format</span>
                                                                                                {/if}
                                                                                            {:else}
                                                                                                <button class="{btn}" onclick={upload}>upload</button>
                                                                                            {/if}
                                                                                        {/if}
                                                                                    </div>
                                                                                    {#if json_upload}
                                                                                        <pre class="bg-gray-50 border border-gray-200 rounded p-2 text-xs font-mono whitespace-pre-wrap break-all max-h-64 overflow-auto min-w-0">{#each json_upload as x}{JSON.stringify(x) + "\n"}{/each}</pre>
                                                                                    {:else if text_upload}
                                                                                        {#if tdf}
                                                                                            <h5 class="text-sm font-semibold text-gray-700">Original, first 10 lines</h5>
                                                                                            <pre class="bg-gray-50 border border-gray-200 rounded p-2 text-xs font-mono whitespace-pre-wrap break-all max-h-64 overflow-auto min-w-0">{text_upload.split("\n").slice(0,9).join("\n")}</pre>
                                                                                        {:else if jsonn}
                                                                                            <h5 class="text-sm font-semibold text-gray-700">Original, first 1000 characters</h5>
                                                                                            <pre class="bg-gray-50 border border-gray-200 rounded p-2 text-xs font-mono whitespace-pre-wrap break-all max-h-64 overflow-auto min-w-0">{text_upload.substr(0,999)}</pre>
                                                                                        {/if}
                                                                                    {/if}
                                                                                </div>
                                                                                <!-- <Dialog.Footer>
                                                                                    <Button variant="secondary" onclick={() => reassign(v.id, vv.id)}>Reassign</Button>
                                                                                </Dialog.Footer> -->
                                                                            </Dialog.Content>
                                                                        </Dialog.Root>
                                                                        <Dialog.Root>
                                                                            <Dialog.Trigger class={buttonVariants({ variant: "secondary" })}>Bulk Reassign</Dialog.Trigger>
                                                                            <Dialog.Content>
                                                                                <Dialog.Header>
                                                                                    <Dialog.Title>Bulk Reassign</Dialog.Title>
                                                                                    <Dialog.Description>
                                                                                        Reassign all matched kits in table below
                                                                                    </Dialog.Description>
                                                                                </Dialog.Header>
                                                                                <div>
                                                                                    <label>
                                                                                        User
                                                                                        <select bind:value={new_user}>
                                                                                            <option value={null}>don't change</option>
                                                                                            <option value={emptyv}>none</option>
                                                                                            {#each vv.members as x}
                                                                                                <option value={x}>{x.name}</option>
                                                                                            {/each}
                                                                                        </select>
                                                                                    </label>
                                                                                    <label>
                                                                                        State
                                                                                        <select bind:value={new_state}>
                                                                                            <option value={null}>don't change</option>
                                                                                            {#each states as x}
                                                                                                <option value={x}>{x}</option>
                                                                                            {/each}
                                                                                        </select>
                                                                                    </label>
                                                                                </div>
                                                                                <Dialog.Footer>
                                                                                    <Button variant="secondary" onclick={() => reassign(v.id, vv.id)}>Reassign</Button>
                                                                                </Dialog.Footer>
                                                                            </Dialog.Content>
                                                                        </Dialog.Root>
                                                                    {:else}
                                                                        <div>My Kits</div>
                                                                    {/if}
                                                                    {#if models.kit.id}
                                                                        <div>
                                                                            <button class="{btn}" onclick={open_kit}>Open</button>
                                                                        </div>
                                                            <!--                {#if task_admin}
                                                                            <Modal {...deletem}>
                                                                                <div slot=summary>
                                                                                    Delete
                                                                                </div>
                                                                                <div slot=body>
                                                                                    This will delete the task {kit_index[task_id].name}, are you sure you want to do this?
                                                                                </div>
                                                                            </Modal>
                                                                        {/if} -->
                                                                    {/if}
                                                                    {#if vv.task_admin_bool}
                                                                        <!-- <DownloadTranscripts task_id={vv.id} /> -->
                                                                        <Dialog.Root>
                                                                            <Dialog.Trigger class={buttonVariants({ variant: "secondary" })}>
                                                                                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                                                                                    <path fill-rule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm3.293-7.707a1 1 0 011.414 0L9 10.586V3a1 1 0 112 0v7.586l1.293-1.293a1 1 0 111.414 1.414l-3 3a1 1 0 01-1.414 0l-3-3a1 1 0 010-1.414z" clip-rule="evenodd" />
                                                                                </svg>
                                                                            </Dialog.Trigger>
                                                                            <Dialog.Content>
                                                                                <Dialog.Header>
                                                                                    <Dialog.Title>Download Transcript</Dialog.Title>
                                                                                    <Dialog.Description>
                                                                                        Download one or more transcripts, with variable columns.
                                                                                    </Dialog.Description>
                                                                                </Dialog.Header>
                                                                                <div class="overflow-auto">
                                                                                    <div class="Box-body overflow-auto">
                                                                                        <div>
                                                                                            {#await downloadp}
                                                                                                <div class="mx-auto w-8 h-8"><Spinner /></div>
                                                                                            {:then v}
                                                                                                {JSON.stringify(v)}
                                                                                            {/await}
                                                                                            <div class="form-group">
                                                                                                <div class="form-group-header">Filename (.tsv will be appended)</div>
                                                                                                <div class="form-group-body">
                                                                                                    <input
                                                                                                        type=text
                                                                                                        class="focus:ring-indigo-500 focus:border-indigo-500 flex-1 block w-full rounded-md border-gray-300"
                                                                                                        bind:value={filename}
                                                                                                    />
                                                                                                </div>
                                                                                            </div>
                                                                                            <div class="form-group">
                                                                                                <div class="form-group-header">
                                                                                                    <label>
                                                                                                        <input
                                                                                                            type=checkbox
                                                                                                            class="focus:ring-indigo-500 focus:border-indigo-500 h-4 w-4 border-gray-300"
                                                                                                            bind:checked={include_headers}
                                                                                                        />
                                                                                                        Include Headers
                                                                                                    </label>
                                                                                                </div>
                                                                                            </div>
                                                                                            <div class="form-group">
                                                                                                <div class="form-group-header">
                                                                                                    <label>
                                                                                                        <input
                                                                                                            type=checkbox
                                                                                                            class="focus:ring-indigo-500 focus:border-indigo-500 h-4 w-4 border-gray-300"
                                                                                                            bind:checked={include_speaker}
                                                                                                        />
                                                                                                        Include Speaker
                                                                                                    </label>
                                                                                                </div>
                                                                                            </div>
                                                                                            <div class="form-group">
                                                                                                <div class="form-group-header">
                                                                                                    <label>
                                                                                                        <input
                                                                                                            type=checkbox
                                                                                                            class="focus:ring-indigo-500 focus:border-indigo-500 h-4 w-4 border-gray-300"
                                                                                                            bind:checked={include_section}
                                                                                                        />
                                                                                                        Include Section
                                                                                                    </label>
                                                                                                </div>
                                                                                            </div>
                                                                                        </div>
                                                                                        <!-- {#if json}
                                                                                            <button class="{btn}" on:click={add} data-close-dialog>add</button>
                                                                                        {:else if text}
                                                                                            <button class="{btn}" on:click={download}>download</button>
                                                                                        {/if} -->
                                                                                        <div><button class="{btn}" onclick={() => create_download(vv.id)}>Create</button> a transcript file, which you can preview below
                                                                                            {#if url}
                                                                                                <!-- svelte-ignore a11y_missing_attribute -->
                                                                                                and then <a bind:this={link} download={filename}>Download</a>
                                                                                            {/if}
                                                                                            {#if json_download}
                                                                                                {#each json_download as x}
                                                                                                    {JSON.stringify(x) + "\n"}
                                                                                                {/each}
                                                                                            {:else if textt}
                                                                                                <h4>Preview</h4>
                                                                                                <pre>{textt}</pre>
                                                                                            {/if}
                                                                                        </div>
                                                                                    </div>
                                                                                </div>
                                                                                <!-- <Dialog.Footer>
                                                                                    <Button variant="secondary" onclick={() => reassign(v.id, vv.id)}>Save</Button>
                                                                                </Dialog.Footer> -->
                                                                            </Dialog.Content>
                                                                        </Dialog.Root>
                                                            <!--                 <Modal {...createm}>
                                                                            <div slot=summary>
                                                                                Create Task
                                                                            </div>
                                                                            <div slot=body>
                                                                                <form>
                                                                                    <label>
                                                                                        Name
                                                                                        <input type=text bind:value={name}/>
                                                                                    </label>
                                                                                </form>
                                                                            </div>
                                                                            <div slot=footer>
                                                                                <button type="button" class="{btn}"   data-close-dialog on:click={create}>Create</button>
                                                                            </div>
                                                                        </Modal> -->
                                                                    {/if}
                                                                </div>
                                                                <hr>
                                                                <Help {help}>
                                                                    {#snippet content()}
                                                                        <div>
                                                                            <p>The table can be filtered by user, state, and text (which matches any column)</p>
                                                                            <p>The filters are conjoined (all must be true)</p>
                                                                            <p>The Bulk Reassign feature depends on these filters; the filters select the kits to be reassigned</p>
                                                                        </div>
                                                                    {/snippet}
                                                                </Help>
                                                                {#if rows}
                                                                    <Table
                                                                        bind:this={kits_for_task_table}
                                                                        indexf={x => models.kit.index = x}
                                                                        columns={[
                                                                            [ 'ID', 'id', 'col-1' ],
                                                                            [ 'UID', 'uid', 'col-1', 'f', (x, y) => window.open(x.link) ],
                                                                            [ 'State', 'state', 'col-1', 'filter' ],
                                                                            [ 'Source', 'source_uid', 'col-1' ],
                                                                            [ 'Continue', 'continue', 'col-1', 'html' ],
                                                                            [ 'User', 'user', 'col-1', 'filter' ],
                                                                            [ 'Broken Comment', 'broken_comment', 'col-1' ],
                                                                            [ 'Updated At', 'updated_at', 'col-1' ]
                                                                        ]}
                                                                        {rows}
                                                                        selectedf={(x, y) => (models.kit.id = x) && set_style(y)}
                                                                    />
                                                                {/if}
                                                            {/if}
                                                        {/await}
                                                    {/if}
                                                </Tabs.Content>
                                                <Tabs.Content value="done">
                                                    {#if models.task.tab == 'done'}
                                                        <!-- <DoneKits
                                                            {help}
                                                            project_id={v.id}
                                                            task_id={vv.id}
                                                            task_admin={vv.task_admin_bool}
                                                            task_users={vv.members}
                                                        /> -->
                                                        {#await donekitsp}
                                                            <div class="mx-auto w-8 h-8"><Spinner /></div>
                                                        {:then rows}
                                                            <div class="flex justify-around mb-4">
                                                                {#if vv.task_admin_bool}
                                                                    <div>All Done Kits</div>
                                                                    <!-- dialogs -->
                                                                {:else}
                                                                    <div>My Done Kits</div>
                                                                {/if}
                                                            </div>
                                                            <hr>
                                                            {#if rows}
                                                                <Table
                                                                    bind:this={donekits_for_task_table}
                                                                    indexf={x => models.donekit.index = x}
                                                                    columns={[
                                                                        [ 'ID', 'id', 'col-1' ],
                                                                        [ 'UID', 'uid', 'col-1', 'f', (x, y) => window.open(x.link) ],
                                                                        [ 'Source', 'source_uid', 'col-1' ],
                                                                        [ 'User', 'user', 'col-1', 'filter' ],
                                                                        [ 'Done Comment', 'done_comment', 'col-1' ],
                                                                    ]}
                                                                    {rows}
                                                                    selectedf={(x, y) => (models.donekit.id = x) && set_style(y)}
                                                                />
                                                            {/if}
                                                        {/await}
                                                    {/if}
                                                </Tabs.Content>
                                                <Tabs.Content value="sources">
                                                    {#if models.task.tab == 'sources'}
                                                        {#if comparison_source}
                                                            {@render source_comparison()}
                                                        {:else}
                                                            {#await sourcesp}
                                                                <div class="mx-auto w-8 h-8"><Spinner /></div>
                                                            {:then rows}
                                                                <div class="flex justify-around mb-4">
                                                                    <div>Sources ({rows ? rows.length : 0})</div>
                                                                    <div class="text-sm text-gray-600">click a source to compare its transcripts</div>
                                                                </div>
                                                                <hr>
                                                                {#if rows}
                                                                    <Table
                                                                        key_column="source"
                                                                        download={true}
                                                                        columns={[
                                                                            [ 'Source', 'source', 'col-5' ],
                                                                            [ 'Users Done', 'done_users', 'col-1' ],
                                                                            [ 'Who', 'users', 'col-3' ],
                                                                            [ 'Done Kits', 'done_kits', 'col-1' ],
                                                                            [ 'Kits', 'kits', 'col-1' ],
                                                                        ]}
                                                                        {rows}
                                                                        selectedf={(x, y) => open_comparison(x)}
                                                                    />
                                                                {/if}
                                                            {/await}
                                                        {/if}
                                                    {/if}
                                                </Tabs.Content>
                                                <Tabs.Content value="duals">
                                                    {#if tab == 'duals'}duals
                                                <!-- <Duals
                                                    {help}
                                                    {project_id}
                                                    {task_id}
                                                    task_admin={task_admin_boovv.l}
                                                    {task_users}
                                                    {meta}
                                                /> -->
                                                    {/if}
                                                </Tabs.Content>
                                                <Tabs.Content value="members">
                                                    {@render member_tab('task', vv)}
                                                </Tabs.Content>
                                                <Tabs.Content value="docids">
                                                    <!-- The documents this task gives every user,
                                                         read by the SameListForEveryone workflow. -->
                                                    {#if models.task.tab == 'docids'}
                                                        {#if v.project_admin_bool || vv.task_admin_bool}
                                                            <TaskDocids task_id={vv.id} />
                                                        {:else}
                                                            <div class="p-3 text-sm text-gray-600">Permission Denied</div>
                                                        {/if}
                                                    {/if}
                                                </Tabs.Content>
                                                <Tabs.Content value="batches">
                                                    {#if tab == 'batches'}batches
                                                <!-- {#if project_admin || lead_annotator || task_admin_bool}
                                                    <KitBatches
                                                        {help}
                                                        {project_id}
                                                        {task_id}
                                                        task_admin={task_admin_bool}
                                                        {task_users}
                                                    />
                                                {:else}
                                                    Permission Denied
                                                {/if} -->
                                                    {/if}
                                                </Tabs.Content>
                                                <Tabs.Content value="nodes">
                                                    {#if tab == 'nodes'}nodes
                                                <!-- {#if project_admin || lead_annotator || task_admin_bool}
                                                    <Nodes
                                                        {project_id}
                                                        {task_id}
                                                    />
                                                {:else}
                                                    Permission Denied
                                                {/if} -->
                                                    {/if}
                                                </Tabs.Content>
                                                <Tabs.Content value="nb">
                                                    {#if tab == 'nb'}nb
                                                <!-- {#if project_admin || lead_annotator || task_admin_bool}
                                                    <NewBatches
                                                        {help}
                                                        {task_id}
                                                        task_admin={task_admin_bool}
                                                        {task_users}
                                                    />
                                                {:else}
                                                    Permission Denied
                                                {/if} -->
                                                    {/if}
                                                </Tabs.Content>
                                            </Tabs.Root>
                                        {/if}
                                    {/await}
                                {:else}
                                    <div class="flex justify-around items-center my-2">
                                        {#if v.project_admin_bool}
                                            <div class="font-semibold">All Tasks</div>
                                        {:else}
                                            <div class="font-semibold">My Tasks</div>
                                        {/if}
                                        {#if models.task.id && models.task.index}
                                            <div>
                                                <button class={buttonVariants({ variant: "secondary" })} onclick={() => actions.task.get_one()}>Open</button>
                                            </div>
                                            {@render boiler7('task')}
                                            {#if v.project_admin_bool}
                                                {@render dialog_delete('task')}
                                            {/if}
                                        {/if}
                                        {#if v.project_admin_bool}
                                            {@render dialog_create('task')}
                                        {/if}
                                    </div>
                                    <Table
                                        indexf={x => models.task.index = x}
                                        columns={[
                                            [ 'ID', 'id', 'col-1' ],
                                            [ 'Task', 'name', 'col-2' ],
                                            [ 'Available Kits', 'available_kit_count', 'col-1' ],
                                            [ 'Source UID', 'source_uid', 'col-1' ]
                                        ]}
                                        rows={v.tasks}
                                        selectedf={(x, y) => (models.task.id = x) && set_style(y)}
                                    />
                                {/if}
                            </Tabs.Content>
                            <Tabs.Content value="members">
                                {@render member_tab('project', v)}
                            </Tabs.Content>
                        </Tabs.Root>
                    {/await}
                {:else}
                    {@render boiler3("project", admin, lead_annotator)}
                    <Table
                        indexf={x => models.project.index = x}
                        columns={[
                            [ 'ID', 'id', 'col-1' ],
                            [ 'Project', 'name', 'col-2', 'html' ],
                            [ 'Task Count', 'task_count', 'col-1' ]
                        ]}
                        rows={v}
                        selectedf={(x, y) => (models.project.id = x) && set_style(y)}
                    />
                {/if}
            {/await}
        {/if}
    </Tabs.Content>
    <Tabs.Content value="browse">
        {#if tab == 'browse'}
    <!-- <Browse
        {help}
        {admin}
        {portal_manager}
        {project_manager}
        p={Promise.resolve(tus)}
        bind:this={browsex}
    /> -->
        deactivated
        {/if}
    </Tabs.Content>
    <Tabs.Content value="kit_types">
        <Help {help}>
            {#snippet content()}
                <div>
                    <p>kit types</p>
                </div>
            {/snippet}
        </Help>
        {#if tab == 'kit_types'}
            {#await tabp}
                <div class="mx-auto w-8 h-8"><Spinner /></div>
            {:then v}
                {#if pp}
                    {@render boiler1('kit_type')}
                {:else}
                    {@render boiler3('kit_type', admin, lead_annotator)}
                    <Table
                        indexf={x => models.kit_type.index = x}
                        columns={[
                            [ 'ID', 'id', 'col-1' ],
                            [ 'Name', 'name', 'col-2' ]
                        ]}
                        rows={v}
                        selectedf={(x, y) => (models.kit_type.id = x) && set_style(y)}
                    />
                {/if}
            {/await}
        {/if}
    </Tabs.Content>
    <Tabs.Content value="features">
        {#if tab == 'features'}
            <Help {help}>
                {#snippet content()}
                <div>
                    <p>features</p>
                </div>
                {/snippet}
            </Help>
            {#await tabp}
                <div class="mx-auto w-8 h-8"><Spinner /></div>
            {:then v}
                {#if pp}
                    {@render boiler1('feature')}
                {:else}
                    {@render boiler3("feature", admin, lead_annotator)}
                    <Table
                        indexf={x => models.feature.index = x}
                        columns={[
                            [ 'Category', 'category', 'col-1' ],
                            [ 'Feature', 'name', 'col-1' ],
                            [ 'Value', 'value', 'col-1' ],
                            [ 'Label', 'label', 'col-2' ],
                            [ 'Description', 'description', 'col-8' ]
                        ]}
                        rows={v}
                        selectedf={(x, y) => (models.feature.id = x) && set_style(y)}
                    />
                {/if}
            {/await}
        {/if}
    </Tabs.Content>
    <Tabs.Content value="workflows">
        {#if tab == 'workflows'}
            <Help {help}>
                {#snippet content()}
                <div>
                    <p>workflows</p>
                </div>
                {/snippet}
            </Help>
            {#await tabp}
                <div class="mx-auto w-8 h-8"><Spinner /></div>
            {:then v}
                {#if pp}
                    {@render boiler1('workflow')}
                {:else}
                    {@render boiler3("workflow", admin, lead_annotator)}
                    <Table
                        indexf={x => models.workflow.index = x}
                        columns={[
                            [ 'Name', 'name', 'col-1' ],
                            [ 'Description', 'description', 'col-1' ],
                            [ 'Type', 'type', 'col-1' ]
                        ]}
                        rows={v}
                        selectedf={(x, y) => (models.workflow.id = x) && set_style(y)}
                    />
                {/if}
            {/await}
        {/if}
    </Tabs.Content>
    <Tabs.Content value="groups">
        {#if tab == 'groups'}
            <Help {help}>
                {#snippet content()}
                <div>
                    <p>groups</p>
                </div>
                {/snippet}
            </Help>
            {#await tabp}
                <div class="mx-auto w-8 h-8"><Spinner /></div>
            {:then v}
                {#if pp}
                    {@render boiler2('group')}
                    {#await pp}
                        <div class="mx-auto w-8 h-8"><Spinner /></div>
                    {:then v}
                        {@render boiler4(v)}
                        <Tabs.Root bind:value={models.group.tab} class="w-full">
                            <Tabs.List>
                                <Tabs.Trigger value="info">Group Info</Tabs.Trigger>
                                <Tabs.Trigger value="members">Group Members</Tabs.Trigger>
                            </Tabs.List>
                            <Tabs.Content value="info">
                                {@render boiler5('group', v)}
                             </Tabs.Content>
                            <Tabs.Content value="members">
                                {@render member_tab('group', v)}
                            </Tabs.Content>
                        </Tabs.Root>
                    {/await}
                {:else}
                    {@render boiler3("group", admin, lead_annotator)}
                    <Table
                        indexf={x => models.group.index = x}
                        columns={[
                            [ 'Name', 'name', 'col-1' ],
                            [ 'Description', 'description', 'col-1' ],
                            [ 'Type', 'type', 'col-1' ],
                        ]}
                        rows={v}
                        selectedf={(x, y) => (models.group.id = x) && set_style(y)}
                    />
                {/if}
            {/await}
        {/if}
    </Tabs.Content>
    <Tabs.Content value="invites">
        {#if tab == 'invites'}
            {#if portal_manager}
                {@render access_links()}
                <hr class="my-6">
            {/if}
            {#if project_manager}
                <div class="flex justify-around">
                    <div>
                        Invitations you made
                    </div>
                    <!-- <Modal {...h}>
                        {#snippet summary()}
                        <div>
                            Send Invitation
                        </div>
                        {/snippet}
                        {#snippet body()}
                        <div>
                            <form onsubmit={preventDefault(()=>null)}>
                                <div>
                                    <label>Email
                                        <input type=text bind:value={email}/>
                                    </label>
                                </div>
                                {#if admin || portal_manager}
                                    <div class="pt-2">
                                        Optionally, give the person a special role.
                                    </div>
                                {/if}
                                {#if admin}
                                    <div>
                                        <label>
                                        <input type=radio bind:group={role} value={"Project Manager"}>
                                        Project Manager
                                        </label> 
                                    </div>
                                {/if}
                                {#if portal_manager}
                                    <div>
                                        <label>
                                        <input type=radio bind:group={role} value={"Portal Manager"}>
                                        Portal Manager
                                        </label> 
                                    </div>
                                {/if}
                                {#if project_manager}
                                    <div class="pt-2">
                                        <div>If you want to automatically add the invitee to</div>
                                        <div>a project and/or task, select those here.</div>
                                    </div>
                                    {#await p}
                                    <div class="mx-auto w-8 h-8"><Spinner /></div>
                                    {:then v}
                                        <div>
                                            <label for=x>Project</label>
                                            <select id=x class="form-select" bind:value={project_id}>
                                                <option value={null}></option>
                                                {#each v.projects as project}
                                                    <option value={project.id}>
                                                        {project.name}
                                                    </option>
                                                {/each}
                                            </select>
                                        </div>
                                        <div>
                                            {#if project_id && project_id != v.personal}
                                                <label for=y>Task</label>
                                                <select id=y class="form-select" bind:value={task_id}>
                                                    <option value={null}></option>
                                                    {#each v.tasks_index[project_id] as task}
                                                        <option value={task.id}>
                                                            {task.name}
                                                        </option>
                                                    {/each}
                                                </select>
                                            {/if}
                                        </div>
                                    {/await}
                                {/if}
                            </form>
                        </div>
                        {/snippet} -->
                        <!-- <div slot=footer>
                            <button type="button" class="{btn}"   data-close-dialog on:click={create_invite}>Send</button>
                        </div> -->
                </div>
                {#await tabp}
                    <div class="mx-auto w-8 h-8"><Spinner /></div>
                {:then v}
                    <!-- <Table {columns} rows={v.users} use_filter={true} key_column=email height=500 /> -->
                    <Table
                        indexf={x => models.invite.index = x}
                        columns={[
                            [ 'Email', 'email', 'col-1' ],
                            [ 'Sent', 'sent', 'col-1' ],
                            [ 'Activated', 'activated', 'col-1' ]
                        ]}
                        rows={v ? v.users : []}
                        selectedf={(x, y) => (models.invite.id = x) && set_style(y)}
                    />
                {/await}
            {:else}
                Not allowed
            {/if}
        {/if}
    </Tabs.Content>
    <Tabs.Content value="permissions">
        {#if tab == 'permissions'}
    <div class="col-2 mx-auto">
        {#if admin}
            <div>You're an Admin.</div>
            <div><button class="{btn}" onclick={ () => { admin = false; portal_manager = true } }>Set yourself to Portal Manager</button></div>
        {:else if portal_manager}
            <div>You're a Portal Manager.</div>
            <div><button class="{btn}" onclick={ () => { portal_manager = false; project_manager = true; lead_annotator = true } }>Set yourself to Project Manager</button></div>
        {:else if project_manager}
            <div>You're a Project Manager.</div>
            <div><button class="{btn}" onclick={ () => { project_manager = false; lead_annotator = false } }>Set yourself to normal User</button></div>
        {:else}
            You don't have any global permissions.
        {/if}
    </div>
        {/if}
    </Tabs.Content>
    <Tabs.Content value="activations">
        {#if tab == 'activations'}
            {#if portal_manager}
                <div class="mx-auto max-w-2xl">
                    <div class="pb-2 flex justify-between items-center">
                        <div class="font-semibold">Unactivated users</div>
                        <button class={btn} onclick={() => activations_p = controller_actions.user.get_unactivated()}>Refresh</button>
                    </div>
                    {#await activations_p}
                        <div class="mx-auto w-8 h-8"><Spinner /></div>
                    {:then v}
                        {#if v?.users?.length}
                            <table class="w-full text-sm">
                                <thead>
                                    <tr class="border-b">
                                        <th class="text-left py-1">Username</th>
                                        <th class="text-left py-1">Email</th>
                                        <th class="text-right py-1"></th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {#each v.users as u (u.id)}
                                        <tr class="border-b">
                                            <td class="py-1">{u.name || '—'}</td>
                                            <td class="py-1">{u.email || '—'}</td>
                                            <td class="py-1 text-right">
                                                <button
                                                    class={btn}
                                                    onclick={async () => {
                                                        await controller_actions.user.activate(u.id);
                                                        activations_p = controller_actions.user.get_unactivated();
                                                    }}
                                                >Activate</button>
                                            </td>
                                        </tr>
                                    {/each}
                                </tbody>
                            </table>
                        {:else}
                            <div class="text-gray-500">No users awaiting activation.</div>
                        {/if}
                    {/await}
                </div>
            {:else}
                Not allowed
            {/if}
        {/if}
    </Tabs.Content>
    <Tabs.Content value="account">
        {#if tab == 'account'}
            <div class="mx-auto max-w-md">
                <div class="pb-2 font-semibold">Change password</div>
                <p class="pb-3 text-sm text-gray-600">
                    Signed in as {user}. Changing your password signs out your other
                    devices; this one stays signed in.
                </p>
                <form class="space-y-3" onsubmit={(e) => e.preventDefault()}>
                    <div>
                        <Label for="account_current_password">Current password</Label>
                        <Input type="password" id="account_current_password" autocomplete="current-password" bind:value={account_current_password} />
                    </div>
                    <div>
                        <Label for="account_new_password">New password</Label>
                        <Input type="password" id="account_new_password" autocomplete="new-password" bind:value={account_new_password} />
                        <div class="pt-1 text-xs text-gray-600">At least 8 characters.</div>
                    </div>
                    <div>
                        <Label for="account_confirm_password">Confirm new password</Label>
                        <Input type="password" id="account_confirm_password" autocomplete="new-password" bind:value={account_confirm_password} />
                    </div>
                    <Button variant="secondary" onclick={change_password} disabled={account_password_busy}>
                        {account_password_busy ? 'Changing…' : 'Change password'}
                    </Button>
                </form>
            </div>
        {/if}
    </Tabs.Content>
</Tabs.Root>

