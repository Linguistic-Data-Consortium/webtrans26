Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"

  get 'password_resets/new'

  get 'password_resets/edit'

  get '/awaiting_activation', to: 'pages#awaiting_activation', as: :awaiting_activation

  get '/documentation',       to: 'documentation#index', as: :documentation_index
  get '/documentation/:slug', to: 'documentation#show',  as: :documentation_show, constraints: { slug: /[A-Za-z0-9_\-]+/ }

  get :echo, to: 'pages#echo'
  get '/azure_audio_url', to: 'pages#azure_audio_url'
  post '/azure_transcribe', to: 'pages#azure_transcribe'

  # New async transcription endpoints
  post '/azure_transcribe_async', to: 'azure_transcription#create'
  get '/azure_transcribe/status/:job_id', to: 'azure_transcription#status'
  root 'pages#home'
  get '/signup', to: 'users#new'
  post '/signup', to: 'users#create'
    # get '/login', to: 'sessions#new'
  # post '/login', to: 'sessions#create'
  # get '/confirmation', to: 'sessions#confirmation'
  # post '/confirm', to: 'sessions#confirm'
  # delete '/logout', to: 'sessions#destroy'
  # get '/logout2', to: 'sessions#destroy2'

  resources :users do
    collection do
      get :unactivated
    end
    member do
      patch :activate
    end
  end
  # resources :sessions, only: [:create]
  resources :account_activations, only: [:edit]
  resources :password_resets,     only: [:new, :create, :edit, :update]

  resources :kit_batches, only: [ :index, :show, :new, :create ]

  resources :annotations

  post 'projects/respond_with_project', :to => 'projects#respond_with_project'
  get 'projects/:id/research_team', :to => 'projects#research_team', :as => 'projects_research_team'
  get 'projects/:id/users_not_in_project', to: 'projects#users_not_in_project', :as => 'users_not_in_project'
  get 'groups/:id/users_not_in', to: 'groups#users_not_in', :as => 'users_not_in'
  get 'projects/:id/project_users', to: 'projects#project_users', :as => 'project_project_users'
  get 'tasks/:id/task_users', to: 'tasks#task_users', :as => 'task_task_users'
  get 'tasks/:id/users_not_in_task', to: 'tasks#users_not_in_task', :as => 'users_not_in_task'
  post 'tasks/respond_with_task', :to => 'tasks#respond_with_task'
  get 'tasks/recreate', :to => 'tasks#recreate'

  post 'add_user_to_project_and_task/:project_id/:task_id', :to => 'projects#add_user_to_project_and_task', :as => 'add_user_to_project_and_task'


  resources :node_classes
  resources :nodes
  resources :trees
  resources :node_values
  resources :nde_values
  resources :constants
  resources :kit_batches, only: [ :index, :show, :new, :create ]
  resources :tasks, :except => [:new, :create]#if the task already exists, we can infer the project, for new/create it must be specified
  resources :projects, except: [ :new, :edit ] do
    resources :tasks, except: [ :new, :edit, :index ] do
      member do
        # A drawing of everything this task's kits have annotated: the graph
        # tables, snapshotted from the log and laid out on a timeline.
        get :graph
        get :kit_creator
        post :file_upload
        post :kit_generation_preview
        post :generate_kits
        post :process_kits
        post :process_kits_preview
        get :reassign_kit
        get :kit_processor
        patch :reassign_many_kits
      end
    end
  end
  # Add every member of another task to this one, and the tasks that offers.
  get "/task_users/source_tasks", to: 'task_users#source_tasks'
  post "/task_users/copy_from_task", to: 'task_users#copy_from_task'
  resources :task_users, :only => [ :show, :create, :update, :destroy ]
  resources :project_users
  post "/project_users/invite", to: "project_users#invite", as: "project_users_invite"
  post "/users/invite", to: "users#invite", as: "users_invite"
  # The list of documents a task gives to every one of its users, which the
  # SameListForEveryone workflow reads. Entered on the Task tab.
  get "/task_docids", to: 'task_docids#index'
  post "/task_docids", to: 'task_docids#replace'
  get "/kits/all", to: 'kits#all'
  # Rebuilds the kit's annotation-graph projection (graph_nodes / graph_arcs)
  # and returns it — the waveform's Graph button.
  post "/kits/graph", to: 'kits#graph'
  # The same payload the tool loads with, rebuilt from the graph tables — a
  # cross-check, so it reads what the last snapshot wrote rather than rebuilding.
  get "/kits/graph_payload", to: 'kits#graph_payload'
  # The imported graph covering this kit's audio, if one was imported for it —
  # what the transcribe_text_only mode transcribes against.
  post "/kits/imported", to: 'kits#imported'
  get "/kits_new", to: 'kits#kits_new'
  post "/create_kits_from_kits_tab", to: 'kits#create_kits_from_kits_tab'
  resource :kits do
    member do
      get ':id/unlock_tree', action: :unlock_tree, as: :unlock_tree
      get :get
      patch :change_kit_state
      post :get_time_spent
      get :get_time_spent
      post :change_time_spent
      get :change_time_spent
      post :get_message_from_journal
      get ':id/show', :action => :show, :as => :show
      get ':id/check', :action => :check, :as => :check
      patch ':id/update', :action => :update, :as => :update
      get 'task/:id', :action => :task, :as => :task
      post :set_kits_done
      get 'fix_floating_kits/:task/:new_state', :action => :fix_floating_kits, :as => :fix_floating_kits
      get :management
      get :trouble
      get ':id/undo', action: :undo
    end
  end

  resources :workflows do
    member do
      get 'read_only/:kit_id', to: 'task_users#read_only'
      # get 'quality_control/:kit_id/:task_id', :action => 'quality_control'
      get 'work/:workflow_id', to: 'task_users#get'
      # get 'work/:task_user_id/:value', :action => 'work'
      get 'set/:task_user_id/:value', :action => 'set'
      # get 'set_lock/:state', :action => 'set_lock'
    end
  end
  resources :kit_types do
    get 'autocomplete', :on => :collection
  end

  resource :sources do
    member do
      get :text
      get :audio
      get :audio_full
      post :get_text
      post :get_ner
      post :uget
      get :ugett
      post :uget_public
      get :get_upload
      get :get_download
      get :new
    end
  end

  resources :groups, except: [ :new, :edit ]
  resources :group_users, :only => [:create, :destroy]


  resources :invites
  # Signed-in password change (the dashboard's Account tab).
  patch '/account/password', to: 'account_passwords#update', as: :account_password
  # One-time sign-in links: index/create are the admin side (JSON), and
  # /access/:id/:token is the link a new user clicks.
  resources :access_links, only: [ :index, :create ]
  get '/access/:id/:token', to: 'access_links#show', as: :access_link,
      constraints: { token: /[A-Za-z0-9_\-]+/ }
  resources :features, except: [ :new, :edit ]

  get '/bucket', to: 'data_sets#bucket'
  post '/token', to: 'cognito_token#get_credentials'
    
  resources :actions, only: [ :create ]
  resources :xamespaces, except: [ :new, :edit ]

  resources :jwts, only: [ :create, :index ]

end
