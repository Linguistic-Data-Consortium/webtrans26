class FeaturesController < ApplicationController

  # before_action :authenticate
  before_action :set_model

  def set_model
    @model = Feature
  end

  def index
    index_allm only: :admin
  end

  def show
    show_usersm params: params, only: :admin, users: false
  end

  def create
    createjm params: feature_params, only: :admin
  end

  def update
    updatejm p: params, params: feature_params, only: :admin
  end

  def destroy
    destroyjm params: params, only: :admin
  end

  private

  def feature_params
    params.require(:feature).permit(:category, :name, :value, :label, :description)
  end

end
