class ConversionRunner
  def initialize(cli)
    @cli = cli
  end

  def run
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = ConversionResult.new(
      input_path: @cli[:in_path],
      options: result_options
    )

    fixed_channels.each do |fixed_channel|
      channel_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      reducer_options = @cli[:reducer_options].merge(fixed_channel: fixed_channel)
      reducer = DitherReducer.new(**reducer_options)
      process_result = reducer.process(
        @cli[:in_path],
        output_path_for(fixed_channel),
        output_layout: @cli[:output_layout],
        resize_mode: @cli[:resize_mode],
        mz_output: !@cli[:png_only]
      )
      add_bsd_outputs(reducer, process_result[:outputs], fixed_channel) unless @cli[:png_only]
      result.add_outputs(process_result[:outputs])
      result.add_channel_timing(
        {
          fixed_channel: fixed_channel,
          read_seconds: process_result[:timing][:read_seconds],
          prepare_seconds: process_result[:timing][:prepare_seconds],
          image_timings: process_result[:outputs].map { |item| item[:timing] }.compact,
          total_seconds: round_seconds(Process.clock_gettime(Process::CLOCK_MONOTONIC) - channel_started_at)
        }
      )
    end

    result.set_total_seconds(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at)
    result
  end

  private

  def fixed_channels
    if @cli[:reducer_options][:palette_mode] == '512' && @cli[:reducer_options][:fixed_channel] == 'all'
      %w[R G B]
    else
      [@cli[:reducer_options][:fixed_channel]]
    end
  end

  def output_path_for(fixed_channel)
    out_path = @cli[:out_path]
    if @cli[:reducer_options][:palette_mode] == '512'
      ext = File.extname(out_path)
      stem = ext.empty? ? out_path : out_path[0...-ext.length]
      out_path = "#{stem}_fixed#{fixed_channel}#{ext}"
    end

    DitherCLI.ensure_png_extension(out_path)
  end

  def add_bsd_outputs(reducer, outputs, fixed_channel)
    case @cli[:reducer_options][:palette_mode]
    when '512'
      add_512_bsd_outputs(reducer, outputs, fixed_channel)
    when '4096'
      add_4096_bsd_outputs(reducer, outputs)
    when '8', '16'
      add_standard_bsd_outputs(reducer, outputs)
    end
  end

  def add_512_bsd_outputs(reducer, outputs, fixed_channel)
    if @cli[:output_layout] == 'split320x200'
      upper = outputs.find { |item| item[:brd]&.match?(/_u\.brd\z/i) }
      lower = outputs.find { |item| item[:brd]&.match?(/_l\.brd\z/i) }
      return unless upper && lower

      bsd_path = bsd_path_for(upper[:brd], "#{split_base_name(upper[:brd])}_ul")
      outputs << {
        bsd: reducer.write_split320_bsd(bsd_path, upper[:brd], lower[:brd], fixed_channel)
      }
      return
    end

    outputs.each do |item|
      next unless item[:brd]

      bsd_path = bsd_path_for(item[:brd])
      item[:bsd] = reducer.write_512_bsd(bsd_path, item[:brd], fixed_channel)
    end
  end

  def add_4096_bsd_outputs(reducer, outputs)
    outputs.each do |item|
      next unless item[:brd] && item[:palette_color_line]

      bsd_path = bsd_path_for(item[:brd])
      item[:bsd] = reducer.write_4096_bsd(bsd_path, item[:brd], item[:palette_color_line], @cli[:output_layout])
    end
  end

  def add_standard_bsd_outputs(reducer, outputs)
    outputs.each do |item|
      next unless item[:brd]

      bsd_path = bsd_path_for(item[:brd])
      item[:bsd] = reducer.write_standard_bsd(bsd_path, item[:brd], @cli[:output_layout], 16)
    end
  end

  def bsd_path_for(brd_path, base_name = File.basename(brd_path, '.*'))
    File.join(File.dirname(brd_path), "#{base_name}.bas.bsd")
  end

  def split_base_name(brd_path)
    File.basename(brd_path, '.*').sub(/_[ul]\z/i, '')
  end

  def result_options
    @cli[:reducer_options].merge(
      output_layout: @cli[:output_layout],
      resize_mode: @cli[:resize_mode],
      png_only: @cli[:png_only],
      output_dir: File.dirname(@cli[:out_path])
    )
  end

  def round_seconds(seconds)
    seconds.round(4)
  end
end

