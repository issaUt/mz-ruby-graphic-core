class DitherReducer
  BASE_RGB8 = [
    [0, 0, 0],
    [0, 0, 255],
    [255, 0, 0],
    [255, 0, 255],
    [0, 255, 0],
    [0, 255, 255],
    [255, 255, 0],
    [255, 255, 255]
  ].freeze

  BASE_RGB8_INDEX = [0, 9, 10, 11, 12, 13, 14, 15].freeze

  FIXED_RGB16 = [
    [0, 0, 0],
    [0, 0, 127],
    [127, 0, 0],
    [127, 0, 127],
    [0, 127, 0],
    [0, 127, 127],
    [127, 127, 0],
    [127, 127, 127],
    [152, 152, 152],
    [0, 0, 255],
    [255, 0, 0],
    [255, 0, 255],
    [0, 255, 0],
    [0, 255, 255],
    [255, 255, 0],
    [255, 255, 255]
  ].freeze

  BASE_RGB16_INDEX = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15].freeze

  DIFFUSION = {
    floyd_steinberg: [
      [1, 0, 7.0 / 16],
      [-1, 1, 3.0 / 16],
      [0, 1, 5.0 / 16],
      [1, 1, 1.0 / 16]
    ],
    stucki: [
      [1, 0, 8.0 / 42],
      [2, 0, 4.0 / 42],
      [-2, 1, 2.0 / 42],
      [-1, 1, 4.0 / 42],
      [0, 1, 8.0 / 42],
      [1, 1, 4.0 / 42],
      [2, 1, 2.0 / 42],
      [-2, 2, 1.0 / 42],
      [-1, 2, 2.0 / 42],
      [0, 2, 4.0 / 42],
      [1, 2, 2.0 / 42],
      [2, 2, 1.0 / 42]
    ],
    jarvis: [
      [1, 0, 7.0 / 48],
      [2, 0, 5.0 / 48],
      [-2, 1, 3.0 / 48],
      [-1, 1, 5.0 / 48],
      [0, 1, 7.0 / 48],
      [1, 1, 5.0 / 48],
      [2, 1, 3.0 / 48],
      [-2, 2, 1.0 / 48],
      [-1, 2, 3.0 / 48],
      [0, 2, 5.0 / 48],
      [1, 2, 3.0 / 48],
      [2, 2, 1.0 / 48]
    ],
    no_dither: []
  }.freeze

  def initialize(
    palette_mode: '8',
    sort_mode: :no_sort,
    fixed_channel: 'R',
    removeBBDW: :no_remove,
    diffusion: :floyd_steinberg,
    strength: 1.0,
    distance: :rgb
  )
    @mode = palette_mode.to_s
    @sort_mode = sort_mode.to_sym
    @fixed_ch = fixed_channel.upcase
    @removeBBDW = removeBBDW
    @method = diffusion.to_sym
    @strength = strength.clamp(0.0, 1.0)
    @distance = distance.to_sym

    @palette = case @mode
               when '8'
                 BASE_RGB8.dup
               when '16'
                 FIXED_RGB16.dup
               when '512'
                 build_512_palette(@fixed_ch)
               else
                 nil
               end

    @paletteIndex = case @mode
                    when '8'
                      BASE_RGB8_INDEX.dup
                    when '16'
                      BASE_RGB16_INDEX.dup
                    else
                      nil
                    end

    if @mode == '16' && @removeBBDW != :no_remove
      case @removeBBDW
      when :removeBB
        @palette.delete_at(8)
        @paletteIndex.delete_at(8)
      when :removeDW
        @palette.delete_at(7)
        @paletteIndex.delete_at(7)
      when :removeBBDW
        @palette.slice!(7, 2)
        @paletteIndex.slice!(7, 2)
      end
    end

    build_palette_lab if @distance == :lab && @palette
    build_palette_oklab if @distance == :oklab && @palette
  end

  def rgb_to_oklab(r, g, b)
    lin = lambda do |c|
      if c <= 0.04045
        c / 12.92
      else
        ((c + 0.055) / 1.055)**2.4
      end
    end

    r, g, b = [r, g, b].map do |c|
      lin.call(c / 255.0)
    end

    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

    l, m, s = [l, m, s].map do |v|
      v**(1.0 / 3)
    end

    okl = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    oka = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    okb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s

    [okl, oka, okb]
  end

  def build_512_palette(ch)
    full = (0..7).to_a
    fixed = [1, 3, 5, 7]

    lr = ch == 'R' ? fixed : full
    lg = ch == 'G' ? fixed : full
    lb = ch == 'B' ? fixed : full

    lr.product(lg, lb).map do |r, g, b|
      [
        (r * 255 / 7.0).round,
        (g * 255 / 7.0).round,
        (b * 255 / 7.0).round
      ]
    end
  end

  def build_4096_palette(img, k = 15, iters = 10)
    px = []

    img.height.times do |y|
      img.width.times do |x|
        r, g, b = ChunkyPNG::Color.to_truecolor_bytes(img[x, y])
        next if r + g + b == 0

        px << [r, g, b]
      end
    end

    cent = px.sample(k)

    iters.times do
      groups = Array.new(k) { [] }

      px.each do |p|
        idx = cent.each_with_index.min_by do |c, _|
          dist_rgb(c, p)
        end[1]

        groups[idx] << p
      end

      cent = groups.map do |g|
        g.empty? ? px.sample : avg_rgb(g)
      end
    end

    to4 = ->(v) { ((v * 15) / 255.0).round }
    to8 = ->(v) { (v * 255 / 15.0).round }

    quant = cent.map do |r, g, b|
      [to8.call(to4.call(r)), to8.call(to4.call(g)), to8.call(to4.call(b))]
    end.uniq

    sorted = case @sort_mode
             when :luminance
               quant.sort_by do |r, g, b|
                 0.299 * r + 0.587 * g + 0.114 * b
               end
             when :frequency
               freq = px.tally
               quant.sort_by do |rgb|
                 -(freq[rgb] || 0)
               end
             else
               quant
             end

    @palette = ([[0, 0, 0]] + sorted.take(k)).uniq[0, 16]

    if @palette.size > 2
      head = @palette[0]
      rest = @palette[1..]
      rest.sort_by! do |r, g, b|
        0.299 * r + 0.587 * g + 0.114 * b
      end
      @palette = [head] + rest
    end

    build_palette_lab if @distance == :lab
    build_palette_oklab if @distance == :oklab
  end

  def build_palette_lab
    @palette_lab = @palette.map do |r, g, b|
      Color::RGB.new(r, g, b).to_lab.values_at(:L, :a, :b)
    end
    @lab_cache = {}
  end

  def build_palette_oklab
    @palette_ok = @palette.map do |r, g, b|
      rgb_to_oklab(r, g, b)
    end
    @ok_cache = {}
  end

  def dist_rgb(a, b)
    (a[0] - b[0])**2 + (a[1] - b[1])**2 + (a[2] - b[2])**2
  end

  def dist_lab(idx, r, g, b)
    lp = @lab_cache[[r, g, b]] ||= Color::RGB.new(r, g, b).to_lab.values_at(:L, :a, :b)
    pl = @palette_lab[idx]
    (lp[0] - pl[0])**2 + (lp[1] - pl[1])**2 + (lp[2] - pl[2])**2
  end

  def dist_oklab(idx, r, g, b)
    lp = @ok_cache[[r, g, b]] ||= rgb_to_oklab(r, g, b)
    po = @palette_ok[idx]
    (lp[0] - po[0])**2 + (lp[1] - po[1])**2 + (lp[2] - po[2])**2
  end

  def closest(r, g, b)
    case @distance
    when :lab
      idx = (0...@palette.size).min_by do |i|
        dist_lab(i, r, g, b)
      end
    when :oklab
      idx = (0...@palette.size).min_by do |i|
        dist_oklab(i, r, g, b)
      end
    else
      return @palette.min_by do |pr, pg, pb|
        dist_rgb([r, g, b], [pr, pg, pb])
      end
    end

    @palette[idx]
  end

  def dither(img)
    @strength = 0.0 if @method == :no_dither

    diff = DitherReducer::DIFFUSION[@method]
    w = img.width
    h = img.height

    buf = Array.new(h) { Array.new(w) }
    h.times do |y|
      w.times do |x|
        buf[y][x] = ChunkyPNG::Color.to_truecolor_bytes(img[x, y]).map(&:to_f)
      end
    end

    h.times do |y|
      w.times do |x|
        old = buf[y][x]
        newc = closest(*old)
        img[x, y] = ChunkyPNG::Color.rgb(*newc)

        err = [old[0] - newc[0], old[1] - newc[1], old[2] - newc[2]]

        diff.each do |dx, dy, wg|
          nx = x + dx
          ny = y + dy
          next unless nx.between?(0, w - 1) && ny.between?(0, h - 1)

          3.times do |c|
            value = buf[ny][nx][c] + err[c] * wg * @strength
            buf[ny][nx][c] = [[value, 0].max, 255].min
          end
        end
      end
    end

    img
  end

  def avg_rgb(a)
    [
      a.sum { |p| p[0] } / a.size,
      a.sum { |p| p[1] } / a.size,
      a.sum { |p| p[2] } / a.size
    ]
  end

  def get_palette_key(pal)
    "#{pal[0]}_#{pal[1]}_#{pal[2]}"
  end

  def get_8bit_2_4bit_value(value)
    a = (value.to_f * 15.0) / 255.0
    a.round(0)
  end

  def output_mz2500_brd(image, path)
    if @mode == '512'
      output_mz2500_brd_512(image, path)
    else
      output_mz2500_brd_standard(image, path)
    end
  end

  def output_mz2500_brd_standard(image, path)
    palette_bundle = build_brd_palette_bundle
    pixels_new = image_to_brd_indices(image, palette_bundle[:hp_index], palette_bundle[:hp_hist])
    write_brd_file(path, image.width, image.height, pixels_new)
    print_brd_histogram(palette_bundle[:hp_index_r], palette_bundle[:hp_hist])
    palette_result = write_4096_palette_report(path, palette_bundle[:hp_index_r]) if @mode == '4096'

    {
      brd: path,
      palette: palette_result && palette_result[:palette],
      palette_color_line: palette_result && palette_result[:color_line]
    }
  end

  def output_mz2500_brd_512(image, path)
    write_mz2500_512_brd(path, image.width, image.height, build_mz2500_512_buffer(image))

    {
      brd: path
    }
  end

  def simulate_mz2500_512_image(image)
    out = ChunkyPNG::Image.new(image.width, image.height, ChunkyPNG::Color::BLACK)

    image.height.times do |y|
      image.width.times do |x|
        r, g, b = ChunkyPNG::Color.to_truecolor_bytes(image[x, y])
        br = channel_to_3bit(r)
        bg = channel_to_3bit(g)
        bb = channel_to_3bit(b)

        case @fixed_ch
        when 'R'
          br &= 0b110
        when 'G'
          bg &= 0b110
        when 'B'
          bb &= 0b110
        else
          raise ArgumentError, "unsupported 512 fixed channel: #{@fixed_ch}"
        end

        out[x, y] = ChunkyPNG::Color.rgb(
          channel_3bit_to_8bit(br),
          channel_3bit_to_8bit(bg),
          channel_3bit_to_8bit(bb)
        )
      end
    end

    out
  end

  def build_mz2500_512_buffer(image)
    width = image.width
    height = image.height
    raise ArgumentError, 'image width must be a multiple of 8' unless (width % 8).zero?

    buffer = Array.new(width * height, 0)
    blocks_per_row = width / 8

    height.times do |y|
      blocks_per_row.times do |bx|
        base = (width * y) + (bx * 8)

        8.times do |lx|
          x = (bx * 8) + lx
          r, g, b = ChunkyPNG::Color.to_truecolor_bytes(image[x, y])
          br = channel_to_3bit(r)
          bg = channel_to_3bit(g)
          bb = channel_to_3bit(b)
          bit = 1 << lx

          buffer[base] |= bit if (bb & 0b100) != 0
          buffer[base + 1] |= bit if (br & 0b100) != 0
          buffer[base + 2] |= bit if (bg & 0b100) != 0
          buffer[base + 4] |= bit if (bb & 0b010) != 0
          buffer[base + 5] |= bit if (br & 0b010) != 0
          buffer[base + 6] |= bit if (bg & 0b010) != 0

          write_mz2500_512_low_bits(buffer, base, bit, br, bg, bb)
        end
      end
    end

    buffer
  end

  def channel_to_3bit(value)
    [(value.to_i / 32), 7].min
  end

  def channel_3bit_to_8bit(value)
    (value.to_i * 255 / 7.0).round
  end

  def write_mz2500_512_low_bits(buffer, base, bit, br, bg, bb)
    case @fixed_ch
    when 'R'
      buffer[base + 3] |= bit if (bg & 0b001) != 0
      buffer[base + 7] |= bit if (bb & 0b001) != 0
    when 'G'
      buffer[base + 3] |= bit if (br & 0b001) != 0
      buffer[base + 7] |= bit if (bb & 0b001) != 0
    when 'B'
      buffer[base + 3] |= bit if (bg & 0b001) != 0
      buffer[base + 7] |= bit if (br & 0b001) != 0
    else
      raise ArgumentError, "unsupported 512 fixed channel: #{@fixed_ch}"
    end
  end

  def write_mz2500_512_brd(path, width, height, buffer)
    width_le = [width].pack('v').bytes
    height_le = [height].pack('v').bytes

    File.open(path, 'wb') do |file|
      file.write('graphic data 000')
      file.write([0, 0, 0, 0, width_le[0], width_le[1], height_le[0], height_le[1], 0x20].pack('C*'))
      file.write(Array.new(231, 0).pack('C*'))
      file.write(buffer.pack('C*'))
      file.write(Array.new(1280, 0).pack('C*'))
    end
  end

  def build_brd_palette_bundle
    hp_hist = {}
    hp_index = {}
    hp_index_r = {}

    if @mode == '8' || @mode == '16'
      @palette.each_with_index do |pal, i|
        key = get_palette_key(pal)
        hp_index[key] = @paletteIndex[i]
        hp_index_r[i] = key
        hp_hist[key] = 0
      end
    else
      @palette.each_with_index do |pal, i|
        key = get_palette_key(pal)
        hp_index[key] = i
        hp_index_r[i] = key
        hp_hist[key] = 0
      end
    end

    {
      hp_hist: hp_hist,
      hp_index: hp_index,
      hp_index_r: hp_index_r
    }
  end

  def image_to_brd_indices(image, hp_index, hp_hist)
    width = image.width
    height = image.height
    raise ArgumentError, 'image width must be a multiple of 8' unless (width % 8).zero?

    pixels_new = Array.new(height) { Array.new(width) }

    height.times do |y|
      width.times do |x|
        r, g, b = ChunkyPNG::Color.to_truecolor_bytes(image[x, y])
        key = get_palette_key([r.to_i, g.to_i, b.to_i])
        hp_hist[key] = hp_hist[key] + 1
        pixels_new[y][x] = hp_index[key]
      end
    end

    pixels_new
  end

  def write_brd_file(path, width, height, pixels_new)
    bytes_per_row = (width / 8) * 4
    width_le = [width].pack('v').bytes
    height_le = [height].pack('v').bytes

    File.open(path, 'wb') do |file|
      file.write('graphic data 000')
      file.write([0, 0, 0, 0, width_le[0], width_le[1], height_le[0], height_le[1], 0xD0].pack('C*'))
      file.write(Array.new(231, 0).pack('C*'))

      height.times do |y|
        block = Array.new(bytes_per_row, 0)
        b = 0
        x = 0

        while x < width
          bit_b = 0
          bit_r = 0
          bit_g = 0
          bit_i = 0

          i = 0
          while i < 8
            bit = 1 << i
            val = pixels_new[y][x + i]

            bit_b |= bit if val[0] != 0
            bit_r |= bit if val[1] != 0
            bit_g |= bit if val[2] != 0
            bit_i |= bit if val[3] != 0
            i += 1
          end

          block[b] = bit_b
          block[b + 1] = bit_r
          block[b + 2] = bit_g
          block[b + 3] = bit_i
          b += 4
          x += 8
        end

        file.write(block.pack('C*'))
      end

      file.write(Array.new(768, 0).pack('C*'))
    end
  end

  def print_brd_histogram(hp_index_r, hp_hist)
    hp_index_r.keys.sort.each do |i|
      key = hp_index_r[i]
      keys = key.split('_')
      printf("%2d:%12s,(%8b, %8b, %8b): %d
", i, key, keys[1].to_i, keys[0].to_i, keys[2].to_i, hp_hist[key])
    end
  end

  def build_4096_palette_report_lines(hp_index_r)
    pl_m25 = []
    lines = []

    hp_index_r.keys.sort.each do |i|
      key = hp_index_r[i]
      keys = key.split('_')
      val = Array.new(3, 0)
      val[0] = get_8bit_2_4bit_value(keys[1].to_i)
      val[1] = get_8bit_2_4bit_value(keys[0].to_i)
      val[2] = get_8bit_2_4bit_value(keys[2].to_i)

      pl_m25.push(val) if i != 0
      line = format('%2d, ( %d, %d, %d )', i, val[0], val[1], val[2])
      puts line
      lines << line
    end

    color_line = 'color='
    pl_m25.each_with_index do |val, i|
      color_line << format('(%d,%d,%d,%d)', i + 1, val[0], val[1], val[2])
      color_line << ',' if i < pl_m25.length - 1
    end
    print color_line
    print "
"
    lines << color_line

    lines
  end

  def write_4096_palette_report(brd_path, hp_index_r)
    lines = build_4096_palette_report_lines(hp_index_r)
    palette_path = File.join(File.dirname(brd_path), "#{File.basename(brd_path, '.*')}.pallet")
    File.write(palette_path, lines.join("
") + "
")
    {
      palette: palette_path,
      color_line: lines.last
    }
  end

  def write_split320_bsd(path, upper_brd_path, lower_brd_path, fixed_channel)
    upper_name = File.basename(upper_brd_path, '.*')
    lower_name = File.basename(lower_brd_path, '.*')
    cblock = cblock_for_fixed_channel(fixed_channel)
    statements = [
      format('init "crt2:320,200,256":cls 3:cblock %d', cblock),
      'init "crt:,,,1"',
      'screen ,,0,(0)',
      format('gload "%s"', upper_name),
      'screen ,,1,(1)',
      format('gload "%s"', lower_name),
      'screen ,,0,(0)',
      'out &HBC,&HE: out &HBD,&H19',
      'out &HBC,&H8A',
      'out &HBD,&H90: out &HBD,&H1',
      'out &HBC,&H94',
      'out &HBD,&H0: out &HBD,&H40',
      'out &HBD,&HC8: out &HBD,&H0'
    ]
    write_basic_bsd(path, statements)
    path
  end

  def write_512_bsd(path, brd_path, fixed_channel)
    image_name = File.basename(brd_path, '.*')
    cblock = cblock_for_fixed_channel(fixed_channel)
    statements = [
      format('init "crt2:320,200,256":cls 3:cblock %d', cblock),
      'init "crt:,,,1"',
      format('gload "%s"', image_name)
    ]
    write_basic_bsd(path, statements)
    path
  end

  def write_4096_bsd(path, brd_path, color_line, output_layout)
    image_name = File.basename(brd_path, '.*')
    width, height = output_layout_size(output_layout)
    statements = [
      format('init "crt2:%d,%d,16":cls 3', width, height),
      'init "crt:,,,1"',
      color_line,
      format('gload "%s"', image_name)
    ]
    write_basic_bsd(path, statements)
    path
  end

  def write_standard_bsd(path, brd_path, output_layout, color_count)
    image_name = File.basename(brd_path, '.*')
    width, height = output_layout_size(output_layout)
    statements = [
      format('init "crt2:%d,%d,%d":cls 3', width, height, color_count),
      'init "crt:,,,1"',
      format('gload "%s"', image_name)
    ]
    write_basic_bsd(path, statements)
    path
  end

  def write_basic_bsd(path, statements)
    File.binwrite(path, numbered_basic_lines(statements).join("\r") + "\r")
  end

  def numbered_basic_lines(statements)
    statements.each_with_index.map do |statement, index|
      format('%5d %s', (index + 1) * 10, statement)
    end
  end

  def cblock_for_fixed_channel(fixed_channel)
    case fixed_channel
    when 'B'
      0
    when 'R'
      1
    when 'G'
      2
    else
      raise ArgumentError, "unsupported fixed channel for BSD: #{fixed_channel}"
    end
  end

  def output_layout_size(output_layout)
    case output_layout
    when '640x400'
      [640, 400]
    when '640x200'
      [640, 200]
    when '320x200'
      [320, 200]
    else
      raise ArgumentError, "unsupported BSD output layout: #{output_layout}"
    end
  end

  def resize_bilinear(img, target_width, target_height)
    out = ChunkyPNG::Image.new(target_width, target_height, ChunkyPNG::Color::BLACK)
    src_w = img.width
    src_h = img.height

    x_ratio = src_w.to_f / target_width
    y_ratio = src_h.to_f / target_height

    target_height.times do |y|
      sy = (y + 0.5) * y_ratio - 0.5
      y0 = [[sy.floor, 0].max, src_h - 1].min
      y1 = [y0 + 1, src_h - 1].min
      fy = sy - y0
      fy = 0.0 if fy.negative?

      target_width.times do |x|
        sx = (x + 0.5) * x_ratio - 0.5
        x0 = [[sx.floor, 0].max, src_w - 1].min
        x1 = [x0 + 1, src_w - 1].min
        fx = sx - x0
        fx = 0.0 if fx.negative?

        c00 = ChunkyPNG::Color.to_truecolor_bytes(img[x0, y0])
        c10 = ChunkyPNG::Color.to_truecolor_bytes(img[x1, y0])
        c01 = ChunkyPNG::Color.to_truecolor_bytes(img[x0, y1])
        c11 = ChunkyPNG::Color.to_truecolor_bytes(img[x1, y1])

        rgb = 3.times.map do |i|
          top = c00[i] * (1.0 - fx) + c10[i] * fx
          bottom = c01[i] * (1.0 - fx) + c11[i] * fx
          (top * (1.0 - fy) + bottom * fy).round.clamp(0, 255)
        end

        out[x, y] = ChunkyPNG::Color.rgb(*rgb)
      end
    end

    out
  end

  def average_block(img, x0, y0, width, height)
    sum = [0, 0, 0]
    count = width * height

    height.times do |dy|
      width.times do |dx|
        r, g, b = ChunkyPNG::Color.to_truecolor_bytes(img[x0 + dx, y0 + dy])
        sum[0] += r
        sum[1] += g
        sum[2] += b
      end
    end

    sum.map { |v| (v.to_f / count).round.clamp(0, 255) }
  end

  def downsample_average(img, factor_x:, factor_y:, y_offset: 0, height_limit: nil)
    src_height = height_limit || img.height
    out_width = img.width / factor_x
    out_height = src_height / factor_y
    out = ChunkyPNG::Image.new(out_width, out_height, ChunkyPNG::Color::BLACK)

    out_height.times do |y|
      out_width.times do |x|
        rgb = average_block(img, x * factor_x, y_offset + (y * factor_y), factor_x, factor_y)
        out[x, y] = ChunkyPNG::Color.rgb(*rgb)
      end
    end

    out
  end

  def prepare_base_image(img, resize_mode)
    case resize_mode
    when 'fit'
      resize_bilinear(img, 640, 400)
    when 'keep'
      prepare_base_image_keep_aspect(img)
    else
      raise ArgumentError, "unsupported resize_mode: #{resize_mode}"
    end
  end

  def prepare_base_image_keep_aspect(img)
    src_w = img.width
    src_h = img.height
    scale = [640.0 / src_w, 400.0 / src_h].min
    scaled_w = [(src_w * scale).round, 1].max
    scaled_h = [(src_h * scale).round, 1].max

    resized = resize_bilinear(img, scaled_w, scaled_h)
    canvas = ChunkyPNG::Image.new(640, 400, ChunkyPNG::Color::BLACK)

    offset_x = (640 - scaled_w) / 2
    offset_y = (400 - scaled_h) / 2

    scaled_h.times do |y|
      scaled_w.times do |x|
        canvas[offset_x + x, offset_y + y] = resized[x, y]
      end
    end

    canvas
  end

  def prepare_output_images(img, out_path, output_layout, resize_mode)
    base = prepare_base_image(img, resize_mode)

    case output_layout
    when '640x400'
      [[base, out_path]]
    when '640x200'
      [[downsample_average(base, factor_x: 1, factor_y: 2), out_path]]
    when '320x200'
      [[downsample_average(base, factor_x: 2, factor_y: 2), out_path]]
    when 'split320x200'
      ext = File.extname(out_path)
      stem = ext.empty? ? out_path : out_path[0...-ext.length]
      [
        [downsample_average(base, factor_x: 2, factor_y: 1, y_offset: 0, height_limit: 200), "#{stem}_u#{ext}"],
        [downsample_average(base, factor_x: 2, factor_y: 1, y_offset: 200, height_limit: 200), "#{stem}_l#{ext}"]
      ]
    else
      raise ArgumentError, "unsupported output_layout: #{output_layout}"
    end
  end

  def process_single_image(img, out_path)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @palette = nil if @mode == '4096'
    palette_seconds = measure_seconds do
      build_4096_palette(img) if @mode == '4096' && @palette.nil?
    end

    dithered = nil
    dither_seconds = measure_seconds do
      dithered = dither(img.dup)
    end
    simulate_seconds = measure_seconds do
      dithered = simulate_mz2500_512_image(dithered) if @mode == '512'
    end
    save_png_seconds = measure_seconds do
      dithered.save(out_path)
    end

    if @mode == '4096'
      puts '抽出されたパレット:'
      @palette.each_with_index do |(r, g, b), i|
        puts '%2d: (%3d, %3d, %3d)' % [i, r, g, b]
      end
    end

    out_mz_path = File.join(File.dirname(out_path), "#{File.basename(out_path, '.*')}.brd")
    brd_result = nil
    save_brd_seconds = measure_seconds do
      brd_result = output_mz2500_brd(dithered, out_mz_path)
    end

    brd_result.merge(
      png: out_path,
      timing: {
        path: out_path,
        palette_seconds: round_seconds(palette_seconds),
        dither_seconds: round_seconds(dither_seconds),
        simulate_seconds: round_seconds(simulate_seconds),
        save_png_seconds: round_seconds(save_png_seconds),
        save_brd_seconds: round_seconds(save_brd_seconds),
        total_seconds: round_seconds(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at)
      }
    )
  end

  def process(in_path, out_path, output_layout: '640x400', resize_mode: 'fit')
    timings = {}
    img = nil
    timings[:read_seconds] = round_seconds(measure_seconds do
      img = ChunkyPNG::Image.from_file(in_path)
    end)

    prepared_images = nil
    timings[:prepare_seconds] = round_seconds(measure_seconds do
      prepared_images = prepare_output_images(img, out_path, output_layout, resize_mode)
    end)

    outputs = prepared_images.map do |prepared_img, prepared_out_path|
      process_single_image(prepared_img, prepared_out_path)
    end

    {
      outputs: outputs,
      timing: timings
    }
  end

  def measure_seconds
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  end

  def round_seconds(seconds)
    seconds.round(4)
  end
end

