class AccountActivationsController < ApplicationController

  allow_unauthenticated_access only: %i[ edit ]

  def edit
    user = User.find_by(email_address: params[:email])
    if user && user.authenticated?(:activation, params[:id])
      if user.activated
        flash[:success] = "Already activated"
        # redirect_to user
      else
        user.activate
        # start_new_session_for user
        flash[:success] = "Account activated!"
        # redirect_to user
      end
    else
      flash[:danger] = "Invalid activation link"
      # redirect_to root_url
    end
    redirect_to root_url
  end

end
