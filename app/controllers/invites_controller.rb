class InvitesController < ApplicationController
    allow_unauthenticated_access only: %i[ edit ]
    before_action :get_user,       only:   [ :edit, :update ]
    before_action :valid_user,     only:   [ :edit, :update ]
  
    def indexo
      allow(:project_manager) do
        @title = "All Projects"
        @users = User.where(invite_sent_by: current_user.id)
        j = {}
        j[:users] = @users.map do |user|
          h = {
            id: user.id,
            email: user.email_address,
            sent: user.invite_sent_at,
            activated: user.activated
          }
          h
        end
        j[:tasks_index] = {}
        j[:personal] = nil
        # ProjectUser.where(user_id: current_user.id, admin: true).each do |p|
        j[:projects] = Project.all.map do |p|
          j[:tasks_index][p.id] = p.tasks.map do |t| 
            {
              id: t.id,
              name: t.name
            }
          end
          j[:personal] = p.id if p.name == 'Personal'
          {
            id: p.id,
            name: p.name
          }
        end
        j
      end
    end

    def index
      respondj do
        indexo
      end
    end
  
    def edit
      if @user
        if @user.activated?
          flash[:success] = "Your account was already activated"
          redirect_to root_url
        else
          if @user.authenticated?(:invite, params[:id])
            @user.activate
            flash[:success] = "Your account has been activated, please set your user name and password"
            redirect_to edit_password_url(@user.password_reset_token)
          else
            flash[:danger] = "Invalid invitation link"
            redirect_to root_url
          end
        end
      else
        flash[:danger] = "Invalid invitation link"
        redirect_to root_url
      end
    end
  
    def update
      if @user && !@user.activated? && @user.authenticated?(:invite, params[:id])
        @user.update(user_params)
        pus = ProjectUser.where(user_id: @user.id)
        pus.each do |x|
          x.status = 'active'
          x.save
        end
        @user.activate
        start_new_session_for @user
        t = Task.where(name: "Personal/#{@user.id}").first
        t.update(name: "Personal/#{@user.name}") if t
        flash[:success] = "Account activated!"
        redirect_to root_url
      else
        flash[:danger] = "Invalid link"
        redirect_to root_url
      end
    end

    def createo
      email_regex = /\A[\w+\-.#]+@[a-z\d\-.]+\.[a-z]+\z/i
      found = []
      found_error = false
      if params[:email]
        good_invites = params[:email].split.map(&:chomp).select {|invite| invite.match(email_regex)}
        good_invites.each do |invite|
          new_user = User.find_by_email_address(invite)
          found << (if !new_user
            new_user = User.create(email_address: invite)
            # create gets rolled back
            new_user.create_invite_digest current_user.id
            # but then create_invite_digest saves the model, skipping validations
            new_user.send_invitation_email
            "sending to #{invite}"
          else
            found_error = true
            if new_user.activated?
              "#{invite} has already been activated"
            elsif new_user.invite_sent_by == nil
              "#{invite} was created already"
            elsif new_user.invite_sent_by == current_user.id
              new_user.create_invite_digest current_user.id
              new_user.send_invitation_email
              "#{invite} exists, resending invitation"
            else
              "#{invite} was invited by someone else"
            end
          end)
          if params[:role] == "Project Manager" && portal_manager?
            @project_managers ||= Group.find_by_name 'Project Managers'
            @project_managers.users << new_user unless @project_managers.users.include? new_user
            found << "#{invite} was added as Project Manager"
          end
          if params[:role] == "Portal Manager" && admin?
            @portal_managers ||= Group.find_by_name 'Portal Managers'
            @portal_managers.users << new_user unless @portal_managers.users.include? new_user
            found << "#{invite} was added as Portal Manager"
          end
          if params[:project_id]
            if ProjectUser.where(project_id: params[:project_id], user_id: current_user.id, admin: true).length == 1 or
               ProjectUser.where(project_id: params[:project_id], user_id: current_user.id, owner: true).length == 1 or
               project_manager?
              p = Project.find params[:project_id]
              p.users << new_user unless p.users.include? new_user
              found << "#{invite} was added to project"
              if params[:task_id]
                t = Task.find params[:task_id]
                t.users << new_user unless t.users.include? new_user
                found << "#{invite} was added to task"
              # elsif p.name == "Personal"
              #   t = Task.where(
              #     name: "Personal/#{new_user.id}",
              #     project_id: p.id,
              #     kit_type_id: 83,
              #     workflow_id: 2
              #   ).first_or_create
              #   t.users << new_user unless t.users.include? new_user
              #   found << "#{invite} was added to task"
              end
            else
              found_error = true
              found << "you're not an admin for the project"
            end
          end
        end
        if found.length == 0
          found_error = true
          found << "no valid emails found"
        end
        if found_error
          { errors: found }
        else
          { ok: found }
        end
      else
        { errors: [ "no emails given" ] }
      end
      
    end

    def create
      respondj do
        allow(:project_manager) do
          createo
        end
      end
    end

    private
  
    def get_user
      @user = params[:email] ? User.find_by(email_address: params[:email]) : User.find_by(email_address: params[:user][:email])
    end
  
    # Confirms a valid user.
    def valid_user
      unless (@user && 
              @user.authenticated?(:invite, params[:id]))
        redirect_to root_url
      end
    end

    def user_params
      if params.dig(:user,:profile_attributes,:gender_radio)
        gender = params[:user][:profile_attributes][:gender_radio]
        if params[:user][:profile_attributes][:gender_other]
          gender = params[:user][:profile_attributes][:gender_other]
        end
        params[:user][:profile_attributes][:gender] = gender
        params[:user][:profile_attributes].delete(:gender_radio)
        params[:user][:profile_attributes].delete(:gender_other)
      end
      params.require(:user).permit(:name, :ack_name, :email, :password, :password_confirmation, :terms_agreed, profile_attributes: [:year_of_birth, :gender, :cities, :languages_known])
    end
  end
