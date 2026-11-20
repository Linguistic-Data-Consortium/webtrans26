# The task whose members may use the download features for the project's work
# (Project#may_download?): transcript downloads and table exports. Like the S3
# upload task beside it, membership is the permission, granted by a task or
# project admin.
#
# Nullable, and none by default: then only system admins can download. Nullified
# when the task goes, so deleting it revokes the permission and leaves the
# project alone.
class AddDownloadTaskToProjects < ActiveRecord::Migration[8.1]
  def change
    add_reference :projects, :download_task, foreign_key: { to_table: :tasks, on_delete: :nullify }, null: true
  end
end
