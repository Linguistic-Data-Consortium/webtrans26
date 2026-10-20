# Copying one production task into the development database, so it can be
# opened, read and debugged locally.
#
#   bin/rails task:pull TASK_ID=42        # export on production, import here
#   bin/rails task:pull TASK_ID=42 REPLACE=1   # …over a copy already here
#   bin/rails task:export TASK_ID=42 > t.json  # just the dump
#   bin/rails task:import FILE=t.json          # just the load
#
# `pull` runs the export through `kamal app exec`, the same way kits.rake
# already reaches production, and loads what comes back. The halves are
# separate because the export has to run where the data is and the import where
# it's wanted — and because a dump someone hands you should load the same way.
#
# TaskTransfer is what they all call; what it carries and what it leaves behind
# is written down there.

namespace :task do
  desc "Dump one task and everything it needs as JSON (TASK_ID=n)"
  task export: :environment do
    task_id = Integer(ENV["TASK_ID"] || abort("TASK_ID= is required"))
    dump = begin
      TaskTransfer.export(task_id)
    rescue TaskTransfer::Refused => e
      abort e.message
    end

    # The dump goes to stdout so it can be piped or redirected; the summary goes
    # to stderr so it doesn't end up in the file.
    $stdout.puts JSON.generate(dump)
    warn "exported task #{task_id} (#{dump['task_name']}): #{TaskTransfer.summarise(dump)}"
  end

  desc "Load a dump into this database (FILE=t.json, REPLACE=1 to overwrite)"
  task import: :environment do
    path = ENV["FILE"] || abort("FILE= is required")
    abort "no such file: #{path}" unless File.exist?(path)
    load_dump(JSON.parse(File.read(path)), from: path)
  end

  desc "Export a task on production and import it here (TASK_ID=n, REPLACE=1, DEST=path)"
  task pull: :environment do
    require "open3"

    task_id = Integer(ENV["TASK_ID"] || abort("TASK_ID= is required"))
    unless Rails.env.development?
      abort "task:pull loads production data into development, not into #{Rails.env}"
    end

    dest = Pathname.new(ENV["DEST"] || Rails.root.join("tmp", "task-#{task_id}.json"))
    dest.dirname.mkpath

    # REMOTE_CMD is the escape hatch for a server reached some other way.
    remote = ENV["REMOTE_CMD"] || "bin/rails task:export TASK_ID=#{task_id}"
    command = [ "kamal", "app", "exec", "-q", "--reuse", remote ]
    warn "==> #{command.join(' ')}"

    out, err, status = Open3.capture3(*command)
    unless status.success?
      warn err
      abort "kamal exited #{status.exitstatus} — is it configured, and can you reach the server?"
    end

    # -q keeps kamal quiet, but it is still a wrapper: if anything of its own
    # reached stdout, the parse is where we find out, and the start of what
    # actually came back says more than "unexpected token".
    json = out.strip
    dump = begin
      JSON.parse(json)
    rescue JSON::ParserError => e
      warn err unless err.strip.empty?
      abort "what came back from kamal isn't a dump (#{e.message}):\n#{json[0, 300]}"
    end

    dest.write(json)
    warn "==> wrote #{dest} (#{(json.bytesize / 1024.0).round} KB)"
    warn err.strip unless err.strip.empty? # the remote export's own summary
    load_dump(dump, from: dest.to_s)
  end

  def load_dump(dump, from:)
    counts = TaskTransfer.import(dump, replace: ENV["REPLACE"].present?)
    warn "imported task #{dump['task_id']} (#{dump['task_name']}) from #{from}:"
    warn "  " + counts.map { |table, n| "#{n} #{table}" }.join(", ")
    warn "  graph_* and segments/sections are projections and rebuild on demand"
  rescue TaskTransfer::Refused => e
    # The model doesn't know it was reached from a command line; the way to say
    # yes to it from here is worth saying.
    hint = "\n  REPLACE=1 to overwrite it" if e.message.include?("already in") && ENV["REPLACE"].blank?
    abort "#{e.message}#{hint}"
  end
end
