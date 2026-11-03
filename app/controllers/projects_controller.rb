class ProjectsController < ApplicationController

  # before_action :authenticate
  before_action :admin_user, :only => :destroy
  # Creating a project makes you its owner and admin, and so admin of any task
  # you then add to it, which is what most per-task checks ask about.
  before_action :project_manager_json, :only => [ :create ]
  before_action :project_owner_user, :only => [ :update ]
  # before_action :project_admin, :only => [ :edit, :users_not_in_project ]
  after_action { flash.discard if request.xhr? }

  include UsersHelper
  # include MarkdownAdapter

  # Candidates for the add-member dialog: everyone not yet in the project, so
  # only for someone who can add them.
  def users_not_in_project
    @project = Project.find(params[:id])
    return deny_json unless project_admin?
    userids = @project.users.map{ |x| x.id }
    @users = User.all.order(:name).where("name LIKE ?", "%#{params[:term]}%").where.not(id: userids).map{ |x| {name: x.name, id: x.id, project_id: @project.id.to_s } }
    respond_to do |format|
      format.json { render json: @users }
    end
  end

  def index
    respond_to do |format|
      format.json do
        if lead_annotator?
          projects = Project.sorted.all
        else
          projects = current_user.sorted_projects
        end
        task_counts = Task.group(:project_id).count
        render json: (
          projects.map do |project|
            {
              id: project.id,
              name: project.name,
              task_count: task_counts[project.id]
            }
          end
        )
      end
    end
  end


  def show
    respond_to do |format|
      format.json do
        project = Project.includes( :tasks ).find(params[:id])
        render json: (
          if project.member?(current_user) || lead_annotator?
            title = project.name
            #for the new task partial
            @workflows = Workflow.all.order(:id) #.all_newest_first
            @kit_types = KitType.all_newest_first
            available_kit_counts = Kit.where( state: 'unassigned', task_id: project.tasks.pluck(:id) ).group(:task_id).count
            # portal_manager? already covers admin? (SessionsHelper), and the
            # backend ProjectUsersController#create authorizes Portal Managers
            # via project_admin? — so the frontend gate must match, otherwise
            # the "Add Member" button hides for Portal Managers who could
            # otherwise legitimately add users to the project.
            project_owner_bool = project.owner?(current_user) || portal_manager?
            project_admin_bool = project.admin?(current_user) || project_owner_bool
            project_users = project.project_users.includes(:user).map do |x|
              {
                id: x.id,
                user_id: x.user_id,
                name: x.user_name,
                owner: x.owner,
                admin: x.admin
              }
            end
            # @current_user_project_user = project_users.select { |x| x.user_id == current_user.id }.first
            # @current_user_task_ids = TaskUser.where( task_id: project.tasks.map(&:id), user_id: current_user.id ).pluck(:task_id)
            {
              id: project.id,
              name: title,
              project_owner_bool: project_owner_bool,
              project_admin_bool: project_admin_bool,
              tasks: project.tasks.includes(:workflow).map { |x|
                {
                  id: x.id,
                  name: x.name,
                  # Unassigned kits for most workflows; one that makes kits when
                  # the user arrives counts what it still owes instead, since
                  # for those the kits don't exist yet.
                  available_kit_count: x.workflow&.outstanding_kit_count(x, available_kit_counts[x.id] || 0) ||
                                       (available_kit_counts[x.id] || 0),
                  source_uid: x.meta['docid']
                }
              },
              members: project_users
            }
          else
            { error: 'Permission denied.' }
          end
        )
      end
    end
  end

  def create
    respond_to do |format|
      format.json do
        render json: (
          project = Project.new project_params
          if project.save
            ProjectUser.create(project_id: project.id, user_id: current_user.id, owner: true, admin: true)
            project
          else
            { error: project.errors.full_messages }
          end
        )
      end
    end
  end

  def update
    respond_to do |format|
      format.json do
        @project = Project.find(params[:id])
        render json: (
          if not project_owner? # uses @project
            { error: "Only the project owner or an administrator can edit the project." }
          elsif @project.update project_params
            @project
          else
            { error: @project.errors.full_messages }
          end
        )
      end
    end
  end

  def destroy
    respond_to do |format|
      format.json do
        project = Project.find(params[:id])
        project.destroy
        render json: { deleted: "Project: #{project.name} has been deleted." }
      end
    end
  end

  private

  def project_params
    params.require(:project).permit(:name, :title, :subtitle, :about, :image, :blog_url, :status, :comment, :image_name, :position,
      assets: [], researchers_attributes: [:id, :name, :title, :description, :image, :_destroy],
      partners_attributes: [:id, :name, :url, :image, :_destroy], assets_destroy: {})
  end

  def project_owner_user
    #need to define @project so project_owner? in sessions_helper can work
    #assuming that if its not for a project, its for a project id
    params[:id].nil? ? @project = Project.find(params[:project_id]) : @project = Project.find(params[:id])
    redirect_to(root_path) unless project_owner?
  end

  def project_admin
    if params['project_id']
      @project = Project.find(params['project_id'])
    elsif params[:id]
      @project = Project.find(params[:id])
    end
    redirect_to(root_path) unless project_admin?
  end

  def project_manager_json
    render json: { error: "Permission denied." }, status: :forbidden unless project_manager?
  end

  #pl_user -> project level user
  def project_member
    @project = Project.find(params[:id])
    redirect_to(root_path) unless @project.member?(current_user) || lead_annotator?
  end

end
