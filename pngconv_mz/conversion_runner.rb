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

    write_d88_image(result) if @cli[:d88_path]
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
      out_path = "#{stem}_#{fixed_channel_token(fixed_channel)}#{ext}"
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

      bsd_path = bsd_path_for(upper[:brd], "#{split_base_name(upper[:brd])}_c")
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
      output_dir: File.dirname(@cli[:out_path]),
      d88_path: @cli[:d88_path],
      d88_title: @cli[:d88_title],
      d88_append_if_exists: @cli[:d88_append_if_exists],
      d88_sidecar: @cli[:d88_sidecar]
    )
  end

  def round_seconds(seconds)
    seconds.round(4)
  end

  # pngconvMZ integration: pack generated MZ files into a D88 image.
  def write_d88_image(result)
    d88_path = @cli[:d88_path]
    title = @cli[:d88_title] || default_d88_title(d88_path)
    disk = if @cli[:d88_append_if_exists] && File.exist?(d88_path)
             MZD88::Disk.load(d88_path)
           else
             MZD88::Disk.blank(title: title)
           end
    disk_name_map = d88_source_paths(result).to_h do |path|
      [path, d88_disk_name_for(path)]
    end
    temp_paths = []

    d88_source_paths(result).each do |path|
      source_path = d88_source_file_for(path, result, disk_name_map, temp_paths)
      disk.add_file(source_path, disk_name: disk_name_map[path], force: true)
    end

    disk.save(d88_path)
    result.add_d88_output(d88_path)
    result.add_logs("D88 saved: #{File.expand_path(d88_path)}")
    cleanup_d88_sidecar_files(result) if @cli[:d88_sidecar] == 'delete'
  ensure
    temp_paths&.each do |temp_path|
      File.delete(temp_path) if File.exist?(temp_path)
    end
  end

  def d88_source_paths(result)
    (result.brd_outputs + result.bsd_outputs).uniq
  end

  def d88_source_file_for(path, result, disk_name_map, temp_paths)
    return path unless path.downcase.end_with?('.bsd')

    brd_name_map = result.brd_outputs.to_h do |brd_path|
      [default_d88_disk_name(brd_path), disk_name_map[brd_path]]
    end
    original = File.binread(path)
    rewritten = original.gsub(/gload "([^"]+)"/i) do
      %(gload "#{brd_name_map.fetch(Regexp.last_match(1), Regexp.last_match(1))}")
    end
    return path if rewritten == original

    temp_path = path.sub(/\.bsd\z/i, '.d88tmp.bsd')
    File.binwrite(temp_path, rewritten)
    temp_paths << temp_path
    temp_path
  end

  def d88_disk_name_for(path)
    name = default_d88_disk_name(path)
    raise ArgumentError, "D88 internal name is longer than 16 bytes: #{name}" if name.bytesize > 16

    name
  end

  def default_d88_disk_name(path)
    basename = File.basename(path)
    if basename.downcase.end_with?('.bas.bsd')
      "#{File.basename(basename, '.bas.bsd')}.bas"
    else
      File.basename(path, File.extname(path))
    end
  end

  def fixed_channel_token(fixed_channel)
    case fixed_channel
    when 'R' then 'FR'
    when 'G' then 'FG'
    when 'B' then 'FB'
    else fixed_channel
    end
  end

  def cleanup_d88_sidecar_files(result)
    cleanup_output_paths(result, :bsd, result.bsd_outputs)
    cleanup_output_paths(result, :brd, result.brd_outputs)
  end

  def cleanup_output_paths(result, key, paths)
    paths.each do |path|
      next unless File.exist?(path)

      File.delete(path)
      result.remove_file_output!(key, path)
      result.add_logs("Deleted after D88 packing: #{File.expand_path(path)}")
    end
  end

  def default_d88_title(d88_path)
    File.basename(d88_path, File.extname(d88_path))
  end
end
