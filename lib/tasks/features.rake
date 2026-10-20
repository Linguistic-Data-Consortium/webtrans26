# The kit type features the admin UI offers — the checkboxes and text boxes a
# project manager uses to switch a constraint on for a kit type.
#
# Separate from db:seed on purpose. Deploying runs db:prepare, which migrates
# but only seeds a database it had to create, so a new feature never reaches an
# existing production database on its own. db:seed would bring it — along with
# a reset of the canonical Transcription kit type's constraints, which is not
# something to do to a live one.
#
#   bin/rails features:seed
#   kamal app exec -q --reuse 'bin/rails features:seed'
namespace :features do
  desc "Create the kit type features the admin UI offers, refreshing labels (safe on a live database)"
  task seed: :environment do
    before = Feature.where(category: "kit_type").pluck(:name)
    rows = Feature.seed_kit_type!
    added = rows.map(&:name) - before
    puts "kit type features: #{rows.size} (#{added.any? ? "added #{added.join(', ')}" : 'nothing new'})"
    rows.each { |f| puts "  #{f.name.ljust(24)} #{f.value == f.name ? '[checkbox]' : "[text, default #{f.value}]"}" }
  end

  desc "List the kit type features and which kit types use them"
  task list: :environment do
    Feature.where(category: "kit_type").sorted.each do |f|
      users = KitType.all.select { |kt| kt.constraints&.key?(f.name) }
      puts "#{f.name.ljust(24)} #{users.any? ? users.map { |kt| "#{kt.id}:#{kt.name}=#{kt.constraints[f.name]}" }.join(' ') : '(unused)'}"
    end
  end
end
