class PagesController < ApplicationController

  allow_unauthenticated_access only: %i[awaiting_activation]

  def awaiting_activation
    @email = params[:email].presence
  end

  def home
    if authenticated?
      redirect_to user_path(current_user)
    else
      if Server.count == 0
        Server.create(name: '')
        # helpers.annotations_setup([])
      end
      @server = Server.new
      @failed = true # prevents repeated checking of the db in views
      @title = "Home"
      @user = User.new
    end
  end

  def versions
    @git = `git log | head -3`.chomp.split("\n")
    @tag = `git describe`
    @gems = `cat Gemfile.lock`
  end

  def echo
    respond_to do |format|
      format.json do
        render json: { time: Time.now.to_s, version: 2 }
      end
      format.html do
        render plain: Time.now.to_s
      end
    end
  end
end
