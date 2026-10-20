require "test_helper"

# The kit type features are what the admin UI offers a project manager. They're
# rows, so a new one has to be created on every database that already exists —
# deploying migrates but doesn't seed. Feature.seed_kit_type! is what does that,
# and it has to be safe to run on a live one.
class FeatureTest < ActiveSupport::TestCase
  test "it creates the features the admin UI offers" do
    Feature.where(category: "kit_type").delete_all

    names = Feature.seed_kit_type!.map(&:name)

    assert_includes names, "comments"
    assert_includes names, "transcribe_text_only"
    assert_equal names.sort, Feature.where(category: "kit_type").pluck(:name).sort
  end

  test "running it again changes nothing" do
    Feature.seed_kit_type!
    before = Feature.where(category: "kit_type").order(:name).pluck(:name, :value, :label)

    assert_no_difference -> { Feature.count } do
      Feature.seed_kit_type!
    end
    assert_equal before, Feature.where(category: "kit_type").order(:name).pluck(:name, :value, :label)
  end

  test "a feature whose value is its name is a checkbox; one with another value is a text box" do
    Feature.seed_kit_type!

    assert_equal "comments", Feature.find_by(name: "comments").value,
      "value == name, so the admin UI renders a checkbox"
    assert_equal "reference", Feature.find_by(name: "transcribe_text_only").value,
      "value != name, so it renders a text box and what's typed becomes the tier"
  end

  test "it leaves everything else alone" do
    class_def = ClassDef.where(name: "ArcTranscription").first_or_create!
    root = NodeClass.where(name: "ArcTranscription:Root").first_or_create!(class_def: class_def)
    kit_type = KitType.create!(name: "untouched-#{SecureRandom.hex(3)}", node_class: root)
    kit_type.update!(constraints: { "comments" => "comments" })

    Feature.seed_kit_type!

    assert_equal({ "comments" => "comments" }, kit_type.reload.constraints,
      "a kit type's own constraints aren't the seed's business")
  end
end
