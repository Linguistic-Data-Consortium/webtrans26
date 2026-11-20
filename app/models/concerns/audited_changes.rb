# Creating, changing or deleting one of these goes in the security log
# (SecurityEvent) under the model's audit_event, naming the record and, for a
# change, which fields changed (not their values: a kit type's meta can be
# large). For configuration everyone's work depends on: kit types, features,
# workflows.
module AuditedChanges
  extend ActiveSupport::Concern

  IGNORED = %w[ created_at updated_at ].freeze

  included do
    class_attribute :audit_event
    after_create  { audit_change("created") }
    after_update do
      fields = saved_changes.keys - IGNORED
      audit_change("updated", fields: fields) if fields.any?
    end
    after_destroy { audit_change("deleted") }
  end

  private

  def audit_change(action, fields: nil)
    SecurityEvent.record(audit_event, action: action, id: id, name: try(:name), fields: fields)
  end
end
