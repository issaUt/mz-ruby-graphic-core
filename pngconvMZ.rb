require 'chunky_png'
require 'color'
require 'fileutils'
require 'json'
require 'optparse'
require 'stringio'

require_relative 'pngconv_mz/version'
require_relative 'pngconv_mz/image_loader'
require_relative 'pngconv_mz/conversion_result'
require_relative 'pngconv_mz/dither_reducer'
require_relative 'pngconv_mz/conversion_runner'
require_relative 'pngconv_mz/dither_cli'

if __FILE__ == $PROGRAM_NAME
  cli = DitherCLI.parse!(ARGV)

  if cli[:json_output]
    captured_stdout = StringIO.new
    original_stdout = $stdout
    begin
      $stdout = captured_stdout
      result = ConversionRunner.new(cli).run
    rescue StandardError => e
      result = {
        ok: false,
        error: e.message,
        error_class: e.class.name,
        log: captured_stdout.string.lines.map(&:chomp)
      }
    ensure
      $stdout = original_stdout
    end
    if result.respond_to?(:add_logs)
      result.add_logs(captured_stdout.string)
      puts result.to_json
    else
      puts JSON.pretty_generate(result)
      exit 1
    end
  else
    if cli[:quiet]
      captured_stdout = StringIO.new
      original_stdout = $stdout
      begin
        $stdout = captured_stdout
        result = ConversionRunner.new(cli).run
      ensure
        $stdout = original_stdout
      end
    else
      result = ConversionRunner.new(cli).run
    end

    if !cli[:quiet] && result.png_outputs.length > 1
      puts 'Generated outputs:'
      result.png_outputs.each do |path|
        puts "  - #{path}"
      end
    end

    unless cli[:quiet]
      puts format('Elapsed: %.4fs', result.timings[:total_seconds]) if result.timings[:total_seconds]
    end

    puts 'Done.' unless cli[:quiet]
  end
end
