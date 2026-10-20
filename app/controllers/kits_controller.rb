class KitsController < ApplicationController

  require 'date'

  # before_action :authenticate
  # before_action :task_admin, :only => [ :get_message_from_journal, :fix_floating_kits, :create_kits_from_kits_tab ]
  skip_before_action :verify_authenticity_token, only: [ :get_time_spent, :create_kits_from_kits_tab ]
  # before_action :authenticate, except: [ :create_kits_from_kits_tab ]
  # allow_unauthenticated_access only: %i[ create_kits_from_kits_tab ]
  before_action :task_admin, :only => [ :fix_floating_kits ]
  before_action :admin_user, :only => [ :set_kits_done ]
  before_action :lead_annotator_user, only: [ :show, :change_kit_state, :management ]

  def task
    respond_to do |format|
      format.html do
        flash[:error] = "See Projects / Tasks / Kits below"
        redirect_to root_path
      end
      format.json do
        @task = Task.find params[:id]
        render json: (
          if task_admin?
            # @state = params[:state]
            # @title = "Kits for #{@task.name}"
            @task_user = TaskUser.where( task_id: @task, user_id: current_user.id ).first
            get_kits
                # render json: {"aaData" => @kits}
          else
            { error: 'Permission denied.' }
          end
        )
      end
    end
  end

  def undo
    respond_to do |format|
      format.json do
        render json: Annotation.includes(:node_value).where(kit_id: params[:id]).order(:id).map { |x|
          {
            id: x.id,
            transaction_id: x.transaction_id,
            parent_id: x.parent_id,
            user_id: x.user_id,
            task_id: x.task_id,
            tree_id: x.tree_id,
            iid: x.iid,
            message: x.message,
            value: x.node_value.tvalue
          }
        }
      end
    end
  end

  def set_kits_done
    @task = Task.find params[:task][:id]
    Kit.where(:task_id => @task.id, :state => 'unassigned').each do |tk|
      tk.update(:state => 'done')
    end

    flash[:success] = "Marked all the kits for #{@task.name} as done"
    redirect_to project_task_path(@task.project, @task)
  end

  #this action fixes all of the floating kits for a particular task by moving them to another state (unassigned or broken typically)
  def fix_floating_kits
    @task = Task.find(params[:task])
    new_state = params[:new_state]
    Kit.where(:task_id => @task.id, :state => 'assigned').each do |kit|
      taskuser = TaskUser.kit_taskuser(kit.id).first
      if !taskuser || !User.exists?(taskuser.user_id)
        if new_state == 'broken'
          kit.state = new_state
          kit.meta['broken_comment'] = "broken by #{current_user.name} through floating kit fix process"
        else
          kit.state = new_state
        end
        kit.save!
      end
    end
    flash[:success] = "Successfully moved the floating kits for #{@task.name} to state => #{new_state}"
    redirect_back fallback_location: root_path
  end

  def change_kit_state
    @newState = kit_params[:state]
    @kit = Kit.find_by_uid kit_params[:uid]
    originalState = @kit.state
    if @newState == 'broken'
      @kit.state = 'broken'
      @kit.meta['broken_comment'] = "marked as broken by #{current_user.name}"
    else
      @kit.state = @newState
      flash[:success] = "Kit uid #{@kit.uid} state updated to #{@newState}"
    end
    @kit.save!
    #remove the kit from the taskuser if the original state was unassigned
    if originalState == 'assigned'
      if TaskUser.kit_taskuser(@kit.uid).count > 0
        taskuser = TaskUser.kit_taskuser(@kit.uid).first
        taskuser.kit_oid = nil
        taskuser.state = 'needs_kit'
        taskuser.save
      end
    end
    redirect_back fallback_location: root_path
  end

  def get_time_spent
    @kit = Kit.find_by_uid params[:uid]
    puts @kit.time_spent if @kit
    respond_to do |format|
      format.json do
        render :json => { :type => 'success', :message => "#{@kit.time_spent}"}
      end
      format.html do
        redirect_to root_path
      end
    end
  end

  def trouble
    @kit = Kit.find_by_uid params[:uid]
    UserMailer.trouble(@kit, current_user).deliver_now
    respond_to do |format|
      format.json do
        render :json => { :type => 'success', :message => "#{@kit.uid}"}
      end
    end
  end

  def change_time_spent
    @kit = Kit.find_by_uid params[:uid]
    if @kit
      @kit.time_spent = params[:time_spent].to_i
      @kit.save
    end
    respond_to do |format|
      format.json do
        render :json => { :type => 'success', :message => "set time_spent of #{@kit.uid} to #{@kit.time_spent}"}
      end
      format.html do
        redirect_to root_path
      end
    end
  end

  def management
    @title = "Kit Management"
    @tasks = Task.all
    @states = UserDefinedObject.where(:name => 'kit_states').first["object"].split
  end

  def get
    @kit = Kit.find_by_uid(params[:uid])
    add_meta_values_to_kit
    if params[:task_user_id] == 'readonly'
      elaborate_root_helper unless params[:mode] == 'two'
    else
      task_user = TaskUser.find params[:task_user_id]
      raise 'wrong user' unless task_user.user == current_user or params[:editor] == 'true'
      elaborate_root_helper task_user, task_user.state unless params[:mode] == 'two'
    end
    respond_to do |format|
      format.json do
        @kit.view = 'open' if @kit.view.nil? or @kit.view == ''
        @kit.meta['constraints'] = {}
        @kit.kit_type.constraints.each do |k, v|
          @kit.meta['constraints'][k] = (v == '' ? true : v)
        end
        # @kit.meta['constraints']['rtl'] = true if LDCI::CONFIG[:rtl] and @kit.source[:uid] and LDCI::CONFIG[:rtl].include?(@kit.source[:uid].split('_').first) and @kit.source[:uid] !~ /\.eng/
        # The tree is built through the graph shape — anchors, spans, labels —
        # in memory from the annotation log. Nothing is written, so there's no
        # snapshot to be stale.
        #
        # ?payload= on the work page picks another route to the same tree:
        #   log           the annotation log directly, as the tool loaded for years
        #   graph_stored  what a snapshot wrote, for checking the stored rows
        hash = case params[:payload]
               when 'log'          then @kit.to_hash(false, 'deep', params[:editor])
               when 'graph_stored' then @kit.graph_payload
               else                     @kit.graph_memory_payload
               end
        # unprotect_annotations hash['tree'] if @kit.task_id.in? protected_task_ids
        hash['other_task_user_id'] = get_other_task_user_id
        hash['task_meta'] = @kit.task.meta 
        # if params[:iid]
        #   if params[:iid] == 0
        #     hash['tree'] = @kit.tree.tree.to_client_hash
        #   else
        #     node = Nd.where(tree_id: @kit.tree_id, iid: params[:iid]).first
        #     node.initialize_from_sql nil, @kit.tree, @kit.tree.class_def.inverted_grammar
        #     hash['tree'] = node.to_client_hash
        #   end
        # end
        render :json => hash
      end
    end
  end

  def get_other_task_user_id
    workflow = @kit.task.workflow
    if false #workflow.type == "Workflows::CaceTopicDevDataScouting"
      TaskUser.where( task_id: (Task.where(workflow_id: workflow.id).pluck(:id) - [ @kit.task_id ]).first, user_id: @kit.user_id ).pluck(:id).first
    else
      nil
    end
  end

  def unlock_tree
    @kit = Kit.find_by_id params[:id]
    response = { done: 'failure' }
    if @kit.tree.locked == current_user.id || current_user.admin?
      @kit.tree.update(locked: nil)
      response[:done] = 'success'
    end
    respond_to do |format|
      format.html
      format.json { render json: response }
    end
  end

  def show
    id = params[:id]
    if id.length == 24
      @kit = Kit.find_by_uid params[:id]
    else
      @kit = Kit.find_by_id params[:id]
    end
    @task_user = TaskUser.where( task_id: @kit.task_id, user_id: current_user.id).first
    @kit_types = KitType.all
    # redirect_to "/workflows/workflows/#{task.workflow_id}/read_only/#{kit.uid}", :only_path => true
    if params[:open]
      source = Source.where(id: params[:open].to_i).first
      @kit.source_uid = source.uid
      @kit.source[:uid] = source.uid
      @kit.source[:id] = source.uid
      @kit.source[:filename] = params[:filename]
      @kit.save!
    end
    if params[:s3]
      uid = params[:s3]
      @kit.source_uid = uid
      @kit.source[:uid] = uid
      @kit.source[:id] = uid
      @kit.source[:filename] = params[:filename]
      @kit.save!
    end
    if params[:goto]
      @kit.destroy
      Kit.find(params[:goto]).update(state: :assigned)
      @task_user.update( state: 'needs_kit' )
    end
    respond_to do |format|
      format.html
      format.json { render json: @kit }
    end
  end

  def check
    id = params[:id]
    @kit = Kit.find_by_id params[:id]
    if params[:check]
      tree_id = @kit.tree_id
      kit_id = @kit.id
      @kit = {}
      @kit[:ns] = Kit.connection.exec_query("select * from Ns where tree_id = ?", "SQL", [[nil, tree_id]]).to_a
      @kit[:segments] = Kit.connection.exec_query("select * from Segments where tree_id = ?", "SQL", [[nil, tree_id]]).to_a
      @kit[:sections] = Kit.connection.exec_query("select * from Sections where tree_id = ?", "SQL", [[nil, tree_id]]).to_a
      @kit[:segmentos] = Kit.connection.exec_query("select * from Segmentos where tree_id = ?", "SQL", [[nil, tree_id]]).to_a
      @kit[:sectionos] = Kit.connection.exec_query("select * from Sectionos where tree_id = ?", "SQL", [[nil, tree_id]]).to_a
      KitCheck.create(kit_id: kit_id, check: params[:check])
    end
    respond_to do |format|
      format.html
      format.json { render json: @kit }
    end
  end

  def kits_new
    if params[:open] or params[:s3]
      user_id = current_user.id
      task_id = params[:task_id].to_i
      kit = Kit.new
      kit.user_id = user_id
      kit.task_id = task_id 
      kit.kit_type_id = Task.find(task_id).kit_type_id
      kit.state = 'unassigned'
      # task_user = TaskUser.where( task_id: task_id, user_id: current_user.id).first
      # @kit_types = KitType.all
      # # redirect_to "/workflows/workflows/#{task.workflow_id}/read_only/#{kit.uid}", :only_path => true
    end
    if params[:open]
      source = Source.where(id: params[:open].to_i).first
      kit.source_uid = source.uid
      kit.source[:uid] = source.uid
      kit.source[:id] = source.uid
      kit.source[:filename] = params[:filename]
      kit.save!
    end
    if params[:s3]
      uid = params[:s3]
      kit.source_uid = uid
      kit.source[:uid] = uid
      kit.source[:id] = uid
      kit.source[:filename] = params[:filename]
      kit.save!
    end
    if params[:goto]
      kit = Kit.find(params[:goto])
      kit.update(state: :unassigned, user_id: current_user.id)
      # @task_user.update( state: 'needs_kit' )
    end
    respond_to do |format|
      format.html
      format.json do
        render json: {
          id: kit.id,
          uid: kit.uid,
          user_id: kit.user_id
        }
      end
    end
  end

  def edit
  end

  def update
    respond_to do |format|
      format.json do
        @kit = Kit.find_by_id params[:id]
        @task = @kit.task
        render json: (
          if not task_admin?
            { error: "Only a task admin can edit the kit." }
          elsif @kit.update kit_params
            @kit
          else
            { error: @kit.errors.full_messages }
          end
        )
      end
    end
  end

  # One kit per entry: { docid: }, optionally with { user_id: } to give the kit
  # to someone — the Kits tab's text dialog parses "foo.wav user_id=alice" into
  # that shape.
  #
  # user_id is whatever was typed: an id, a name, or an email address. It's
  # resolved here, and an entry naming a user who doesn't exist makes no kit at
  # all rather than one owned by nobody. Which entries failed comes back with
  # the count, since the dialog has closed by then and the answer has to be
  # readable somewhere.
  def create_kits_from_kits_tab
    respond_to do |format|
      format.json do
        @task ||= Task.find params[:task_id]
        # The dialog is only offered to a task's admins; before this, that was
        # the only thing stopping anyone from making kits here — and now that
        # an entry can name whose kit it is, that matters more.
        unless task_admin? # uses @task
          render json: { created: 0, kit_ids: [], errors: [ "You must be a task admin to do that." ] }
          next
        end
        made = []
        errors = []
        params[:kits].each do |x|
          uid = x['docid']
          wanted = x['user_id'].presence
          user = wanted && find_user_for_kit(wanted)
          if wanted && user.nil?
            errors << "#{uid}: no user '#{wanted}'"
            next
          end
          kit = @task.create_default_kit
          kit.source = { uid: uid, id: uid, filename: uid }
          kit.source_uid = uid
          kit.user_id = user&.id
          kit.save!
          made << kit.id
        end
        render json: { created: made.size, kit_ids: made, errors: errors }
      end
    end
  end

  # An id, a name, or an email address — whichever the person typing had to
  # hand. Names and addresses are unique case-insensitively.
  def find_user_for_kit(value)
    value = value.to_s.strip
    return User.find_by(id: value) if value.match?(/\A\d+\z/)
    User.where("lower(name) = ?", value.downcase).first ||
      User.where("lower(email_address) = ?", value.downcase).first
  end

  # Writes this kit's rows in graph_nodes / graph_arcs from its annotations and
  # returns them. A second projection of the same log, alongside the
  # segments/sections one Kit#snapshot writes.
  def graph
    respond_to do |format|
      format.json do
        kit = Kit.find_by_uid(params[:uid])
        if kit.nil?
          render json: { error: "no such kit" }
        elsif kit.tree_id.nil?
          render json: { error: "that kit has never been opened, so it has no annotations" }
        elsif kit.user_id != current_user.id && !lead_annotator?
          render json: { error: "permission denied" }
        else
          render json: kit.graph_snapshot
        end
      end
    end
  end

  # The imported graph this kit transcribes against, matched to its audio by
  # stem — no directory, no extension, no channel suffix. Which tier comes from
  # the kit type's transcribe_text_only constraint: set as a plain flag it
  # reads 'reference', set to a value it reads that tier.
  #
  # Returns the spans flattened, since that's what the tool needs: a caption
  # over each segment, and the times to create segments at when the kit is
  # still empty.
  def imported
    respond_to do |format|
      format.json do
        kit = Kit.find_by_uid(params[:uid])
        if kit.nil?
          render json: { error: "no such kit" }
          next
        end

        tier = kit.kit_type&.constraints&.dig("transcribe_text_only")
        tier = ImportedGraph::DEFAULT_TIER if tier.blank? || tier == "transcribe_text_only"
        graph = ImportedGraph.for_source(kit.source_uid, tier: tier)
        if graph.nil?
          # Say which tiers this audio does have. The common way to get here is
          # a kit type asking for the default tier when the import named it
          # something else, and that's only obvious if the message says so.
          available = ImportedGraph.for_stem(kit.source_uid).pluck(:name).sort
          error = "no '#{tier}' graph imported for #{kit.source_uid}"
          error += available.any? ? " — that audio has: #{available.join(', ')}" : " — nothing imported for that audio"
          render json: { error: error, tier: tier, available: available }
        else
          render json: {
            docid: graph.docid, tier: graph.name, source: graph.source,
            rows: graph.transcript_rows.map { |r| r.slice(:beg, :end, :text) }
          }
        end
      end
    end
  end

  # The client payload built from graph_nodes / graph_arcs / graph_labels
  # instead of from the annotation log — what #get serves, for the same kit,
  # by a different route. Reads the tables as they stand, so it's only
  # meaningful once #graph has run for this kit and the kit hasn't changed
  # since.
  def graph_payload
    respond_to do |format|
      format.json do
        kit = Kit.find_by_uid(params[:uid])
        if kit.nil?
          render json: { error: "no such kit" }
        elsif kit.tree_id.nil?
          render json: { error: "that kit has never been opened, so it has no annotations" }
        elsif kit.user_id != current_user.id && !lead_annotator?
          render json: { error: "permission denied" }
        elsif GraphNode.by_tree(kit.tree_id).none? && GraphArc.by_tree(kit.tree_id).none?
          render json: { error: "no graph for that kit yet — build it first" }
        else
          render json: kit.graph_payload
        end
      end
    end
  end

  def all
    respond_to do |format|
      format.json do
        o = []
        task_id = params[:task_id].to_i
        Kit.where(task_id: task_id).each do |x|
          x.snapshot
        end
        last_uid = nil
        trs = nil
        Kit.connection.execute(
          "
          SELECT
            kits.uid,
            kits.source_uid as docid,
            kits.done_comment,
            segments.iid,
            segments.btime as beg,
            segments.etime as e, -- not sure if end is allowed here
            segments.text,
            segments.speaker,
            sections.name as section
          FROM kits
          LEFT JOIN segments ON segments.tree_id = kits.tree_id
          LEFT JOIN sections ON sections.tree_id = kits.tree_id
            AND segments.btime >= sections.btime AND segments.etime <= sections.etime
          WHERE kits.task_id = #{task_id} and kits.state = 'done'
          ORDER BY uid, beg, segments.iid
          "
        ).each do |x|
          if x['uid'] != last_uid
            trs = {kit_uid: x['uid'], segments: []}
            o << trs
            last_uid = x['uid']
          end
          x['end'] = x['e']
          o[-1][:segments] << x
        end
        render json: o
      end
    end
  end
  private

  def kit_params
    params.require(:kit).permit(:meta, :user_id, :task_id, :kit_type_id, :uid, :state, :source, :broken_comment, :tree_id, :kit_batch_id, :not_user_id, :time_spent)
  end

  # Was: build the tree's node graph from the nodes table and "elaborate" it
  # (attach node classes, types, styles) before serving the kit. There is no
  # such table — the graph is replayed from the annotation log by whoever reads
  # it — so the guard `@kit.tree.tree` has been nil, and this a no-op, since the
  # readers switched over. Kept as an empty hook because both controllers call
  # it on the work-page path and the rescue used to reset the task_user's state.
  def elaborate_root_helper(task_user=nil, original_state='has_kit')
  end

  def add_meta_values_to_kit
    return
    @kit.kit_type.meta.each do |k, v|
      raise unless k =~ /^\w+$/
      case k
      when 'root1'
        next
      when 'source'
        if v.length > 0        # v = '{}' if v == ''
          @kit.source = JSON.parse v
        else
          @kit.source = {} unless @kit.source
        end
        next
      end
      #eval "@kit.#{k} = v" if @kit.respond_to? k
      @kit.send("#{ k }=", v) if @kit.respond_to? k
    end
  end

  def task_admin
    @task = params[:id] ? Task.find(params[:id]) : (params[:task] ? Task.find(params[:task]) : Task.find(params[:task_id]))
    redirect_to(root_path) unless task_admin?
  end

  def get_kits
    # Kit.includes(:user).where(:task_id => @task.id, :state => @state).map do |kit|
    Kit.includes(:user, :kit_states, :kit_values).where(:task_id => @task.id).map do |kit|
      {
        id: kit.id,
        uid: kit.uid,
        state: kit.state,
        link: get_link_to_kit(kit),
        source_uid: get_kit_source(kit),
        continue: get_link_to_continue(kit),
        user: get_kit_username(kit),
        # get_reassign_link(kit),
        broken_comment: get_broken_comment(kit),
        updated_at: get_kit_updated(kit),
        dual_id: kit.dual_id,
        # duration: kit.kit_values.where(key: :duration).first&.value.to_f
        duration: kit.kit_values.select { |x| x.key == 'duration' }.first&.value.to_f
      }
    end
  end

  def get_link_to_kit(kit)
    "/workflows/#{@task.workflow_id}/read_only/#{kit.uid}"
  end

  def get_link_to_continue(kit)
    @state == 'assigned' && @task_user ? view_context.link_to('continue', "/workflows/#{@task.workflow_id}/work/#{@task_user.id}?kit_id=#{kit.id}") : 'n/a'
  end

  def get_kit_source(kit)
    (kit.source[:uid] || kit.source['uid']) || "none"
  end

  def get_kit_username(kit)
    kit.user ? kit.user.name : 'none'
  end

  def get_reassign_link(kit)
    "<div class=\"reassign_kit modal-trigger\" kit_id=\"#{kit.uid}\">reassign</div>"
  end

  def get_broken_comment(kit)
    kit.state == 'broken' ? kit.broken_comment : "n/a"
  end

  def get_kit_updated(kit)
    kit.updated_at.getlocal
  end

end
