module UsersHelper
  #this function retrieves the tabs to display for this user
  def get_tabs_for_user(user)
    tabs = []
    # tabs << {:id => 'dashboard', :display => 'Dashboard'} if user.dashboard?
    tabs << {:id => 'tasks', :display => 'Task List'} if user.task_users.count > 0 || user.lead_annotator?
    tabs << {:id => 'profile', :display => 'Profile'}
    # tabs << {:id => 'enrollments', :display => 'Enrollments'} if user.enrollments.count > 0 || user.lead_annotator?
    # tabs << {:id => 'reports', :display => 'Reports'} if user.report_groups.count > 0 || user.lead_annotator?
    tabs
  end

  #this function gets the user friendly state for a given task user
  def get_friendly_state_for_taskuser(state)
    {
      'fail' => 'ineligible',
      nil => 'N/A',
      'needs_kit' =>'not in progress',
      'ok' =>'not in progress',
      'has_kit' => 'in progress',
      'paused' => 'in progress (paused)',
      'hold' => 'on hold'
      }[state]
  end

  def new_kits_available?(task_user)
    if @banned_kits && @banned_kits.any? { |x| x.task_id == task_user.task_id }
      kits = Kit.unassigned_by_task_and_user(task_user.task_id, task_user.user_id )
      kits += Kit.unassigned_by_task_and_user(task_user.task_id, nil )
      kits.each do |kit|
        return true if KitUser.where( kit_id: kit.id, user_id: task_user.user_id ).count == 0
      end
      return false
    elsif task_user.task.workflow.new_kits_available? task_user
      true
    else
      @kits_available_by_task.has_key? task_user.task_id
    end
  end

  #function that returns either a link for a user to start/continue doing work, or a string saying there are no kits available
  def get_action_link(task, tuser, text = nil)
    # if task.kits_available? || tuser.has_kit_oid?
    fc = task&.kit_type&.constraints['free_choice']
    if new_kits_available?(tuser) or tuser.has_kit_oid? or fc
      if text.nil?
        link_string = case tuser.state
          when nil, '', 'needs_kit', 'ok'
            'Start Now'
          when 'has_kit', 'paused'
            'Continue'
          when 'hold'
            nil
          end
      else
        link_string = text
      end
      if link_string
        work_path = "/workflows/#{tuser.id}/work/#{task.workflow_id}"
        if task.kit_type.constraints['free_choice'] and tuser.state == 'needs_kit'
          "<a class=browser_link>Browse</div>"
        else
          # Kits that exist and are waiting — or, for a workflow that makes
          # them when the user arrives, what it still owes them.
          count = @kits_available_by_task[task.id] || task.workflow.kits_left(tuser)
          helpers.link_to link_string, work_path, :title => "#{count} kit#{'s' if count != 1} are left to be done"
        end
      else
        ''
      end
    else
      'No Available Kits'
    end
  end
end
