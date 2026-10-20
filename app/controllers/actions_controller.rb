class ActionsController < ApplicationController
  # before_action :authenticate

  def create
    @action = Action.new action_params
    @action.save
    render json: { ok: @action.id }
  end

  private

  def action_params
    params.permit(:user_id, :task_id, :kit_id, :name, :client_time)
  end

end
