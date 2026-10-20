class Feature < ApplicationRecord
  validates( :name, :presence => true,
  :uniqueness => { :case_sensitive => false })

  scope :sorted, -> { order('name ASC') }

  # The constraints a project manager can switch on for a kit type, in the
  # admin UI. A feature whose value equals its name renders as a checkbox; one
  # with a different value renders as a text box, and whatever is typed becomes
  # the constraint's value.
  KIT_TYPE = [
    { name: "import_transcript_auto", value: "import_transcript_auto",
      label: "Import Transcript Automatically",
      description: "Open the Upload Transcript dialog when a fresh kit loads." },
    { name: "import_transcript_blanks", value: "import_transcript_blanks",
      label: "Import Transcript as Blanks",
      description: "Add an empty segment per reference segment, with the reference shown above it." },
    { name: "comments", value: "comments",
      label: "Comments",
      description: "Let the annotator attach a remark to a stretch of audio. Comments are their own " \
                   "list — one span, one label — and no transcript export includes them. Allowed " \
                   "even where the transcript itself is locked." },
    { name: "asr_range", value: "asr_range",
      label: "Ask for a Time Range Before ASR",
      description: "Choosing an ASR service asks which stretch of audio it may fill, and only " \
                   "segments that fit entirely inside that stretch are added. Off, a run adds " \
                   "the whole transcript the service returns, which on a long recording is " \
                   "thousands of segments." },
    { name: "transcribe_text_only", value: "reference",
      label: "Transcribe Imported Segments (text only)",
      description: "Transcribe against an imported graph matched to this kit's audio: its spans " \
                   "become the segments and the captions above them, and only their text can be " \
                   "edited — no times, no splitting or merging, no speaker or section. The value " \
                   "names which tier to read (reference, asr, …); blank means reference." }
  ].freeze

  # Create the rows the admin UI offers, refreshing the label and description
  # of any that are already there. Touches nothing else, which is why it can be
  # run on a live database — unlike db:seed, which also resets the canonical
  # Transcription kit type's constraints to what this repo thinks they are.
  #
  #   bin/rails features:seed
  def self.seed_kit_type!
    KIT_TYPE.map do |feature|
      row = where(category: "kit_type", name: feature[:name]).first_or_create
      row.update!(value: feature[:value], label: feature[:label], description: feature[:description])
      row
    end
  end
end
