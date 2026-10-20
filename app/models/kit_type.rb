
# == Schema Information
#
# Table name: kit_types
#
#  id                :integer          not null, primary key
#  name              :string(255)
#  node_class_id     :integer
#  source_id         :integer
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  config_id         :integer
#  type              :string(255)
#  meta              :text
#  annotation_set_id :integer
#

class KitType < ActiveRecord::Base

  # attr_accessible :name, :node_class_id, :source_id, :config_id, :meta, :annotation_set_id
  serialize :meta, type: Hash
  serialize :constraints, type: Hash
  belongs_to :node_class
  has_many :kits
  # belongs_to :annotation_set, class_name: 'LDC::Annotation::AnnotationSet'
  # NOTE: removed `has_many :kit_type_packages, dependent: :destroy` and `has_many :packages,
  # through: :kit_type_packages` — neither the KitTypePackage model nor the Package model
  # exists in app/models, so the association was unloadable and broke every KitType destroy
  # with `NameError: Missing model class KitTypePackage`. Restore them once the models land.

  scope :sorted, -> { order('created_at DESC') }
  scope :all_newest_first, -> { order('created_at DESC') }

  def class_def
    node_class.class_def
  end

  def composite_name
    "#{id}:#{name}"
  end

  def new_kit_meta(kit, root)
    # if kit.empty_list
    #   kit.empty_list.each do |path|
    #     root.find_node_in_children_by_path(path).tree_empty_node if root.find_node_in_children_by_path(path)
    #   end
    # end
    # if kit.coref_groups and kit.coref_groups.count > 0
    #   kit.coref_groups.each do |group|
    #     root.coref.add_group group
    #   end
    #   @tree.save_coref
    # end
  end
  
  def new_root_helper(kit)
    km = KitValue.where(kit_id: kit.id, key: :root).first_or_create
    km.update(value: kit.class_def.name) if km.value.nil?
    km = KitValue.where(kit_id: kit.id, key: :source_uid).first_or_create
    km.update(value: "NYT_ENG_19940701.0001") if km.value.nil?
    km = KitValue.where(kit_id: kit.id, key: :source_type).first_or_create
    km.update(value: "document") if km.value.nil?
  end

  #creates a new tree using LDCI NodeClasses, originating from the Namespace
  def new_root(kit, task_user)
    new_root_helper kit
    class_def = kit.class_def
    @tree = class_def.new_root

    json = { messages: [ { message: 'new' } ] }

    # case class_def.name
    # when 'CaceTopicDev'
    #   json[:messages] << { node: '7', message: 'add', value: 7975 }
    # end
    # g = class_def.inverted_grammar
    create_with_json(task_user, kit, @tree, json)
    return @tree
  end

  def new_root2(kit:, task_user:, journals:)
    new_root_helper kit
    class_def = kit.class_def
    @tree = class_def.new_root

    journals.each do |j|
      create_with_json2(task_user, kit, @tree, j)
    end

    return @tree

  end

  def create_with_json(task_user, kit, tree, json)
    class_def = kit.class_def
    Annotation.create(
      user_id: task_user.user_id,
      task_id: task_user.task_id,
      kit_id: kit.id,
      tree_id: tree.id,
      last_iid: 0,
      message: 'new'
    )
  end

  def create_with_json2(task_user, kit, tree, j)
    class_def = kit.class_def
    Annotation.create(
      user_id: task_user.user_id,
      task_id: task_user.task_id,
      kit_id: kit.id,
      tree_id: tree.id,
      last_iid: 0,
      message: 'new'
    )
  end

  #offers a way to specify a JSON file with the kits specified and generate kits from that
  def kit_generation_options(task)
    tabs = Array.new
    options = Array.new

    #filename needed in kit_generation_options, generate_kits_from_options and tasks_controller.
    fileprefix = Rails.application.config.public_path
    publicpath = "#{fileprefix}/#{task.project_name}/#{task.name}"

    FileUtils.mkdir_p publicpath if !Dir.exists? publicpath
    myDir = Dir.open publicpath

    files_available = [];
    myDir.each do |filename|
      if(not File.directory? "#{publicpath}/#{filename}" and not filename =~ /\.Zap\S+/)
        files_available << filename
      end
    end

    options << {:type => "select", :label => "Select an existing kit JSON file.", :options => files_available}
    options << {:type => "file-upload", :label => "Add a new kit JSON file."}
    tabs << {:label => "Load kits from file", :options => options}

    tabs
  end

  # Actually an array of kits from the chosen options for user to preview and choose.
  def generate_kits_from_options(task, options, remember_token)
    selection = options["Select an existing kit JSON file."]

    #filename needed in kit_generation_options, generate_kits_from_options and tasks_controller.
    #Maybe it should be part of the task? How to do that?
    fileprefix = Rails.application.config.public_path #"#{File.expand_path('.')}/docs"
    publicpath = "#{fileprefix}/#{task.project.name}/#{task.name}"

    if(selection and not selection.empty?)
      serverFileName = "#{publicpath}/#{selection}"
    else
      return {:kits => Array.new, :preview => Array.new}
    end

    kits = Array.new
    preview = [:label =>  "File Path: #{serverFileName.sub("#{fileprefix}/", '')}"]
    File.open(serverFileName).each_with_index do |str, idx|
      kit_info = JSON.parse str
      kit =  {
        'task_id' => task.id,
        'kit_type_id' => task.kit_type_id,
        'json_id' => idx,
      }
      kit_info.each do |key, value|
        kit[key] = value
      end

      kits << kit
    end
    {:kits => kits, :preview => preview}
  end

  #returns a list to be used in the view for type selection when creating new kit types
  def types
    types = Array.new
    Dir['app/models/kit_types/*.rb'].each do |file|
      filestem = file.gsub('.rb', '').gsub('app/models/kit_types/', '')
      types << "KitTypes::#{filestem.camelize}"
    end
    types.sort
  end


end
