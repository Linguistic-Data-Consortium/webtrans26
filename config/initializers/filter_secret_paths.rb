# Some links carry their secret in the path, not the query string:
#
#   /access/:id/:token               one-time sign-in link
#   /passwords/:token/edit           emailed password reset
#   /invites/:token[/edit]           invitation
#   /account_activations/:token/edit activation
#
# filter_parameters hides the token in the "Parameters:" line, but the
# "Started GET ..." line is written from request.filtered_path, which filters
# only the query string, so every one of these was logged whole. This masks the
# secret segment there. (A proxy in front of the app keeps its own logs, which
# this can't reach; see PasswordsController#edit for keeping the reset token out
# of every URL after the first.)
module FilterSecretPaths
  SECRET_SEGMENTS = [
    %r{\A(/access/\d+/)[^/?]+},
    %r{\A(/passwords/)(?!new\b|reset\b)[^/?]+},
    %r{\A(/invites/)(?!new\b)[^/?]+},
    %r{\A(/account_activations/)[^/?]+}
  ].freeze

  def filtered_path
    @filtered_secret_path ||= SECRET_SEGMENTS.reduce(super) { |path, re| path.sub(re, '\1[FILTERED]') }
  end
end

ActionDispatch::Request.prepend FilterSecretPaths
