class AnnotationsController < ApplicationController

  # skip_before_action :verify_authenticity_token, only: :create

  def annotatex(o)
    # last_ann = Annotation.where(tree_id: @tree.id).last
    # last_ann = Ann.where(tree_id: kit_id).last if last_ann.nil?
    # last_ann = OpenStruct.new(id: nil, last_iid: -1) if last_ann.nil? # or tree_id.nil?
    # last_children = nil
    # hash = json
    anns = []
    o['messages'].each do |m|
      iid = m['node']
      message = m['message']
      value = m['value']
      puts value
      case message
      when 'new'
        parent_id = nil
        last_children = nil
        last_iid = 0
      when 'add'
        parent_id = @last_ann.id
        last_children = value['value'].split ','
        # last_iid = (@last_ann ? @last_ann.last_iid : 1) + last_children.length
        last_iid = @last_ann.last_iid + last_children.length
        # value = { 'value' => value }
      else
        parent_id = @last_ann.id
        last_children = nil
        last_iid = @last_ann.last_iid
      end
      # docid = 
      # begi = 
      # begr = value && value['real'] ? value['beg'] : nil
      @last_ann = Annotation.create(
        transaction_id: 0,
        parent_id: parent_id,
        user_id: @task_user.user_id,
        task_id: @task_user.task_id,
        kit_id: @kit.id,
        tree_id: @tree.id,
        message: message,
        iid: iid,
        last_iid: last_iid,
        # node_value: XodeValue.new_value(value)
        value: (value ? value['value'] : nil),
        docid: (value ? value['docid'] : nil),
        begr: (value && value['type'] == 'real' ? value['beg'] : nil),
        endr: (value && value['type'] == 'real' ? value['end'] : nil),
        begi: (value && value['type'] != 'real' ? value['beg'] : nil),
        endi: (value && value['type'] != 'real' ? value['end'] : nil)
      )
      anns << @last_ann
    end
    anns
  end

  # message protocol:  space separated messages, comma separated fields within messages
  # e.g: "4,add 5,change,blah 6,text,blah,123,456" is a sequence of 3 messages
  # message 1:  add child to node 4
  # message 2:  change value of node 5 to "blah"
  # message 3:  change text pointer of node 6 to docid=blah, beg=123, end=456
  def create
    task_user = TaskUser.find params[:task_user_id]
    @task_user = task_user
    @work_path = "/workflows/#{task_user.id}/work/#{task_user.task_workflow_id}"
    locked = false
    # this wasn't possible when the qc mode existed, but now seems like the right thing
    @response = if current_user.id != task_user.user_id
      [ { :redirect => root_path } ]
    elsif task_user.task.status == 'inactive'
      [ { :redirect => root_path, :message => 'inactive' } ]
    elsif task_user.state == 'hold'
      [ { :redirect => root_path } ]
    else
      #set the current_task_user_id if its different than the one being annotated on, set the state to paused for the previous taskuser
      logger.debug "kit_oid #{task_user.kit_oid}"
      current_user.update_current_task_user task_user
      logger.debug "kit_oid #{task_user.kit_oid}"
      @kit = Kit.find_by_uid(params[:qc] ? params[:kit_id] : task_user.kit_oid)
      @tree = @kit.tree
      @last_ann = Annotation.where(tree_id: @tree.id).last
      @response = if current_user.id != @kit.user_id #or current_user.id != @tree.user_id
        [ { :redirect => root_path } ]
      else
        locked = true
        3.times do
          locked = Tree.where(id: @tree.id, locked: nil).update_all(locked: current_user.id) == 0
          break unless locked
          sleep 1
        end
        if locked
          [ { error: "This tree is locked.", current: true } ]
        else
          r = helper5
          Tree.where(id: @tree.id).update_all(locked: nil)
          r
        end
      end
  
    end

    respond_to do |format|
      format.json do
        render :json => @response
      end
    end

  end

  def helper5
    # object being sent back via ajax (an array of responses, one for each message)
    # a workflow message will cause a redirect, essentially eliminating the responses of further messages
    request = JSON.parse params[:json]
    if request['kit_uid'] != @kit.uid
      [ { :redirect => root_path } ]
    else
      helper4 request
    end
  end

  def helper4(request)
    # work_path = "/workflows/#{task_user.task_workflow_id}/work/#{task_user.id}"
    # work_path = "/task_users/#{task_user.id}"
    if request['messages'].size == 0
      return [ { :error => "empty message, nothing to do" } ]
    end

    # if request['messages'][0] =~ /^new,/
    #   return [ { :error => "bad request, begins with 'new'" } ]
    # end

    task_user = current_user.current_task_user
    raise "error" if task_user.id != @task_user.id

    annotations = annotatex request
    client_time = request['client_time']

    @response = []
    annotations.each_with_index do |a, idx|
      helper2 a, idx
    end
    @response
  end

  # Each response describes the annotation it answers, read off that annotation.
  #
  # This used to replay the whole tree — NodeDerivation.for_tree, every row for
  # the tree, once per request — and read the answer out of the result. That is
  # unnecessary and, for a batch, wrong.
  #
  # Unnecessary because the replay's value for a node is literally the
  # annotation's own `node_value` (NodeDerivation::Result#value_for), so for the
  # annotation just written it is reading back what it has in hand. The cost grew
  # with the transcript: a 300-segment kit is ~1,500 rows replayed to answer a
  # one-row question, on every flush.
  #
  # Wrong because `annotatex` writes every message before this loop runs, so the
  # replay is the state *after* the whole batch. Two changes to one node in one
  # request gave both responses the second value — the first message was told its
  # own change hadn't taken. Nothing issued such a batch, so it was never seen,
  # but confirm_message would have reported it as a divergence and (since the
  # desync banner) put an undismissable warning in front of the annotator. An
  # annotation is the state as of itself; that is exactly what a per-message
  # answer needs.
  #
  # Dropped with the replay: `parent_id` on a change, and `node.meta.name`. Both
  # need tree structure, and neither is read — `parent_id` appears nowhere in
  # app/javascript, and `meta.name` is read only off an add's `nodes`, which is
  # built from the group string below. Everything confirm_message compares is
  # still here.
  def helper2(a, idx)
            message = a.message
            value = a.value
            response = { :old_id => a.iid, :message => message }
            @response << response
            #raise message.to_s
            # 'fork', 'update_order' and 'move' used to be handled here, each by
            # mutating Tree's in-memory node graph. No client sends them — the
            # waveform only ever sends new/add/change/delete/done — and the
            # graph they mutated no longer exists, so they now fall through to
            # helper3, which reports an unknown message.
            case message
            #code to delete a ListItem from a List
            when 'delete'
              response[:parent_id] = 0
              response[:annotation_id] = a.id
            #code to add a new ListItem to a List
            when 'add'
              # Only the list item carries this annotation; its children start
              # out valueless, pointing at the id-0 placeholder — so this is one
              # element, and the group string names it. "5:SegmentListItem,6:Arc,…"
              # gives the iid and the name; the value is the string itself.
              response[:nodes] = [ list_item_node(a) ]
              response[:annotation_id] = a.id
            when 'noop'
              response[:noop] = true
            #code to change an existing widget's value, making an annotation
            when 'change'
              #return the value of the node too, necessary for Text widgets and Menu widgets at least
              response[:node] = { "meta" => { "id" => a.iid }, "value" => a.node_value }
              response[:node]['value'][:type] = 'real' if response[:node]['value'][:beg].class == Float
              response[:annotation_id] = a.id
            else
              helper3 message, value, response
            end
  end
  # The list item an 'add' created, from the group string it recorded:
  # "5:SegmentListItem,6:Arc,7:Text,8:Speaker" → iid 5, name SegmentListItem.
  # Shaped like NodeDerivation#client_hash, which is what this replaced.
  def list_item_node(a)
    iid, name = a.value.to_s.split(',').first.to_s.split(':', 2)
    { "meta" => { "name" => name, "id" => iid.to_i }, "value" => { value: a.value } }
  end

  def helper3(message, value, response)
              w = @task_user.task_workflow
              begin
                symbol = w.work_ajax @task_user, @kit, message, value
                case symbol
                when :work
                  response[:redirect] = @work_path
                when :home
                  response[:redirect] = root_path
                when :logout
                  response[:redirect] = logout2_path
                when :noop
                  response[:noop] = 'noop'
                else
                  raise "ajax error on message: #{message}, return value: #{symbol}"
                end
              rescue Workflow::UnknownMessageError => e
                response[:error] = "unknown message: #{message}"
              rescue Workflow::EndOfListError => e
                response[:error] = e.to_s
              rescue Workflow::NoKitError => e
                response[:redirect] = @work_path
              # rescue Lock::LockError => e
              #   response[:redirect] = root_path
              end
  end

end
