class ClassDef < ApplicationRecord
  validates(
    :name,
    :presence => true,
    :uniqueness => { :case_sensitive => false },
    :length => { :maximum => 50 }
  )
  scope :sorted, -> { order('name ASC') }

  def basic_info
    o = { classes: {} }
    NodeList.where(class_def_id: id).each do |x|
      o[:classes][x.name] = { children: x.children.split }
    end
    {
      class_def_id: id,
      name: name,
      original_id: original_id,
      def: o.to_json
    }
  end

  def new_root
    tree = Tree.new
    tree.class_def_id = id
    update(original_id: id) unless original_id
    tree.version = original_id
    tree.assign_id
    tree.last_iid = 0;
    tree.save!
    tree
  end

  def show_create_tables
    @views = {}
    create_tables_helper
    @views.each do |k, v|
      puts v
    end
    nil
  end

  def create_tables_helper
    NodeList.where(class_def_id: id).each do |x|
      dolistitem_t(x.name, x.children.split)
    end
  end

  def create_tables
    @views = {}
    create_tables_helper
    @views.each do |k, v|
      #puts db.fetch("select * from  #{k};").to_a
      #vv = v.sub(/create.+/,'')
      puts k
      self.class.connection.execute v
    end
    nil
    # puts db.fetch("SHOW FULL TABLES IN rails_production  WHERE TABLE_TYPE LIKE 'VIEW';").to_a
  end

  def create_specific_table(t)
    @views = {}
    create_tables_helper
    @views.each do |k, v|
      #puts db.fetch("select * from  #{k};").to_a
      #vv = v.sub(/create.+/,'')
      puts k
      return self.class.connection.execute(v).to_a.to_s if k == t
    end
    nil
    # puts db.fetch("SHOW FULL TABLES IN rails_production  WHERE TABLE_TYPE LIKE 'VIEW';").to_a
  end

  def show_drop_tables
    @views = {}
    create_tables_helper
    @views.each do |k, v|
      #puts db.fetch("select * from  #{k};").to_a
      #vv = v.sub(/create.+/,'')
      next if k =~ /_index\z/
      # puts k
      v =~ /create table "(\w+)/
      puts "drop view if exists #$1"
      puts "drop table if exists #$1"
    end
    nil
    # puts db.fetch("SHOW FULL TABLES IN rails_production  WHERE TABLE_TYPE LIKE 'VIEW';").to_a
  end

  def drop_tables
    @views = {}
    create_tables_helper
    @views.each do |k, v|
      #puts db.fetch("select * from  #{k};").to_a
      #vv = v.sub(/create.+/,'')
      next if k =~ /_index\z/
      # puts k
      if v =~ /create table "(\w+)/
        table_name = $1
        # Sanitize table name - only allow alphanumeric and underscore
        if table_name =~ /\A[a-zA-Z0-9_]+\z/
          # self.class.connection.execute "drop view if exists #{self.class.connection.quote_table_name(table_name)}"
          self.class.connection.execute "drop table if exists #{self.class.connection.quote_table_name(table_name)}"
        else
          Rails.logger.warn "Attempted to drop table with invalid name: #{table_name}"
        end
      end
    end
    nil
    # puts db.fetch("SHOW FULL TABLES IN rails_production  WHERE TABLE_TYPE LIKE 'VIEW';").to_a
  end

  def dolistitem_t(n, v)
    query = query_hash
    # query['select'] << 'trees.id as tree_id'
    # if ppncid
      query['select'] << 'tree_id int'
      query['select'] << 'iid int'
      # n = k.split(':').last
      # query['select'] << "#{n}_iid int"
      nn_index = ", iid"
    # else
    #   query['select'] << 'tree_id int'
    # end
    # ncs = []
    v.each_with_index do |n, i|
      # kk, vv = kkvv
      # n = kk.split(':').last
      query['select'] << "\"#{n}_iid\" int"
      # ncs << @grammar[kk][:id]
      unless false #@grammar[kk][:parent_id] == 3
        if false #docid_only(kk)
          query['select'] << "#{n}_docid varchar(255)"
        # elsif @grammar[kk][:parent_id] == 2629
        #   query['select'] << "#{n}_docid varchar(255)"
        #   query['select'] << "#{n}_beg float(10,3)"
        #   query['select'] << "#{n}_end float(10,3)"
        #   query['select'] << "#{n}_play_head float(10,3)"
        # elsif @grammar[kk][:parent_id] == 5
        #   query['select'] << "#{n}_docid varchar(255)"
        #   query['select'] << "#{n}_beg int"
        #   query['select'] << "#{n}_end int"
        #   query['select'] << "#{n}_text text"
        # elsif media_provenance(kk)
        #   query['select'] << "#{n}_docid varchar(255)"
        #   query['select'] << "#{n}_begr float(10,3)"
        #   query['select'] << "#{n}_endr float(10,3)"
        #   query['select'] << "#{n}_begi int"
        #   query['select'] << "#{n}_endi int"
        #   query['select'] << "#{n}_text text"
        #   query['select'] << "#{n}_points varchar(255)"
        #   query['select'] << "#{n}_type varchar(255)"
        # elsif @grammar[kk][:id] == 9385
        #   query['select'] << "#{n}_kb_id varchar(255)"
        #   query['select'] << "#{n}_mention_id varchar(255)"
        else
          query['select'] << "\"#{n}_value\" text"
        end
      end
    end
    view_name = name + n
    @views[view_name] =  "create table \"#{view_name}\" (\n" + t_query_helper(query) + "\n) #{default_character_set}\n"
    index_name = "#{view_name}_index"
    @views[index_name] =  "create index \"#{index_name}\" on \"#{view_name}\" (tree_id" + ( view_name =~ /Root\w?\z/ ? '' : nn_index ) + ')'
  end

  def t_query_helper(query)
    query['select'].join(",\n")
  end

  def query_hash
    {
      'select' => [],
      'from' => '',
      'join' => [],
      'where' => [],
      'order' => []
    }
  end

  def default_character_set
    # "default character set utf8 collate utf8_unicode_ci"
    ''
  end

end
