class ConversionResult
  attr_reader :input_path, :outputs, :options, :logs, :timings

  def initialize(input_path:, options:)
    @input_path = input_path
    @options = options
    @outputs = []
    @logs = []
    @timings = {
      channels: []
    }
  end

  def add_outputs(items)
    @outputs.concat(items)
  end

  def add_logs(text)
    return if text.nil? || text.empty?

    @logs.concat(text.lines.map(&:chomp))
  end

  def add_channel_timing(timing)
    @timings[:channels] << timing
  end

  def set_total_seconds(seconds)
    @timings[:total_seconds] = round_seconds(seconds)
  end

  def png_outputs
    @outputs.map { |item| item[:png] }.compact
  end

  def brd_outputs
    @outputs.map { |item| item[:brd] }.compact
  end

  def palette_outputs
    @outputs.map { |item| item[:palette] }.compact
  end

  def bsd_outputs
    @outputs.map { |item| item[:bsd] }.compact
  end

  def to_h
    {
      ok: true,
      input: absolute_path(@input_path),
      outputs: {
        png: png_outputs.map { |path| absolute_path(path) },
        brd: brd_outputs.map { |path| absolute_path(path) },
        palette: palette_outputs.map { |path| absolute_path(path) },
        bsd: bsd_outputs.map { |path| absolute_path(path) }
      },
      options: @options,
      timing: @timings,
      log: @logs
    }
  end

  def to_json(*args)
    JSON.pretty_generate(to_h, *args)
  end

  private

  def absolute_path(path)
    File.expand_path(path)
  end

  def round_seconds(seconds)
    seconds.round(4)
  end
end

