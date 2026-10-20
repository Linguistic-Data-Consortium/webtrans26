module KitTypesHelper
  def js_files
    jsfiles = Array.new
    Dir['app/assets/javascripts/workflows/*.js'].each do |file|
      jsfiles << file.gsub('.js', '').gsub('app/assets/javascripts/workflows/', '')
    end
    Dir['app/assets/javascripts/workflows/*.coffee'].each do |file|
      jsfiles << file.gsub('.js.coffee', '').gsub('app/assets/javascripts/workflows/', '')
    end
    jsfiles.sort!#list of possibilities for meta['js']
  end
  
  def template_files
    templates = Array.new
    Dir['app/views/kit_types/kit_type/*.haml'].each do |file|
      templates << file.gsub('.js', '').gsub('app/views/kit_types/kit_type/', '')
    end
    templates.sort!#list of possibilities for meta['template']
  end
end
