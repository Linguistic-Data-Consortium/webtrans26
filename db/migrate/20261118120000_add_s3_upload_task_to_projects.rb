# The task whose members may write to the project's S3 prefix
# (aws/s3_project_prefixes.md). Membership of a task is granted by a task or
# project admin, so writing needs someone with that standing to say so — but
# the permission is the membership, not a role.
#
# Nullable: a project with no upload task is one nobody can write to, which is
# the safe reading. Nullified rather than cascaded when the task goes, so
# deleting the task revokes write access and leaves the project alone.
class AddS3UploadTaskToProjects < ActiveRecord::Migration[8.1]
  def change
    add_reference :projects, :s3_upload_task, foreign_key: { to_table: :tasks, on_delete: :nullify }, null: true
  end
end
