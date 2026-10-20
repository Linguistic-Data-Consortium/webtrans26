class WorkflowsController < ApplicationController
  before_action :set_model

  def set_model
    @model = Workflow
  end

  def index
    index_allm only: :project_manager
  end

  def show
    respond_to do |format|
      format.json do
        render json: (
          allow(:project_manager) do
            workflow = Workflow.find(params[:id])
            workflow.attributes.merge(types: %w[Orderly OnTheFly])
          end
        )
      end
    end
  end

  def create
    createjm params: workflow_params, only: :admin
  end

  def update
    updatejm p: params, params: workflow_params, only: :admin
  end

  def destroy
    destroyjm params: params, only: :admin
  end

  private

  def workflow_params
    params.require(:workflow).permit(:name, :description, :type, :user_states, :kit_states)
  end
end
