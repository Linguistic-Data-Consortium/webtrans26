# Reference data required for the application to function in every
# environment. Idempotent — every block uses find_or_create / first_or_create
# so it can be re-run safely. Run via `bin/rails db:seed` (also auto-loaded
# for the repl env on first bootstrap by script/transcription_repl_lib.rb).
#
# Was split between this file and config/ua.rb (driven by ua.config) until
# the boot-time ua.rb hook was removed; everything is consolidated here now.

# ── Annotation id=0 ────────────────────────────────────────────────────
# Node rows that aren't the root of an `add` message group are written by
# Annotation#apply with annotation_id=0; they FK to this placeholder row.
Annotation.where(id: 0).first_or_create

# ── Base NodeClasses ───────────────────────────────────────────────────
# Reference types referenced by `parent:` on the ClassDef-specific NodeClasses
# below (`parent: Root`, `parent: NodeList`, …).
%w[
  Leaf Root Node NodeList Text Label Date Gaz children Button Checkbox
  EmbeddedList Tabs TextSource TextSearch MultiMenu CustomText Audio Coref
  CorpusSearch Table EntryLabel ToggleButton Audio2 Message TextSource2
  ChoiceLabel Wave Upload Download ButtonGroupRadio Blob Media Image
].each { |name| NodeClass.where(name: name).first_or_create }

# ── Workflows ──────────────────────────────────────────────────────────
# tasks_controller#show calls workflow.user_states.split(',') so this column
# must be set, otherwise NoMethodError on nil.
Workflow.where(name: "OnTheFly").first_or_create.update!(user_states: "needs_kit,has_kit")
Workflow.where(name: "Orderly" ).first_or_create.update!(user_states: "needs_kit,has_kit")

# ── ClassDefs and project-specific NodeClasses ─────────────────────────
# Each ClassDef declares the NodeClass subgraph below its <ClassDef>:Root.
# Children are short-form ('Arc Text Speaker') and get expanded to the
# qualified form NodeClass#create_children expects:
#   'Arc.<ClassDef>:Arc,Text.<ClassDef>:Text,...'
class_def_data = [
  { name: "SimpleTranscription", node_classes: [
    { name: "SimpleTranscription:Root", parent: "Root" },
  ] },
  { name: "ArcTranscription", node_classes: [
    { name: "ArcTranscription:Root", parent: "Root" },
    { name: "SegmentList", parent: "NodeList", children: "Arc Text Speaker" },
    { name: "SectionList", parent: "NodeList", children: "Arc Name" },
    { name: "NList",       parent: "NodeList", children: "N" },
  ] },
]
class_def_data.each do |cd_spec|
  cd = ClassDef.where(name: cd_spec[:name]).first_or_create
  cd_spec[:node_classes].each do |nc_spec|
    nc = NodeClass.where(name: nc_spec[:name]).first_or_create
    children = nc_spec[:children]
    if children && children !~ /\./
      children = children.split.map { |c| "#{c}.#{cd_spec[:name]}:#{c}" }.join(",")
    end
    nc.update(
      class_def_id: cd.id,
      parent_id: NodeClass.find_by_name(nc_spec[:parent])&.id,
      children: children,
    )
  end
end

# ── Kit type features ──────────────────────────────────────────────────
# The constraints a project manager can switch on for a kit type. The list
# lives on the model, so `bin/rails features:seed` can create them on a
# database this file shouldn't be run against wholesale.
Feature.seed_kit_type!

# ── Default Project / Task / KitType ───────────────────────────────────
# The canonical Transcription task pointing at ArcTranscription:Root.
default_project = Project.where(name: "Transcription").first_or_create
default_kit_type = KitType.where(name: "Transcription").first_or_create
default_kit_type.update!(
  javascript: "empty",
  node_class_id: NodeClass.where(name: "ArcTranscription:Root").pluck(:id).first,
  constraints: { "web_audio" => "web_audio", "show_source" => "show_source", "free_choice" => "free_choice" },
)
Task.where(
  project_id: default_project.id,
  name: "Transcription",
  workflow_id: Workflow.find_by_name("Orderly").id,
  kit_type_id: default_kit_type.id,
).first_or_create
