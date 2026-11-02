module SessionsHelper

  # def authenticate
  #   if signed_in?
  #     confirm
  #   else
  #     deny_access
  #   end
  # end

  # def authenticate_or_die
  #   if signed_in?
  #     confirm
  #   else
  #     render nothing: true, status: :unauthorized
  #   end
  # end
  # def confirm
  #   store_location
  #   redirect_to '/confirmation' if request.format.html? and @current_user.confirmation_expired?
  # end

  # def deny_access
  #   store_location
  #   redirect_to root_path, :flash => {:error => 'Please sign in to access this page.'}
  # end

  # def log_in(user)
  #   session[:user_id] = user.id
  # end

  # def remember(user)
  #   user.remember
  #   cookies.permanent.signed[:user_id] = user.id
  #   cookies.permanent[:remember_token] = user.remember_token
  # end

  # def create_anonymously
  #   user = User.make_anon
  #   user.save!
  #   user.activate
  #   user
  # end

  # def login_anonymously
  #   user = create_anonymously
  #   log_in user
  #   remember user
  #   user
  # end

  def current_user
    # if (user_id = session[:user_id])
    #   @current_user ||= User.find_by(id: user_id)
    # elsif (user_id = cookies.signed[:user_id])
    #   user = User.find_by(id: user_id)
    #   if user && user.authenticated?(:remember, cookies[:remember_token])
    #     log_in user
    #     @current_user = user
    #   end
    # end
    @current_user ||= Current.user
  end

  def current_user?(user)
    user == current_user
  end

  # def logged_in?
  #   !current_user.nil?
  # end

  def signed_in?
    !current_user.nil?
  end

  # def forget(user)
  #   user.forget
  #   cookies.delete(:user_id)
  #   cookies.delete(:remember_token)
  # end

  # def log_out
  #   forget current_user
  #   session.delete(:user_id)
  #   @current_user = nil
  # end

  # def redirect_back_or(default)
  #   redirect_to(session[:forwarding_url] || default)
  #   session.delete(:forwarding_url)
  # end

  # def store_location
  #   session[:forwarding_url] = request.original_url if request.get? and request.format.html?
  # end

  def admin?
    signed_in? ? current_user.admin? : false
  end

  def admin_user
    unless admin?
      flash[:error] = "You must be a sysadmin to access this page."
      redirect_to(root_path)
    end
  end

  def portal_manager?
    signed_in? ? current_user.portal_manager? || current_user.admin? : false
  end

  def portal_manager_user
    unless portal_manager?
      flash[:error] = "You must be a Portal Manager to access this page."
      redirect_to(root_path)
    end
  end

  def project_manager?
    signed_in? ? current_user.project_manager? || portal_manager? : false
  end

  def project_manager_user
    unless project_manager?
      flash[:error] = "You must be a Project Manager to access this page."
      redirect_to(root_path)
    end
  end

  def lead_annotator?
    project_manager?
  end

  def lead_annotator_user
    project_manager_user
  end

  def project_designer_user
    if params['project_id']
      @project = Project.find(params['project_id'])
    elsif params[:id]
      @project = Project.find(params[:id])
    end
    project_admin?
  end

  def fill_in_project
    @project ||= Project.find(params[:id])
    @project ||= Project.find(params['project_id'])
    unless @project
      flash[:error] = "Project not found."
      redirect_to root_path
    end
  end

  def project_owner?
    fill_in_project
    signed_in? ? @project.owner?(current_user) || portal_manager? : false
  end

  def project_owner_user
    unless project_owner?
      flash[:error] = "You must be a Project Owner."
      redirect_to root_path
    end
  end

  def project_admin?
    fill_in_project
    signed_in? ? (@project.admin?(current_user) || project_owner?) : false
  end

  def project_admin_user
    unless project_admin?
      flash[:error] = "You must be a Project Admin."
      redirect_to root_path
    end
  end

  def fill_in_task
    @task ||= Task.find(params[:id])
    @task ||= Task.find(params['task_id'])
    unless @task
      flash[:error] = "Task not found."
      redirect_to root_path
    end
    @project = @task.project
    unless @project
      flash[:error] = "Project not found."
      redirect_to root_path
    end
  end

  def task_admin?
    fill_in_task
    signed_in? ? (@task.admin?(current_user) || project_admin?) : false
  end

  def name_change_helper(n, name)
    ncc = NodeClass.where(name: n).first
    if ncc
      ncc.update(name: name)
      ncc
    else
      NodeClass.where(name: name).first_or_create
    end
  end

end
