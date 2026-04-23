require 'chunky_png'
require 'open3'
require 'tempfile'

module ImageLoader
  JPEG_EXTENSIONS = %w[.jpg .jpeg .jpe].freeze

  module_function

  def load(path)
    ext = File.extname(path).downcase
    return ChunkyPNG::Image.from_file(path) if ext == '.png'
    return load_jpeg(path) if JPEG_EXTENSIONS.include?(ext)

    raise ArgumentError, "unsupported input image format: #{ext.empty? ? '(none)' : ext}"
  end

  def load_jpeg(path)
    load_jpeg_with_libjpeg(path) || load_jpeg_with_windows_decoder(path)
  end

  def load_jpeg_with_libjpeg(path)
    begin
      require 'jpeg'
    rescue LoadError
      return nil
    end

    decoder = JPEG::Decoder.new(pixel_format: :RGB)
    raw = decoder << File.binread(path)
    meta = raw.respond_to?(:meta) ? raw.meta : {}
    width = meta[:width] || meta['width']
    height = meta[:height] || meta['height']
    raise "JPEG decoder did not return image size." unless width && height

    image = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color::BLACK)
    bytes = raw.bytes
    height.times do |y|
      width.times do |x|
        offset = (y * width + x) * 3
        image[x, y] = ChunkyPNG::Color.rgb(bytes[offset], bytes[offset + 1], bytes[offset + 2])
      end
    end
    image
  rescue StandardError
    nil
  end

  def load_jpeg_with_windows_decoder(path)
    raise LoadError, "JPEG input requires the jpeg/libjpeg-ruby gem or Windows PowerShell decoder." unless Gem.win_platform?

    Tempfile.create(['pngconv_mz_jpeg_', '.png']) do |temp|
      temp.close
      script = <<~POWERSHELL
        param(
          [Parameter(Mandatory=$true)][string]$InputPath,
          [Parameter(Mandatory=$true)][string]$OutputPath
        )
        Add-Type -AssemblyName System.Drawing
        $image = [System.Drawing.Image]::FromFile($InputPath)
        try {
          $image.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
          $image.Dispose()
        }
      POWERSHELL
      Tempfile.create(['pngconv_mz_jpeg_decoder_', '.ps1']) do |script_file|
        script_file.write(script)
        script_file.close

        stdout, stderr, status = Open3.capture3(
          'powershell',
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script_file.path,
          path,
          temp.path
        )
        unless status.success?
          message = stderr.strip.empty? ? stdout.strip : stderr.strip
          raise "failed to read JPEG input: #{message}"
        end
      end

      ChunkyPNG::Image.from_file(temp.path)
    end
  end
end
