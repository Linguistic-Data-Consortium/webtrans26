# The list of documents a task hands to every one of its users — read and
# written from the Docid List tab on the Task tab of the user page.
#
# Only meaningful for a task whose workflow is SameListForEveryone; every other
# workflow ignores the list. The tab says so rather than hiding, since a list
# is usually entered before the workflow is switched over.
class TaskDocidsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [ :replace ]
  # Reading is gated as well as writing: the tab is offered to a task's admins,
  # and the endpoint behind it shouldn't be looser than the tab.
  before_action :task_admin, only: [ :index, :replace ]

  # GET /task_docids?task_id=
  def index
    respond_to do |format|
      format.json { render json: list_for(@task) }
    end
  end

  # POST /task_docids — the whole list, as typed: one docid per line.
  #
  # Wholesale replacement, because the list is a list. Blank lines and repeats
  # are dropped, and what comes back is what's now stored, so the box shows
  # what was kept rather than what was sent.
  def replace
    respond_to do |format|
      format.json do
        docids = params[:docids].is_a?(Array) ? params[:docids] : params[:docids].to_s.split("\n")
        TaskDocid.replace_for(@task.id, docids)
        render json: list_for(@task.reload)
      end
    end
  end

  private

  def list_for(task)
    {
      task_id: task.id,
      workflow: task.workflow&.name,
      # The list only does anything under this workflow. Said here rather than
      # worked out in the client, which would have to know the name too.
      used_by_workflow: task.workflow&.name == "SameListForEveryone",
      docids: task.docid_list,
      text: TaskDocid.text_for(task.id)
    }
  end

  # Same rule as the Kits tab: a task's admin may change its list.
  def task_admin
    @task = Task.find(params[:task_id])
    render json: { error: "You must be a task admin to do that." } unless task_admin?
  end
end
