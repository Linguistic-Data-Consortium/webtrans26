class TaskUsersController < ApplicationController

  # before_action :authenticate
  # source_tasks and copy_from_task do their own task_admin? check and render
  # the refusal as JSON, the way create and destroy do — the before_action
  # redirects, which a JSON caller can't read. task_admin2 sets @task for them
  # without redirecting, since task_admin? needs it set first.
  before_action :task_admin, :except => [ :get, :read_only, :create, :destroy, :update,
                                          :source_tasks, :copy_from_task ]
  before_action :task_admin2, :only => [ :source_tasks, :copy_from_task ]

  def show
    respond_to do |format|
      format.json do
        if task_admin? # uses @task
          tu = TaskUser.find params[:id]
          render json: history(tu)
        else
          render json: { error: 'permission denied' }
        end
      end
    end
  end

  # The tasks whose members can be copied into this one: the ones the signed-in
  # user administers, which is the same rule that lets them add a member by
  # hand. Carries the member count, so the choice is made knowing the size of
  # it rather than by name alone.
  #
  # GET /task_users/source_tasks?task_id=
  def source_tasks
    respond_to do |format|
      format.json do
        if !task_admin? # uses @task, set by the task_admin before_action
          render json: { error: 'permission denied' }
        else
          counts = TaskUser.group(:task_id).count
          tasks = administered_tasks.reject { |t| t.id == @task.id }
          render json: tasks.sort_by { |t| [ t.project&.name.to_s, t.name.to_s ] }.map { |t|
            {
              id: t.id, name: t.name, project_name: t.project&.name,
              member_count: counts[t.id] || 0
            }
          }
        end
      end
    end
  end

  # Add every member of another task to this one.
  #
  # Membership only: a user who administers the other task doesn't become an
  # admin here, and their state starts fresh, exactly as if each had been added
  # by hand. Someone already a member is left alone rather than being an error,
  # so the same copy can be run again after the source gains people.
  #
  # POST /task_users/copy_from_task { task_id:, from_task_id: }
  def copy_from_task
    respond_to do |format|
      format.json do
        source = Task.find_by id: params[:from_task_id]
        if !task_admin? # uses @task
          render json: { error: 'permission denied' }
        elsif source.nil?
          render json: { error: 'no such task' }
        elsif source.id == @task.id
          render json: { error: "#{@task.name} is already this task" }
        elsif !source.admin?(current_user) && !source.project&.admin?(current_user) &&
              !source.project&.owner?(current_user)
          render json: { error: "you don't administer #{source.name}" }
        else
          added = []
          skipped = []
          source.users.each do |user|
            if @task.member? user
              skipped << user.name
            else
              @task.users << user
              added << user.name
            end
          end
          render json: {
            ok: "#{added.size} added to #{@task.name} from #{source.name}" \
                "#{skipped.any? ? ", #{skipped.size} already there" : ''}",
            added: added, skipped: skipped
          }
        end
      end
    end
  end

  def create
    respond_to do |format|
      format.json do
        @task = Task.find params[:task_id]
        user = User.find_by id: params[:user_id]
        if !task_admin? # uses @task
          render json: { error: 'permission denied' }
        elsif user.nil?
          # No user_id in the request (or an unknown one): report it as a normal
          # JSON error rather than raising RecordNotFound and returning a 404
          # the caller can't read.
          render json: { error: 'no such user' }
        elsif @task.member? user
          render json: { error: "#{user.name} is already a member of #{@task.name}" }
        else
          @task.users << user
          render json: { ok: "#{user.name} has been added to #{@task.name}" }
        end
      end
    end
  end

  def destroy
    respond_to do |format|
      format.json do
        tu = TaskUser.find params[:id]
        @task = tu.task
        if task_admin? # uses @task
          @task.delete_user tu.user
          render json: { ok: "#{tu.user_name} has been removed from #{@task.name}" }
        else
          render json: { error: 'permission denied' }
        end
      end
    end
  end

  def update
    respond_to do |format|
      format.json do
        task_user = TaskUser.find params[:id]
        @task = task_user.task
        if task_admin? # uses @task
          response = []
          if params.has_key? :admin
            task_user.update(admin: params[:admin])
            response << "#{task_user.user_name} #{task_user.admin? ? "has been made" : "is no longer"} an admin of #{task_user.task_name}"
          end
          if params.has_key? :state
            # task_user.update(admin: params[:admin])
            task_user.goto_state params[:state]
            response << "#{task_user.user_name} set to state #{params[:state]}"
          end
          render json: { ok: response.join(',') }
        else
          render json: { error: 'permission denied' }
        end
      end
    end
  end

  #this action allows read only viewing of any kit for task admins and greater
  def read_only
    @workflow = Workflow.find params[:id]
    @kit = @workflow.read_only params[:kit_id]
    @task = @kit.task
    @project = @task.project
    @kit_type = @kit.kit_type
    kit_source_helper
    render 'workflows/work'
  rescue Workflow::TaskLockError => e
    redirect_to root_path, :flash => {:info => e.to_s}
  rescue Workflow::NoKitError => e
    redirect_to root_path, :flash => {:info => e.to_s}
  end

  # hook into specific workflows
  # 1. changes user's current task
  # 2. calls work method on workflow model
  # 3. renders view based on response from model

  def get
    task_user = TaskUser.find params[:id]
    @task = task_user.task
    @project = @task.project
    @workflow = @task.workflow
    if task_user.user != current_user
      if admin?
        raise Workflow::ReadOnlyError, "read only"
      else
        raise Workflow::WorkError, 'wrong user'
      end
    end
    raise Workflow::TaskInactiveError, 'inactive' if @task.status == 'inactive'
    original_state = task_user.state
    #set the current_task_user_id if its different than the one being annotated on, set the state to paused for the previous taskuser
    current_user.update_current_task_user task_user
    raise Workflow::WorkError, 'your work is on hold' if task_user.state == 'hold'

    if params[:kit_id]
      @workflow.return_to_kit task_user, params[:kit_id]
    end

    task_user.goto_state 'needs_kit' if task_user.state == nil

    @kit = @workflow.work task_user

    raise Workflow::KitLockError, 'wrong user' if @kit.user_id != current_user.id

    @kit_type = @kit.kit_type
    kit_source_helper
    # raise @kit.inspect
    respond_to do |format|
      format.html #{ render "kit_types/kit_type/#{@kit.kit_type.meta['template']}" }
      format.json { render json: @kit }
    end
    render 'workflows/work'
  rescue Workflow::KitLockError => e
    redirect_to user_path(current_user), :flash => {:info => "Kit #{@kit.uid} is locked. Please try again"}
  rescue Workflow::TaskInactiveError => e
    redirect_to root_path, flash: { error: "That task is inactive." }
  rescue Workflow::ReadOnlyError => e
    redirect_to "/workflows/#{@workflow.id}/read_only/#{task_user.kit_oid}"
  rescue Workflow::TaskLockError => e
    redirect_to user_path(task_user.user), :flash => {:info => "#{e.to_s}... Please try again"}
  rescue Workflow::WorkError => e
    redirect_to user_path(task_user.user), :flash => {:info => "#{e.to_s}... Please try again"}
  rescue Workflow::NoKitError => e
    task_user.goto_state 'needs_kit'
    redirect_to user_path(task_user.user), :flash => {:info => e.to_s}
  rescue Workflow::HoldError => e
    task_user.goto_state 'hold'
    redirect_to user_path(task_user.user), :flash => {:info => e.to_s}
  end
  
  def kit_source_helper
    if @kit.source[:uid]
      @source = Source.where(uid: @kit.source[:uid]).first
    elsif @kit.source[:id]
      @source = Source.where(id: @kit.source[:id]).first
    end
    if @source and @source.file
      @source.update(uid: @source.file.key) if @source.uid.nil?
      @kit.source[:uid] = @source.uid if @kit.source[:uid].nil?
      @manifest ||= {}
      @manifest[:urls] = { @source.uid => url_for(@source.file) }
    end
    @workflow.kit_source_helper @kit, @source, @manifest
    if @manifest and @manifest[:urls]
      @manifest[:urls].keys.each do |k|
        v = @manifest[:urls][k]
        @manifest[:urls][k] = url_for v.file if v.class == Source
      end
    end
    # No Source row: the kit names its audio directly, and the manifest hands
    # that name to the client to resolve — an s3:// url gets signed there, an
    # http one and a path are used as they stand.
    #
    # This used to build "s3" + a bucket read off the task's data set. The
    # data_sets table is gone, so that produced the bare string "s3" for every
    # kit whose source_uid wasn't already an s3:// url, and the tool alerted
    # "missing bucket" with nothing to go on.
    if @kit.source_uid and @source.nil?
      @manifest = { urls: { @kit.source_uid => @kit.source_uid } }
    end
  end
  
  def manifest_helper
    hash = @kit.task.game_variant ? @kit.task.game_variant.meta : {}
    dsid = hash['data_set']
    # dsid = 3
    if dsid
      ds = DataSet.find(dsid)
      if ds.name =~ /aws/
        x = ds.name.sub('aws','json')
        "//ldc-developers.s3.amazonaws.com/#{x}"
      else
        ds.spec.url
      end
    else
      nil
    end
  end

  private

  # Every task the signed-in user administers: the ones they're a task admin
  # of, plus every task in a project they admin or own.
  def administered_tasks
    return [] unless signed_in?
    own = Task.joins(:task_users).where(task_users: { user_id: current_user.id, admin: true })
    projects = Project.all.select { |p| p.admin?(current_user) || p.owner?(current_user) }
    (own.to_a + Task.where(project_id: projects.map(&:id)).to_a).uniq
  end

  def task_admin
    #need to define @task so task_admin? in sessions_helper can work
    #uses the task :id for edit/update and the taskuser :task_id for create_tu/remove_tu
    @task = params[:task_id].nil? ? TaskUser.find(params[:id]).task : Task.find(params[:task_id])
    redirect_to(root_path) unless task_admin?
  end

  def task_admin2
    #need to define @task so task_admin? in sessions_helper can work
    #uses the task :id for edit/update and the taskuser :task_id for create_tu/remove_tu
    @task = params[:task_id].nil? ? TaskUser.find(params[:id]).task : Task.find(params[:task_id])
  end

  # Was: build the tree's node graph from the nodes table and "elaborate" it
  # (attach node classes, types, styles) before serving the kit. There is no
  # such table — the graph is replayed from the annotation log by whoever reads
  # it — so the guard `@kit.tree.tree` has been nil, and this a no-op, since the
  # readers switched over. Kept as an empty hook because both controllers call
  # it on the work-page path and the rescue used to reset the task_user's state.
  def elaborate_root_helper(task_user=nil, original_state='has_kit')
  end

  def history(tu)
    return { ok: [] } if tu.versions.length < 2
    {
      ok: (tu.versions.all[1..-1].map { |x|
        y = YAML.load(x.object, permitted_classes: [Time, ActiveSupport::TimeWithZone, ActiveSupport::TimeZone], aliases: true)
        [
          y['updated_at'],
          (y['state'] || '').ljust(10, ' '),
          (y['kit_oid'] || (' '*24)),
          x.whodunnit
        ].join(' ')
      } + [[tu.updated_at, tu.state, tu.kit_oid].join(' ')] ).join("\n")
    }
  end

end
