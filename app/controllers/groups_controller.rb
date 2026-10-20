class GroupsController < ApplicationController

  # before_action :authenticate
  before_action :set_model

  def set_model
    @model = Group
  end

  def users_not_in
    respond_to do |format|
      format.json { render json: Group.find(params[:id]).users_not_in(params[:term]) }
    end
  end

  def index
    Group.where(name: 'Portal Managers').first_or_create
    Group.where(name: 'Project Managers').first_or_create
    index_allm only: :admin
  end

  def custom_attributes(a)
    a[:group_admin_bool] = admin?
  end

  def show
    f = -> (x) { x.group_users.map { |x| { id: x.id, user_id: x.user_id, name: x.user_name } } }
    show_usersm params: params, users: [ :members, f ], only: :admin
  end

  def create
    createjm params: group_params, only: :admin
  end

  def update
    updatejm p: params, params: group_params, only: :admin
  end

  def destroy
    destroyjm params: params, only: :admin
  end

  private

  def group_params
    params.require(:group).permit(:name)
  end

end
