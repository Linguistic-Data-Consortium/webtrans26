class GuideChannel < ApplicationCable::Channel
  def subscribed
    return if params[:gname].nil?
    @guide = Guide.where(user_id: current_user.id, name: params[:gname]).first_or_create
    stream_for @guide
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end

  def get()
    data = @guide.to_json
    data = data.gsub(/\}$/,",\"inactive_for\":\"#{Time.zone.now-(@guide.updated_at||10.years.ago)}\"}")
    broadcast_to(@guide, data)
  end

  def update(data)
    @guide.update(data.except("action")) if data
    @guide.update_attribute("updated_at", Time.zone.now);
  end

  def complete
    @guide.update_attribute("complete", true)
  end
end
