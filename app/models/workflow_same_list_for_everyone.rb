# Every user of the task works the same list of documents.
#
# The task carries a list of docids (task_docids, entered on the Task tab). When
# a user comes for work and has nothing left to do, this creates a kit for each
# document on that list they haven't had yet, then assigns one in order. A user
# part-way through the list gets their next kit and nothing is created; a user
# who has finished the list gets nothing, and stays finished — the list is a
# list, not a supply.
#
# The general form of WorkflowTemp, which did this with three docids written
# into the class. That one is still there and unchanged; this one reads its
# list from the task, so it differs per task and changes without a deploy.
class WorkflowSameListForEveryone < Workflow

  # Create what this user still owes, then hand them one.
  def main
    create_more_kits_if_necessary
    assign_kit :orderly
  end

  # Whether this user has work waiting — asked by the dashboard to decide
  # between a Start Now link and "No Available Kits", and asked before any kit
  # exists.
  #
  # Kits are made when the user arrives, so counting kit rows says "none" for
  # everyone who hasn't started, and the link they need to start never appears.
  # What's actually left is what's on the list they haven't had.
  #
  # Reads its task and user from the argument rather than @task_id / @user_id:
  # this is called on a workflow that hasn't been through #work, so those
  # aren't set.
  def new_kits_available?(task_user)
    remaining(task_user).any?
  end

  # What the dashboard's Start Now link says is left: the documents still owed,
  # since the kits for them don't exist until the user comes for them.
  def kits_left(task_user)
    remaining(task_user).size
  end

  # Work on this task nobody has done yet: the kits waiting to be picked up,
  # plus every document still owed to a member — which for a task nobody has
  # started is the whole list, once per member, and no kits at all.
  #
  # Two queries for the task, and only for a task carrying this workflow.
  def outstanding_kit_count(task, unassigned_count)
    list = task.docid_list
    return unassigned_count if list.empty?

    used = Kit.where(task_id: task.id).where.not(user_id: nil)
      .pluck(:user_id, :source_uid)
      .group_by(&:first)
      .transform_values { |rows| rows.map(&:last).uniq }
    owed = task.task_users.pluck(:user_id).sum { |user_id| (list - (used[user_id] || [])).size }
    unassigned_count + owed
  end

  # The documents on the task's list this user hasn't been given yet.
  def remaining(task_user)
    used = Kit.where(task_id: task_user.task_id, user_id: task_user.user_id).pluck(:source_uid).uniq
    task_user.task.docid_list - used
  end

  # Nothing to do while the user still has a kit waiting for them: they're
  # part-way through the list, and the rest arrives when they get there.
  def create_more_kits_if_necessary
    return if count_available_kits > 0

    needed = task.docid_list - source_uids_already_used_by_user
    needed.each do |uid|
      kit = task.create_default_kit
      kit.source = { uid: uid, id: uid, filename: uid }
      kit.source_uid = uid
      kit.user_id = @user_id
      kit.save!
    end
  end
end
