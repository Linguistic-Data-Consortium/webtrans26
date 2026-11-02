module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      set_current_user || reject_unauthorized_connection
    end

    private
      def set_current_user
        session = Session.find_by(id: cookies.signed[:session_id])
        # The same idle limit as an HTTP request (Authentication), or a session
        # that had lapsed there would still open a socket.
        if session && session.updated_at >= Authentication::SESSION_IDLE_TIMEOUT.ago
          self.current_user = session.user
        end
      end
  end
end
