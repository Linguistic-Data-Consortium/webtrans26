class ActionsController < ApplicationController
  # before_action :authenticate

  def create
    @action = Action.new action_params
    # Whose action it was comes from the session, never from the request.
    @action.user_id = current_user.id
    @action.save
    render json: { ok: @action.id }
  end

  private

  def action_params
    params.permit(:task_id, :kit_id, :name, :client_time)
  end

end
