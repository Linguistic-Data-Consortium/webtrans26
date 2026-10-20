class ProjectUsersController < ApplicationController

  # before_action :authenticate

  def create
    respond_to do |format|
      format.json do
        @project = Project.find params[:project_id]
        user = User.find_by id: params[:user_id]
        if !project_admin? # uses @project
          render json: { error: 'permission denied' }
        elsif user.nil?
          # No user_id in the request (or an unknown one): report it as a normal
          # JSON error rather than raising RecordNotFound and returning a 404
          # the caller can't read.
          render json: { error: 'no such user' }
        elsif @project.member? user
          render json: { error: "#{user.name} is already a member of #{@project.name}" }
        else
          @project.users << user
          render json: { ok: "#{user.name} has been added to #{@project.name}" }
        end
      end
    end
  end

  def destroy
    respond_to do |format|
      format.json do
        pu = ProjectUser.find params[:id]
        @project = pu.project
        if project_admin? # uses @project
          @project.delete_user pu.user
          render json: { ok: "#{pu.user_name} has been removed from #{@project.name}" }
        else
          render json: { error: 'permission denied' }
        end
      end
    end
  end

  def update
    respond_to do |format|
      format.json do
        project_user = ProjectUser.find params[:id]
        @project = project_user.project
        if project_owner? # uses @project
          response = []
          if params.has_key? :owner
            project_user.update(owner: params[:owner])
            response << "#{project_user.user_name} #{project_user.owner? ? "has been made" : "is no longer"} an owner of #{project_user.project_name}"
          end
          if params.has_key? :admin
            project_user.update(admin: params[:admin])
            response << "#{project_user.user_name} #{project_user.admin? ? "has been made" : "is no longer"} an admin of #{project_user.project_name}"
          end
          render json: { ok: response.join(',') }
        else
          render json: { error: 'permission denied' }
        end
      end
    end
  end

end
