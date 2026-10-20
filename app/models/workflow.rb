=begin

A Workflow is responsible for assigning kits, and sometimes creating those kits.
The following line (from TaskUsersController) sums up the relationship:

    @kit = @workflow.work task_user

In other words, a workflow is like a function from tasks and users to kits.  The
above line passes control to Workflow#work (in this file) and is called every time
a user tries to work on a task or kit.  The primary ways this happens are clicking
Start/Continue on their home page, or closing a kit in order to get a new one.
This function would also be called if a user simply refreshes the page when working
on a kit, but in this case assignment wouldn't happen, the function simply returns
the current kit.

Workflows handle various changes of state.  Although these states are customizable,
there's little variation across tasks, so that tasks can be treated as uniformly
as possible.  A Kit normally goes through this process:

    unassigned -> assigned -> done

A TaskUser, which represents a particular User in a particular Task, normally
alternates between two states:

    needs_kit <-> has_kit
    
Other states are possible, but the above is the norm.

There are two basic types of Workflows which are handled in this Workflow file/class,
called OnTheFly and Orderly.  OnTheFly creates a new kit every time, always using
the same source media in every kit.  Orderly assumes that kits already exist, created
outside the workflow, and simply assigns them in order.  Every workflow calls
the assign_kit function found in this file; the Orderly workflow is essentially
just assign_kit, while OnTheFly creates a default kit before calling assign_kit,
ensuring the user gets the new kit.

Since most of the operations of a workflow apply to all workflows, other workflows
are made by subclassing Workflow.  Details can be found in their respective files.

SameListForEveryone is the third one worth knowing about.  A task carrying it
also carries a list of documents (task_docids, entered on the Docid List tab of
the Task tab), and every user of that task works that same list: when a user
comes for work with nothing left to do, it creates a kit for each document on
the list they haven't had yet, then assigns one in order.  A user part-way
through the list gets their next kit and nothing is created; a user who has
finished it stays finished, since the list is a list and not a supply.  It is
the general form of WorkflowTemp, which does the same with three docids written
into the class; that one is unchanged and still in use.

A subclass is reached through the `else` branch of #work below, which calls
#main for any workflow whose name isn't Orderly or OnTheFly.  The row's `type`
column has to name the subclass — see db/migrate/*_add_same_list_for_everyone_workflow.rb,
which is a migration rather than a seed because production's database already
exists and db:prepare only seeds one it had to create.

=end

class Workflow < ApplicationRecord
  # attr_accessible :name, :user_states, :description, :type
  has_many :tasks

  scope :all_newest_first, -> { order('created_at DESC') }

  scope :sorted, -> { order('name ASC') }

  class UnknownMessageError < StandardError
  end

  class NoKitError < StandardError
  end

  class EndOfListError < StandardError
  end

  class HoldError < StandardError
  end

  class TaskLockError < StandardError
  end

  class WorkError < StandardError
  end

  class ReadOnlyError < StandardError
  end

  class TaskInactiveError < StandardError
  end

  class KitLockError < StandardError
  end

  def work_ajax(task_user, kit, message, value)
    case message
    when 'skip'
      kit.state = message
      kit.save!
      task_user.goto_state 'needs_kit'
      :work
    when 'done', 'nothing_to_annotate', 'wrong_genre'
      kit.done_comment = value if value
      kit.state = message
      kit.save!
      # Lock.release 'kit', kit.uid, task_user.user_id
      # Lock.release 'root', kit.tree.uid, task_user.user_id
      task_user.goto_state 'needs_kit'
      :work
    when 'broken'
      kit.broken_comment = value if value
      kit.state = message
      kit.save!
      # Lock.release 'kit', kit.uid, task_user.user_id
      # Lock.release 'root', kit.tree.uid, task_user.user_id
      task_user.goto_state 'needs_kit'
      :work
    when 'logout'
      task_user.update( state: 'paused' )
      :logout
    when 'done_logout'
      kit.state = 'done'
      kit.save!
      task_user.update( state: 'needs_kit' )
      # Lock.release 'kit', kit.uid, task_user.user_id
      # Lock.release 'root', kit.tree.uid, task_user.user_id
      :logout
    when 'switch'
      task_user.update( state: 'paused' )
      :home
    when 'done_switch'
      kit.state = 'done'
      kit.save!
      task_user.update( state: 'needs_kit' )
      # Lock.release 'kit', kit.uid, task_user.user_id
      # Lock.release 'root', kit.tree.uid, task_user.user_id
      :home
    when 'done_hold'
      kit.state = 'done'
      kit.save!
      task_user.update( state: 'hold' )
      # Lock.release 'kit', kit.uid, task_user.user_id
      # Lock.release 'root', kit.tree.uid, task_user.user_id
      :home
    when 'reset'
      if task_user.user_lead_annotator? || task_user.system_admin?
        # Lock.release 'root', kit.tree.uid, task_user.user_id
        kit.reset
        kit.state = 'reset'
        kit.save!
        task_user.update( state: 'needs_kit' )
        # Lock.release 'kit', kit.uid, task_user.user_id
      else
        logger.debug "!!!NOTICE!!!#{task_user.user_name} tried to send a reset message without correct permissions"
      end
      :home
    end
  end

  # a subclass of this one has to be used
  def main(task_user)
    raise "bad workflow #{name}"
  end
  
  def kit_source_helper(*args)
  end
  
  def work(task_user)
    @task_user = task_user
    @task_id = @task_user.task_id
    @user_id = @task_user.user_id
    unlock_task
    case @task_user.state
    when 'needs_kit', 'ok'
      case name
      when 'Orderly'
        unlock_task
        lock_task
        assign_kit :orderly
        unlock_task
      when 'OnTheFly' # doesn't need a lock
        onthefly
      else
        unlock_task
        lock_task
        main
        unlock_task
      end
    when 'paused'
      @task_user.goto_state 'has_kit'
      @kit = Kit.find_by_uid @task_user.kit_oid
    when 'has_kit'
      @kit = Kit.find_by_uid @task_user.kit_oid
      # task_user.goto_state 'needs_kit' if @kit.nil?
    end
    # Lock.grab 'kit', @kit.uid, task_user.user_id
    # Lock.grab 'root', @kit.tree.uid, task_user.user_id

    @kit.workflow_id = id
    @kit.read_only = false
    @kit.task_user_id = @task_user.id
    @kit

    #raise @kit.tree.tree.find_node('29').value.to_s

 end

  def read_only(kit_id)
    @kit = Kit.find_by_uid kit_id
    @kit.workflow_id = id
    @kit.read_only = true
    @kit
  end

  def return_to_kit(task_user, kit_id)
    @kit = Kit.find kit_id
    raise NoKitError, "couldn't find kit #{kit_id}" if @kit.nil?
    raise HoldError, "this kit isn't in this task" unless @kit.task_id == task_user.task_id
    raise HoldError, "you can't return to this kit because it's not assigned to you" unless @kit.state == 'assigned' and @kit.user_id == task_user.user_id
    raise HoldError, "it appears you didn't start this task yet" if task_user.kit_oid.nil?
    return if @kit.uid == task_user.kit_oid
    task_user.update( kit_oid: @kit.uid, state: 'has_kit'  )
    @kit
  end

  def onthefly
    create_default_kit_with_default_doc
    @task_user.goto_state 'has_kit'
    assign_kit :skip
  end

  def create_default_kit_with_default_doc
    @kit = @task_user.task.create_default_kit_with_default_doc
  end

  def put_on_hold_if_kit_limit_is_reached
    kit_limit = Task.where( id: @task_id ).pluck(:per_person_kit_limit).first
    if kit_limit
      if Kit.where( user_id: @user_id, task_id: @task_id, state: 'done' ).count >= kit_limit
        raise HoldError, "your work is on hold because you've reached the limit of #{kit_limit} kits"
      end
    end
  end

  def lock_task
    raise TaskLockError, "Task #{@task_id} locked by User #{@user_id}" if Task.where(id: @task_id, lock_user_id: nil).update_all(lock_user_id: @user_id) != 1
  end

  def unlock_task
    Task.where(id: @task_id, lock_user_id: @user_id).update_all(lock_user_id: nil)
  end

  def find_kit_with_user_id(x)
    @kit = nil
    Kit.unassigned_by_task_and_user( @task_id, x ).order(:state, :uid).each do |kit|
      next if kit.blocked_for_user_id? @user_id
      @kit = kit
      break
    end
  end

  def assign_kit(method)
    put_on_hold_if_kit_limit_is_reached
    case method
    when :orderly#assigns the unassigned kit that is the oldest (was created first)
      #first try to find a kit with the user's id in it
      find_kit_with_user_id @user_id
      #if no kits have the user id, find one without a user_id
      if @kit.nil?
        find_kit_with_user_id nil
        @kit.kit_batch.assign @task_user if @kit and @kit.kit_batch_id
      end
    when :skip#workflow specific assignment code was used, skip this part
      "no op"
    when :reject
      Lock.release 'workflow', id, @task_user.user_id
      raise NoKitError, 'no available kits'
    when :hold
      Lock.release 'workflow', id, @task_user.user_id
      raise HoldError, 'your work is on hold'
    else
      raise 'no method of assignment'
    end
    unlock_task if @kit.nil?
    raise NoKitError, 'no available kits' if @kit.nil?
    logger.debug "assigning user: #{@user_id} the kit: #{@kit.uid}"
    @kit.update(state: 'assigned')
    logger.info "assign #{@kit.id} #{@kit.uid} #{@kit.state}"
    raise "assign #{@kit.id} #{@kit.uid} #{@kit.state}" if @kit.state != 'assigned'

    #if @kit.tree.nodes.count == 0
    if @kit.tree_id.nil?
      @kit.create_tree @task_user
      logger.debug "created a new tree for: #{@kit.id} #{@kit.uid}"
    else
      logger.debug "using existing tree for: #{@kit.id} #{@kit.uid}"
    end
    @kit.update( user_id: @user_id )
    @task_user.update( kit_oid: @kit.uid )
    @task_user.goto_state 'has_kit'
  end

  def enroll_if_necessary(task_user)
    id = task_user.task.meta[:collection_id]
    if id
      Enrollment.where( collection_id: id, user_id: task_user.user_id ).first_or_create
    else
      nil
    end
  end
  
  def new_kits_available?(task_user)
    if name == 'OnTheFly'
      true
    else
      false
    end
  end

  # How much work this user has left, for a workflow that knows. Only asked
  # when no unassigned kit rows are waiting, which for most workflows means
  # there's nothing left to count.
  def kits_left(task_user)
    0
  end

  # What the Project Tasks table's "Available Kits" column shows: work on this
  # task nobody has done yet. For most workflows that's the unassigned kits,
  # which the caller has already counted in one query across the project.
  #
  # A workflow that creates kits when the user arrives overrides this, since
  # its outstanding work is mostly kits that don't exist yet.
  def outstanding_kit_count(task, unassigned_count)
    unassigned_count
  end

  # query kits to see what sources have been used
  def source_uids_already_used
    Kit.where(task_id: @task_id).pluck(:source_uid).uniq
  end
  
  # query kits to see what sources have been used by this user
  def source_uids_already_used_by_user
    Kit.where(task_id: @task_id, user_id: @user_id).pluck(:source_uid).uniq
  end
  
  def count_available_kits
    Kit.where(task_id: @task_id, user_id: [ @user_id, nil ], state: [ :unassigned ]).count
  end

  def unassigned_kit_ids
    @unassigned_kit_ids ||= Kit.where(task_id: @task_id, state: :unassigned).pluck(:id)
  end
  
  def blocked_kit_ids
    @blocked_kit_ids ||= KitUser.where(user_id: @user_id).pluck(:kit_id)
  end
  
  def unassigned_not_blocked_kit_ids
    unassigned_kit_ids - blocked_kit_ids
  end
  
  def task
    @task_user.task
  end
  
  def kit_uids_from_1p_by_current_user
    Kit.where(task_id: task.meta['1p_task_id'], user_id: @user_id).pluck(:uid)
  end
  
  def kit_uids_from_dual
    Kit.where(id: Kit.where(task_id: task.id).pluck(:dual_id)).pluck(:uid)
  end

  def kit_uids_from_original_kits
    Kit.where(id: Kit.where(task_id: task.id).pluck(:orig_id)).pluck(:uid)
  end

  def kit_uids_from_1p_done
    Kit.where(task_id: task.meta['1p_task_id'], state: :done).pluck(:uid)
  end
  
  def loop_over_kits_to_do
    Kit.where(uid: kit_uids_to_do).each do |source_kit|
      yield source_kit
    end
  end
  
  def make_dual_and_block_first_user(kit:, source_kit:, status:)
    kit.dual_id = source_kit.id
    share_source_and_block_first_user(kit: kit, source_kit: source_kit, status: status)
  end

  def share_source(kit:, source_kit:)
    kit.source = source_kit.source
    kit.source_uid = source_kit.source_uid
    kit.save!
  end

  def share_source_and_block_first_user(kit:, source_kit:, status:)
    share_source kit: kit, source_kit: source_kit
    KitUser.create(kit_id: kit.id, user_id: source_kit.user_id, status: status)
  end

  def after_done(kit)
    create_duals kit
  end
  
  def create_duals(kit)
    p = kit.task.meta['dual_percentage']
    if p and not kit.dual_id
      d = kit.task.meta['dual_minimum_duration']
      if d
        v = KitValue.where(kit_id: kit.id, key: :duration).first
        if v and v.value.to_f >= d.to_f
          create_dual_randomly kit, p
        end
      else
        create_dual_randomly kit, p
      end
    end
  end

  def create_dual_randomly(kit, p)
    p = p.to_f / 100
    if p > 0.0 and p <= 1.0 and p > rand
      create_dual kit
    end
  end

  def create_dual(source_kit)
    kit = source_kit.task.create_default_kit
    make_dual_and_block_first_user kit: kit , source_kit: source_kit, status: 'dual'
  end

end
