#!/usr/bin/env ruby
# Generates a 10-second 1 kHz sine-wave WAV file for use as a test fixture.
# Format: 16 kHz mono, 16-bit PCM, little-endian. ~320 KB file.
#
# Re-run with: `ruby test/fixtures/files/generate_test_tone.rb`

require "fileutils"

OUTPUT      = File.expand_path("test_tone_10s.wav", __dir__)
SAMPLE_RATE = 16_000   # 16 kHz
DURATION    = 10       # seconds
FREQUENCY   = 1_000    # 1 kHz tone (standard line-up reference)
AMPLITUDE   = 0.3      # ~ -10 dBFS, comfortably below clipping

num_samples = SAMPLE_RATE * DURATION
data_size   = num_samples * 2 # 16-bit mono = 2 bytes per sample

# Generate the sine samples and pack as 16-bit signed little-endian.
samples = Array.new(num_samples) do |i|
  t = i.to_f / SAMPLE_RATE
  (Math.sin(2 * Math::PI * FREQUENCY * t) * AMPLITUDE * 32_767).round
end
sample_bytes = samples.pack("s<*")

# WAV/RIFF header for PCM mono.
header = +"".b
header << "RIFF"
header << [36 + data_size].pack("V")    # ChunkSize  (file size - 8)
header << "WAVE"
header << "fmt "
header << [16].pack("V")                # Subchunk1Size (16 for PCM)
header << [1].pack("v")                 # AudioFormat   (1 = PCM)
header << [1].pack("v")                 # NumChannels   (mono)
header << [SAMPLE_RATE].pack("V")       # SampleRate
header << [SAMPLE_RATE * 2].pack("V")   # ByteRate      (rate * channels * bytes/sample)
header << [2].pack("v")                 # BlockAlign    (channels * bytes/sample)
header << [16].pack("v")                # BitsPerSample
header << "data"
header << [data_size].pack("V")         # Subchunk2Size

File.binwrite(OUTPUT, header + sample_bytes)
puts "wrote #{OUTPUT} (#{File.size(OUTPUT)} bytes, #{DURATION}s @ #{SAMPLE_RATE} Hz, #{FREQUENCY} Hz tone)"
