# The security audit log (SecurityEvent), for system admins: newest first, 100
# a page, filtered by event, by user (name or email address) and by date, and
# as CSV for handing on.
class SecurityEventsController < ApplicationController
  before_action :admin_user
  PER_PAGE = 100

  def index
    @events = SecurityEvent.newest_first.includes(:user, :actor)
    @events = @events.where(event: params[:event]) if SecurityEvent::EVENTS.key?(params[:event])
    if params[:user].present?
      term = params[:user].to_s.strip.downcase
      ids = User.where("lower(name) = :t OR lower(email_address) = :t", t: term).pluck(:id)
      @events = @events.where(user_id: ids).or(@events.where(actor_id: ids))
    end
    @events = @events.where(created_at: Date.parse(params[:from]).beginning_of_day..) if date?(params[:from])
    @events = @events.where(created_at: ..Date.parse(params[:to]).end_of_day) if date?(params[:to])

    respond_to do |format|
      format.html do
        @page = [ params[:page].to_i, 1 ].max
        @total = @events.count
        @events = @events.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
      end
      format.csv do
        send_data csv(@events), type: "text/csv", filename: "security-events-#{Date.current}.csv"
      end
    end
  end

  private

  def date?(value)
    value.present? && Date.parse(value.to_s)
  rescue Date::Error
    false
  end

  def csv(events)
    require "csv"
    CSV.generate do |out|
      out << %w[ time event description user_id user_email actor_id actor_email ip user_agent details ]
      events.reorder(:id).find_each do |e| # oldest first: an export reads as a timeline
        out << [ e.created_at.utc.iso8601, e.event, e.description, e.user_id, e.user&.email_address,
                 e.actor_id, e.actor&.email_address, e.ip, e.user_agent, e.details&.to_json ]
      end
    end
  end
end
