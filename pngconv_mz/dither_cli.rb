module DitherCLI
  MODES = %w[8 16 512 4096].freeze
  SORT_MODES = %w[no_sort luminance frequency].freeze
  REMOVE_MODES = %w[no_remove removeBB removeDW removeBBDW].freeze
  FIXED_CHANNELS = %w[R G B all].freeze
  DIFFUSION_METHODS = DitherReducer::DIFFUSION.keys.map(&:to_s).freeze
  DISTANCE_MODES = %w[rgb lab oklab].freeze
  OUTPUT_LAYOUTS = %w[640x400 640x200 320x200 split320x200].freeze
  RESIZE_MODES = %w[fit keep cut].freeze

  module_function

  def parse!(argv)
    options = default_options

    parser = OptionParser.new do |opts|
      opts.banner = <<~BANNER
        Usage:
          ruby #{File.basename($PROGRAM_NAME)} [options] INPUT [OUTPUT]

        Examples:
          ruby #{File.basename($PROGRAM_NAME)} in.png
          ruby #{File.basename($PROGRAM_NAME)} -m 16 --remove removeBB in.jpg out.png
          ruby #{File.basename($PROGRAM_NAME)} --mode 512 --fixed g --method jarvis --strength 0.6 in.png
          ruby #{File.basename($PROGRAM_NAME)} --mode 512 --fixed all --layout split320x200 in.png out.png
          ruby #{File.basename($PROGRAM_NAME)} --mode 4096 --sort luminance --distance oklab --resize keep in.jpeg out.png
      BANNER

      opts.separator ''
      opts.separator 'General options:'

      opts.on('-m', '--mode MODE', MODES, "Palette mode: #{MODES.join(', ')} (default: #{options[:palette_mode]})") do |v|
        options[:palette_mode] = v
      end

      opts.on('-s', '--sort MODE', SORT_MODES, "4096-mode sort: #{SORT_MODES.join(', ')} (default: #{options[:sort_mode]})") do |v|
        options[:sort_mode] = v.to_sym
      end

      opts.on('-r', '--remove MODE', REMOVE_MODES, "16-color removal: #{REMOVE_MODES.join(', ')} (default: #{options[:removeBBDW]})") do |v|
        options[:removeBBDW] = v.to_sym
      end

      opts.on('-f', '--fixed CHANNEL', FIXED_CHANNELS, "512-mode fixed channel: #{FIXED_CHANNELS.join(', ')} (default: #{options[:fixed_channel]})") do |v|
        options[:fixed_channel] = (v == 'all' ? 'all' : v.upcase)
      end

      opts.on('-d', '--method METHOD', DIFFUSION_METHODS, "Dither method: #{DIFFUSION_METHODS.join(', ')} (default: #{options[:diffusion]})") do |v|
        options[:diffusion] = v.to_sym
      end

      opts.on('--strength VALUE', Float, "Diffusion strength 0.0..1.0 (default: #{options[:strength]})") do |v|
        options[:strength] = v
      end

      opts.on('--distance MODE', DISTANCE_MODES, "Color distance: #{DISTANCE_MODES.join(', ')} (default: #{options[:distance]})") do |v|
        options[:distance] = v.to_sym
      end

      opts.on('--layout MODE', OUTPUT_LAYOUTS, "Output layout: #{OUTPUT_LAYOUTS.join(', ')} (default: #{options[:output_layout]})") do |v|
        options[:output_layout] = v
      end

      opts.on('--resize MODE', RESIZE_MODES, "Resize mode to 640x400 base: #{RESIZE_MODES.join(', ')} (default: #{options[:resize_mode]})") do |v|
        options[:resize_mode] = v
      end

      opts.on('--out-dir DIR', 'Output directory for generated PNG/BRD/palette files') do |v|
        options[:out_dir] = v
      end

      opts.on('--png-only', 'Generate PNG preview only; skip BRD/BSD/palette outputs') do
        options[:png_only] = true
      end

      opts.on('--json', 'Output conversion result as JSON') do
        options[:json_output] = true
      end

      opts.on('--quiet', 'Suppress normal text output') do
        options[:quiet] = true
      end

      opts.separator ''
      opts.separator 'Help:'
      opts.on('-h', '--help', 'Show this help') do
        puts opts
        exit
      end
    end

    remaining = parser.parse!(argv)
    if remaining.empty?
      warn parser.to_s
      raise OptionParser::MissingArgument, 'INPUT'
    end

    in_path = remaining.shift
    out_path = resolve_output_path(in_path, remaining.shift || 'dithered.png', options[:out_dir])

    unless remaining.empty?
      raise OptionParser::InvalidArgument, "too many positional arguments: #{remaining.join(' ')}"
    end

    validate!(options)

    {
      in_path: in_path,
      out_path: out_path,
      reducer_options: options.reject { |k, _| k == :output_layout || k == :resize_mode || k == :json_output || k == :out_dir || k == :quiet || k == :png_only },
      output_layout: options[:output_layout],
      resize_mode: options[:resize_mode],
      png_only: options[:png_only],
      json_output: options[:json_output],
      out_dir: options[:out_dir],
      quiet: options[:quiet]
    }
  rescue OptionParser::ParseError => e
    if options && options[:json_output]
      puts JSON.pretty_generate(
        ok: false,
        error: e.message,
        error_class: e.class.name,
        log: []
      )
    else
      warn e.message
      warn parser
    end
    exit 1
  end

  def default_options
    {
      palette_mode: '8',
      sort_mode: :no_sort,
      fixed_channel: 'R',
      removeBBDW: :no_remove,
      diffusion: :floyd_steinberg,
      strength: 1.0,
      distance: :rgb,
      output_layout: '640x400',
      resize_mode: 'fit',
      png_only: false,
      json_output: false,
      quiet: false,
      out_dir: nil
    }
  end

  def ensure_png_extension(path)
    File.extname(path).empty? ? "#{path}.png" : path
  end

  def resolve_output_path(in_path, out_path, out_dir)
    base_name = File.basename(ensure_png_extension(out_path))
    target_dir =
      if out_dir && !out_dir.empty?
        out_dir
      else
        input_dir = File.dirname(in_path)
        input_dir.empty? ? Dir.pwd : input_dir
      end

    FileUtils.mkdir_p(target_dir)
    File.join(target_dir, base_name)
  end

  def validate!(options)
    unless options[:strength].between?(0.0, 1.0)
      raise OptionParser::InvalidArgument, '--strength must be between 0.0 and 1.0'
    end

    if options[:output_layout] == 'split320x200' && options[:palette_mode] != '512'
      raise OptionParser::InvalidArgument, <<~MSG.chomp
        split320x200 は 512色モード専用です。
        --mode 512 を指定してください。
      MSG
    end

    if options[:palette_mode] == '512' && options[:output_layout] == '640x400'
      raise OptionParser::InvalidArgument, <<~MSG.chomp
        512色モードでは 640x400 レイアウトは使用できません。
        --layout 640x200, 320x200, split320x200 のいずれかを指定してください。
      MSG
    end

    if options[:fixed_channel] == 'all' && options[:palette_mode] != '512'
      raise OptionParser::InvalidArgument, <<~MSG.chomp
        --fixed all は 512色モード専用です。
        --mode 512 を指定してください。
      MSG
    end


    case options[:palette_mode]
    when '8'
      warn_unused(options, :sort_mode, :removeBBDW, :fixed_channel)
    when '16'
      warn_unused(options, :sort_mode, :fixed_channel)
    when '512'
      warn_unused(options, :sort_mode, :removeBBDW)
    when '4096'
      warn_unused(options, :removeBBDW, :fixed_channel)
    end
  end

  def warn_unused(options, *keys)
    keys.each do |key|
      default = default_options[key]
      next if options[key] == default

      warn "warning: #{option_name(key)} is ignored when mode=#{options[:palette_mode]}"
    end
  end

  def option_name(key)
    case key
    when :sort_mode
      '--sort'
    when :removeBBDW
      '--remove'
    when :fixed_channel
      '--fixed'
    else
      key.to_s
    end
  end
end

