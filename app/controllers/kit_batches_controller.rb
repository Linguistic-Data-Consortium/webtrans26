class KitBatchesController < ApplicationController
  # before_action :authenticate

  def index
    # @kit_creation_counts = KitCreation.all.group(:kit_batch_id).count
    # index_all model: KitBatch, only: :any
    @kit_batches = KitBatch.where("name is not null").includes(:user, :task, :created_by_user)
    j = {}
    j[:kit_batches] = @kit_batches.map do |x|
      {
        id: x.id,
        name: x.name
      }
    end
    j[:tasks_index] = {}
    # ProjectUser.where(user_id: current_user.id, admin: true).each do |p|
    j[:projects] = Project.all.map do |p|
      j[:tasks_index][p.id] = p.tasks.map do |t| 
        {
          id: t.id,
          name: t.name
        }
      end
      {
        id: p.id,
        name: p.name
      }
    end
    respond_to do |format|
      format.html
      format.json { render json: j }
    end
  end

  def show
    kit_batch = KitBatch.includes( { :kit_creations => [ :kit, :user ] } ).find(params[:id])
    kit_creations = kit_batch.kit_creations
    respond_to do |format|
      format.html
      format.json do
        # render json: create_kits
        render json: kit_batch.attributes
      end
    end
  end

  def create_kits
    if @kit_batch.ready
      locked = 0
      locked = KitBatch.where(id: @kit_batch.id, state: 'ready').update_all(state: 'locked')
      if locked == 1
        r = @kit_batch.create_kits2
        if r == 'done'
          { status: 'finished' }
        else
          { status: 'error', error: r }
        end
      else
        { status: 'done' }
      end
    else
      { status: 'done' }
    end
  end

  # what's a good permissions policy for this?
  def create
    createj model: KitBatch, params: kit_batch_params, only: :any, own: false
  end

  def createx
    params_dup = kit_batch_params.dup
    if !params_dup["file"].blank?
      params_dup["kit_creations"] = params_dup["file"].read
      params_dup.delete("file")
    end
    if params_dup["user_id"].blank? || ( params_dup["user_id"].match(/\d+/) && User.exists?(params_dup["user_id"]) )
      @kcs = params_dup.delete("kit_creations")
      if params_dup["kit_creator"] == ""
        params_dup["kit_creator"] = "KitCreator"
      end
      KitBatch.transaction do
        puts "creating kit batch with #{params_dup}"
        @kit_batch = KitBatch.new(params_dup)
        @kit_batch.state = 'ready'
        if @kit_batch.save
          header = [] if @kit_batch["creation_type"] == "data_set"
          @kcs.split(/\r?\n/).each.with_index do |kcc, i|
            kc = kcc.strip
            if @kit_batch["creation_type"] == "data_set"
              if i == 0
                header = kc.split("\t")
              else
                input = {}
                kc = kc.split("\t")
                header.each.with_index do |h, column_i|
                  input[h] = kc[column_i]
                end
                create_kit_creation(input.to_yaml, @kit_batch.user_id, i)
              end
            elsif !kc.include?("user_id=")
              create_kit_creation(kc, @kit_batch.user_id, i)
            else
              line, line_user = kc.split("user_id=")
              line.strip!
              line_user.strip!
              create_kit_creation(line, line_user, i)
            end
          end
          flash[:success] = "New Kit batch created with #{@kit_batch.kit_creations.count} kit_creations."
          respond_to do |format|
            format.html { redirect_to kit_batch_path(@kit_batch)}
            format.json { render json: { kit_batch: @kit_batch } }
          end
        else
          puts "failed to save #@kit_batch"
          flash[:error] = @kit_batch.errors.full_messages.join(', ')
          respond_to do |format|
            format.html { redirect_back(fallback_location: root_path) }
            format.json { render json: { error: "error creating kit batch" } }
          end
        end
      end
    else
      flash[:error] = "User id invalid. Please enter the user id, not user name."
    end
  end

  def new
    @kit_batch = KitBatch.new
    @creator_options = %w[ KitCreator ]
  end

  private

  def kit_batch_params
    params.require(:kit_batch).permit(:block, :created_by, :name, :user_id, :task_id, :state, :creation_type, :kit_creator, :kit_creations, :ready, :file, :multiples_count, :dual_mode)
  end

  def create_kit_creation(input, user_id, sort_index)
    KitCreation.new(
      input: input,
      kit_batch_id: @kit_batch.id,
      user_id: user_id,
      task_id: @kit_batch.task_id,
      sort_order: sort_index
    ).save
  end
end
