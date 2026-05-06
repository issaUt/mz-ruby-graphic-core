module PngconvMZ
  module MachineProfiles
    PROFILES = {
      'mz2500' => {
        label: 'SHARP MZ-2500',
        modes: %w[8 16 512 4096].freeze,
        layouts_by_mode: {
          '8' => %w[640x400 640x200 320x200].freeze,
          '16' => %w[640x400 640x200 320x200].freeze,
          '512' => %w[320x200 split320x200].freeze,
          '4096' => %w[640x400 640x200 320x200].freeze
        }.freeze,
        fixed_channels: %w[R G B all].freeze,
        standard_pixel_bit_order: :lsb_left,
        palette_4096_component_order: %i[g r b].freeze
      }.freeze,
      'mz2861' => {
        label: 'SHARP MZ-2861',
        modes: %w[8 16 4096].freeze,
        layouts_by_mode: {
          '8' => %w[640x400 640x200].freeze,
          '16' => %w[640x400 640x200].freeze,
          '4096' => %w[640x400 640x200].freeze
        }.freeze,
        fixed_channels: [].freeze,
        # Current assumption for MZ-2861: the pixel bit order inside each 8-pixel byte
        # is reversed compared with MZ-2500 family output.
        standard_pixel_bit_order: :msb_left,
        # Relative to the current MZ-2500 color-line output, MZ-2861 swaps G and B.
        palette_4096_component_order: %i[b r g].freeze
      }.freeze
    }.freeze

    module_function

    def ids
      PROFILES.keys
    end

    def fetch(id)
      key = normalize_id(id)
      PROFILES.fetch(key) do
        raise ArgumentError, "unsupported machine: #{id}"
      end
    end

    def label(id)
      fetch(id)[:label]
    end

    def modes(id)
      fetch(id)[:modes]
    end

    def layouts(id, mode)
      fetch(id)[:layouts_by_mode].fetch(mode.to_s) do
        raise ArgumentError, "unsupported layout set for machine=#{id} mode=#{mode}"
      end
    end

    def fixed_channels(id)
      fetch(id)[:fixed_channels]
    end

    def public_profiles
      ids.to_h do |id|
        profile = fetch(id)
        [
          id,
          {
            label: profile[:label],
            modes: profile[:modes],
            layouts_by_mode: profile[:layouts_by_mode],
            fixed_channels: profile[:fixed_channels]
          }
        ]
      end
    end

    def normalize_id(id)
      id.to_s.strip.downcase
    end
  end
end
