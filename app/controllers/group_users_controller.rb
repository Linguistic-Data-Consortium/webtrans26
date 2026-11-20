class GroupUsersController < ApplicationController
  # before_action :authenticate

  def create
    respondj do
      allow(:admin) do
        group = Group.find params[:group_id]
        user = User.find_by id: params[:user_id]
        if user.nil?
          # No user_id in the request (or an unknown one): report it as a normal
          # JSON error rather than raising RecordNotFound and returning a 404
          # the caller can't read.
          { error: 'no such user' }
        elsif group.member? user
          { error: "#{user.name} is already a member of the group: #{group.name}" }
        else
          group.users << user
          audit("group.added", user: user, actor: current_user, group: group.name)
          { ok: "#{user.name} has been added to the group: #{group.name}" }
        end
      end
    end
  end

  def destroy
    respondj do
      allow(:admin) do
        gu = GroupUser.find params[:id]
        group = gu.group
        group.delete_user gu.user
        audit("group.removed", user: gu.user, actor: current_user, group: group.name)
        { ok: "#{gu.user_name} has been removed from the group: #{group.name}" }
      end
    end
  end

end
