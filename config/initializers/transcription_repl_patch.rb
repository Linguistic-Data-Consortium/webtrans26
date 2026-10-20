# Monkey-patch for the transcription REPL harness (script/transcription_repl.rb).
#
# When `TRANSCRIPTION_REPL=1` is set in the env, this initializer wraps
# `TaskUsersController#kit_source_helper` so that any kit whose `source[:uid]` points at a
# static asset under `public/` (e.g. `/test_tone_10s.wav`) gets a manifest pointing back at
# that same static URL. This avoids needing Active Storage / S3 just to play a test audio
# file when manually exploring the transcription tool.
#
# The patch is fully gated on the env var — production and normal dev runs are untouched.
return unless ENV["TRANSCRIPTION_REPL"] == "1"

module TranscriptionReplKitSourceHelperPatch
  def kit_source_helper
    super
    uid = @kit&.source.is_a?(Hash) ? (@kit.source[:uid] || @kit.source["uid"]) : nil
    return unless uid

    relative = uid.sub(%r{\A/}, "")
    return unless File.exist?(Rails.root.join("public", relative))

    @manifest = { urls: { uid => "/#{relative}" } }
  end
end

Rails.application.config.to_prepare do
  unless TaskUsersController.ancestors.include?(TranscriptionReplKitSourceHelperPatch)
    TaskUsersController.prepend(TranscriptionReplKitSourceHelperPatch)
    Rails.logger.info "[transcription-repl] TaskUsersController#kit_source_helper patched"
  end
end
