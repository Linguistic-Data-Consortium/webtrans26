# require_relative '../../lib/loggable'

# require_relative '../../lib/ldc/annotation/kit_creator'
class KitBatch < ActiveRecord::Base
  # attr_accessible :user_id, :task_id
  belongs_to :user, optional: true
  belongs_to :task, optional: true
  belongs_to :created_by_user, class_name: 'User', foreign_key: :created_by, optional: true
  has_many :kits
  has_many :kit_creations
  validates :created_by, presence: true
  validates :task_id, presence: true
  validates :name, uniqueness: true, presence: true

  scope :sorted, -> { order('name ASC') }

  # include Loggable

  def user_name
    user ? user.name : ''
  end

  def task_name
    task ? task.name : ''
  end

  def created
    created_by ? created_by_user.name : ''
  end

  attr_reader :file

  def file=(f)
    self.kit_creations = f.read
  end

  def multiples_count
    counts = [@multiples_count, parallel_multiples, sequential_multiples]
    counts.find { |c| c && c > 1 } || 1
  end

  def multiples_count=(c)
    puts "multiples_count=#{c}"
    @multiples_count = c.to_i
    set_dual_mode
  end

  def dual_mode
    if @dual_mode
      @dual_mode
    elsif parallel_multiples && parallel_multiples > 1
      'parallel'
    else
      'sequential'
    end
  end

  def dual_mode=(m)
    puts "dual_mode=#{m}"
    @dual_mode = m
    set_dual_mode
  end

  def assign(task_user)
    update(user_id: task_user.user_id, task_id: task_user.task_id)
    kits.update_all(user_id: task_user.user_id)
  end

  def create_kits
    r = process
    log "kit batch #{id}: #{r}"
    update(ready: false)
  end

  def create_kits2
    r = process2
    logger.info r
    update(ready: false)
    r
  end

  def process
    input = kit_creations
    return "empty input\n" if input.size == 0

    unless creation_type =~ /(document|multi_post|ltf|file|kit|audio|speaker|manifest|data_set)/
      return "couldn't determine type\n"
    end

    type = creation_type

    return "couldn't determine task_id\n" unless task_id

    kc_class = kit_creator

    return "bad kit creator: #{kc_class}\n" unless LDC::Annotation.const_defined? kc_class

    kc_class = LDC::Annotation.const_get kc_class

    begin
      kc = kc_class.new task_id
    rescue StandardError => e
      puts e
      puts e.backtrace
      return "error when creating KitCreator\n"
    end

    kc.state = state || 'unassigned'

    user_id_first = user_id

    kc.created_by = created_by
    kc.log_init 'kits_scanner2.log'
    begin
      kc.process(input:, user_id_first:, type:, task_id:, kc_class:,
                 kb: self)
    rescue KitCreationError => e
      puts e
      puts e.backtrace
      update(message: e.to_s)
    rescue StandardError => e
      puts e
      puts e.backtrace
      input.update_all(status: :failed)
    end
    'done'
  rescue Exception => e
    ([e] + e.backtrace).map(&:to_s).join("\n") + "\n"
  end

  def process2
    input = kit_creations
    return "empty input\n" if input.size == 0

    return "couldn't determine type\n" unless creation_type =~ /(data_set|document|uid)/

    type = creation_type

    return "couldn't determine task_id\n" unless task_id

    kc_class = kit_creator

    return "bad kit creator: #{kc_class}\n" unless LDC::Annotation.const_defined? kc_class

    kc_class = LDC::Annotation.const_get kc_class

    begin
      kc = kc_class.new task_id
    rescue StandardError => e
      puts e
      puts e.backtrace
      return "error when creating KitCreator\n" + e.to_s
    end

    # kc.state = state || 'unassigned'
    kc.state = 'unassigned'

    user_id_first = user_id

    kc.created_by = created_by
    begin
      kc.process(input:, user_id_first:, type:, task_id:, kc_class:,
                 kb: self)
    rescue KitCreationError => e
      puts e
      puts e.backtrace
      update(message: e.to_s)
    rescue StandardError => e
      puts e
      puts e.backtrace
      input.update_all(status: :failed)
    end
    'done'
  rescue Exception => e
    ([e] + e.backtrace).map(&:to_s).join("\n") + "\n"
  end

  private

  def set_dual_mode
    if dual_mode == 'parallel'
      puts "Setting parallel multiples to #{multiples_count}"
      self.parallel_multiples = multiples_count
      self.sequential_multiples = 1
    else
      puts "Setting sequential multiples to #{multiples_count}"
      self.sequential_multiples = multiples_count
      self.parallel_multiples = 1
    end
  end
end
