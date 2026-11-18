# The session policy for a user's S3 session — aws/s3_project_prefixes.md.
#
# S3SessionsController assumes one role whose own policy reads and writes the
# whole bucket, and passes this document as the session policy. The effective
# permission is the intersection, so this is the actual grant and the role is
# only the ceiling: a mistake here can narrow access further, never widen it
# past the role.
#
# A plain object so the document can be asserted as data without a network
# call. Prefixes are project ids; nothing here comes from the request.
class S3SessionPolicy
  attr_reader :bucket, :read_ids, :write_ids

  def initialize(user, bucket: Rails.application.config.x.s3_bucket)
    @bucket = bucket
    # Integer() before anything reaches an ARN. These come from the database,
    # not the request, but interpolating an uncast value into a policy document
    # is the shape of an injection and this rules it out for the price of a call.
    @read_ids = user.s3_read_project_ids.map { |id| Integer(id) }
    # A subset of the read set by construction — write is never computed
    # independently of read.
    @write_ids = user.s3_write_project_ids.map { |id| Integer(id) } & @read_ids
  end

  # No projects means no session at all: the controller answers 403 rather than
  # handing a browser a credential that can do nothing.
  def empty?
    read_ids.empty?
  end

  def to_h
    statements = [
      { Sid: "Read", Effect: "Allow", Action: [ "s3:GetObject" ],
        Resource: read_ids.map { |id| object_arn(id) } }
    ]
    # Omitted rather than emitted empty: a statement with no resources is
    # rejected by STS as malformed.
    unless write_ids.empty?
      # No s3:DeleteObject. Writers who may not delete is the stricter reading,
      # and the spec leaves it open.
      statements << { Sid: "Write", Effect: "Allow", Action: [ "s3:PutObject" ],
                      Resource: write_ids.map { |id| object_arn(id) } }
    end
    # ListBucket is a bucket-level action, so it is scoped by a condition on
    # the prefix rather than by the resource. Without the condition this would
    # list the whole bucket; scoping the resource instead would deny all
    # listing.
    statements << { Sid: "List", Effect: "Allow", Action: [ "s3:ListBucket" ],
                    Resource: "arn:aws:s3:::#{bucket}",
                    Condition: { StringLike: { "s3:prefix" => read_ids.map { |id| "#{id}/*" } } } }
    { Version: "2012-10-17", Statement: statements }
  end

  def to_json(*)
    to_h.to_json
  end

  private

  def object_arn(id)
    "arn:aws:s3:::#{bucket}/#{id}/*"
  end
end
