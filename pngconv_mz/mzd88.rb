#!/usr/bin/env ruby
# frozen_string_literal: true

# Imported from mz2500-tools/mzd88.rb
# Local adjustments for pngconvMZ integration should be marked explicitly.

require "optparse"
require "fileutils"
require "time"

module MZD88
  HEADER_SIZE = 0x2b0
  TRACK_OFFSET_COUNT = 164
  CYLINDERS = 80
  HEADS = 2
  TRACKS = CYLINDERS * HEADS
  SECTORS_PER_TRACK = 16
  SECTOR_SIZE = 256
  SECTOR_HEADER_SIZE = 16
  TRACK_SIZE = SECTORS_PER_TRACK * (SECTOR_HEADER_SIZE + SECTOR_SIZE)
  DISK_SIZE = HEADER_SIZE + TRACKS * TRACK_SIZE

  TOTAL_RECORDS = CYLINDERS * HEADS * SECTORS_PER_TRACK
  BLOCK_FACTOR = 2
  TOTAL_BLOCKS = TOTAL_RECORDS / BLOCK_FACTOR
  DATA_OFFSET_BLOCK = 0x18
  DATA_START_RECORD = DATA_OFFSET_BLOCK * BLOCK_FACTOR
  DATA_BLOCKS = TOTAL_BLOCKS - DATA_OFFSET_BLOCK

  BITMAP_RECORD = 0x000f
  DIRECTORY_START_RECORD = 0x0010
  DIRECTORY_RECORDS = 8
  DIRECTORY_ENTRIES = 64
  DIRECTORY_ENTRY_SIZE = 32

  EMPTY_DATA_BYTE = 0xbf
  EMPTY_NAME_BYTE = 0x0d

  MODE_UNUSED = 0x00
  MODE_OBJ = 0x01
  MODE_BTX = 0x02
  MODE_BSD = 0x03
  MODE_BRD = 0x04
  MODE_DIR = 0x0f
  MODE_SWAP_EMPTY = 0x80
  MODE_SWAP_USED = 0x81

  MODE_NAMES = {
    MODE_UNUSED => "UNUSED",
    MODE_OBJ => "OBJ",
    MODE_BTX => "BTX",
    MODE_BSD => "BSD",
    MODE_BRD => "BRD",
    MODE_DIR => "DIR",
    MODE_SWAP_EMPTY => "SWAP_EMPTY",
    MODE_SWAP_USED => "SWAP_USED"
  }.freeze

  class Error < StandardError; end

  def self.le16(bytes, offset)
    bytes.getbyte(offset) | (bytes.getbyte(offset + 1) << 8)
  end

  def self.put_le16(bytes, offset, value)
    bytes.setbyte(offset, value & 0xff)
    bytes.setbyte(offset + 1, (value >> 8) & 0xff)
  end

  def self.le32(bytes, offset)
    bytes.getbyte(offset) |
      (bytes.getbyte(offset + 1) << 8) |
      (bytes.getbyte(offset + 2) << 16) |
      (bytes.getbyte(offset + 3) << 24)
  end

  def self.put_le32(bytes, offset, value)
    4.times { |i| bytes.setbyte(offset + i, (value >> (8 * i)) & 0xff) }
  end

  def self.invert(data)
    data.bytes.map { |b| (b ^ 0xff).chr }.join.b
  end

  class D88Image
    attr_reader :bytes

    def initialize(bytes = nil)
      @bytes = bytes || self.class.blank_bytes
      validate!
    end

    def self.load(path)
      new(File.binread(path))
    end

    def self.blank_bytes(title: "BLANK")
      bytes = "\x00".b * DISK_SIZE
      title_bytes = title.encode("ASCII", invalid: :replace, undef: :replace, replace: "?").bytes
      title_bytes = title_bytes.first(16)
      title_bytes.each_with_index { |b, i| bytes.setbyte(i, b) }
      bytes.setbyte(0x1a, 0x00) # write protect
      bytes.setbyte(0x1b, 0x10) # 2DD
      MZD88.put_le32(bytes, 0x1c, DISK_SIZE)

      TRACKS.times do |track_index|
        MZD88.put_le32(bytes, 0x20 + track_index * 4, HEADER_SIZE + track_index * TRACK_SIZE)
      end

      TRACKS.times do |track_index|
        cylinder = track_index / HEADS
        head = track_index % HEADS
        SECTORS_PER_TRACK.times do |sector_index|
          offset = sector_header_offset(track_index, sector_index + 1)
          bytes.setbyte(offset + 0, cylinder)
          bytes.setbyte(offset + 1, head)
          bytes.setbyte(offset + 2, sector_index + 1)
          bytes.setbyte(offset + 3, 1) # 256 bytes
          MZD88.put_le16(bytes, offset + 4, SECTORS_PER_TRACK)
          MZD88.put_le16(bytes, offset + 14, SECTOR_SIZE)
        end
      end

      bytes
    end

    def self.sector_header_offset(track_index, sector)
      HEADER_SIZE + track_index * TRACK_SIZE + (sector - 1) * (SECTOR_HEADER_SIZE + SECTOR_SIZE)
    end

    def validate!
      raise Error, "D88 size is too small" if @bytes.bytesize < HEADER_SIZE
      raise Error, "unsupported D88 size: #{@bytes.bytesize}" if @bytes.bytesize < DISK_SIZE
    end

    def save(path)
      File.binwrite(path, @bytes)
    end

    def sector_data(track_index, sector)
      offset = self.class.sector_header_offset(track_index, sector) + SECTOR_HEADER_SIZE
      @bytes.byteslice(offset, SECTOR_SIZE)
    end

    def set_sector_data(track_index, sector, data)
      raise Error, "sector data must be #{SECTOR_SIZE} bytes" unless data.bytesize == SECTOR_SIZE

      offset = self.class.sector_header_offset(track_index, sector) + SECTOR_HEADER_SIZE
      @bytes[offset, SECTOR_SIZE] = data
    end
  end

  class DirectoryEntry
    attr_accessor :mode, :name, :attr, :length, :load_addr, :exec_addr,
                  :timestamp, :start_record

    def self.empty(index = nil)
      entry = new
      entry.mode = index&.zero? ? MODE_SWAP_EMPTY : MODE_UNUSED
      entry.name = ""
      entry.attr = 0
      entry.length = 0
      entry.load_addr = 0
      entry.exec_addr = 0
      entry.timestamp = "\x00".b * 4
      entry.start_record = 0
      entry
    end

    def self.parse(raw, index: nil)
      entry = new
      entry.mode = raw.getbyte(0)
      entry.name = raw.byteslice(1, 17).bytes.take_while { |b| b != EMPTY_NAME_BYTE && b != 0 }.pack("C*")
      entry.attr = raw.getbyte(18)
      entry.length = MZD88.le16(raw, 20)
      entry.load_addr = MZD88.le16(raw, 22)
      entry.exec_addr = MZD88.le16(raw, 24)
      entry.timestamp = raw.byteslice(26, 4)
      entry.start_record = MZD88.le16(raw, 30)
      entry
    end

    def used?
      ![MODE_UNUSED, MODE_SWAP_EMPTY].include?(@mode)
    end

    def mode_name
      MODE_NAMES.fetch(@mode, "0x%02X" % @mode)
    end

    def byte_length
      @mode == MODE_BRD ? @length * 32 : @length
    end

    def to_bytes
      raw = "\x00".b * DIRECTORY_ENTRY_SIZE
      raw.setbyte(0, @mode || MODE_UNUSED)
      name_bytes = (@name || "").encode("ASCII", invalid: :replace, undef: :replace, replace: "?").bytes.first(17)
      17.times { |i| raw.setbyte(1 + i, name_bytes[i] || EMPTY_NAME_BYTE) }
      raw.setbyte(18, @attr || 0)
      raw.setbyte(19, 0)
      MZD88.put_le16(raw, 20, @length || 0)
      MZD88.put_le16(raw, 22, @load_addr || 0)
      MZD88.put_le16(raw, 24, @exec_addr || 0)
      raw[26, 4] = @timestamp || "\x00".b * 4
      MZD88.put_le16(raw, 30, @start_record || 0)
      raw
    end
  end

  class Disk
    attr_reader :image

    def initialize(image = D88Image.new)
      @image = image
    end

    def self.load(path)
      new(D88Image.load(path))
    end

    def self.blank(title: "BLANK")
      disk = new(D88Image.new(D88Image.blank_bytes(title: title)))
      disk.format_data_disk!
      disk
    end

    def save(path)
      @image.save(path)
    end

    def format_data_disk!
      TOTAL_RECORDS.times { |record| write_record(record, "\xBF".b * SECTOR_SIZE) }
      0x000f.times { |record| write_record(record, "\x00".b * SECTOR_SIZE) }
      boot_record = read_record(0)
      boot_record.setbyte(0, 0x04)
      write_record(0, boot_record)
      DIRECTORY_ENTRIES.times { |i| write_directory_entry(i, DirectoryEntry.empty(i)) }
      write_bitmap(Array.new(DATA_BLOCKS, false))
      self
    end

    def list_entries
      DIRECTORY_ENTRIES.times.map { |i| [i, read_directory_entry(i)] }.select { |_i, e| e.used? }
    end

    def find_entry(name)
      target = disk_name_string(name)
      list_entries.find { |_i, e| e.name == target }
    end

    def add_file(source_path, disk_name: nil, mode: nil, force: false, load_addr: nil, exec_addr: nil)
      data = File.binread(source_path)
      disk_name ||= File.basename(source_path).sub(/\.[^.]*\z/, "")
      mode ||= infer_mode(source_path)
      disk_name = disk_name_string(disk_name)
      raise Error, "name is empty" if disk_name.empty?
      raise Error, "name is longer than 17 bytes: #{disk_name}" if disk_name.bytesize > 17
      raise Error, "file already exists: #{disk_name}" if !force && find_entry(disk_name)

      delete_file(disk_name) if force && find_entry(disk_name)

      entry_index = find_empty_directory_index
      raise Error, "directory is full" unless entry_index

      if mode == MODE_BRD
        start_record, blocks = write_brd_data(data)
        length = (data.bytesize + 31) / 32
      elsif mode == MODE_BSD
        start_record, blocks = write_bsd_data(data)
        length = data.bytesize
      else
        start_record, blocks = write_linear_data(data)
        length = data.bytesize
      end

      entry = DirectoryEntry.empty(entry_index)
      entry.mode = mode
      entry.name = disk_name
      entry.length = length
      entry.load_addr = load_addr || 0
      entry.exec_addr = exec_addr || 0
      entry.start_record = start_record
      entry.timestamp = encode_time(Time.now)
      write_directory_entry(entry_index, entry)
      mark_blocks(blocks, true)
      entry
    end

    def rename_file(old_name, new_name)
      new_name = disk_name_string(new_name)
      raise Error, "name is empty" if new_name.empty?
      raise Error, "name is longer than 17 bytes: #{new_name}" if new_name.bytesize > 17
      raise Error, "file already exists: #{new_name}" if find_entry(new_name)

      found = find_entry(old_name)
      raise Error, "file not found: #{old_name}" unless found

      index, entry = found
      entry.name = new_name
      entry.timestamp = encode_time(Time.now)
      write_directory_entry(index, entry)
      entry
    end

    def delete_all_files
      entries = list_entries
      entries.each { |_index, entry| delete_file(entry.name) }
      entries.map(&:last)
    end

    def free_blocks
      used_blocks.count(false)
    end

    def free_bytes
      free_blocks * BLOCK_FACTOR * SECTOR_SIZE
    end

    def used_file_blocks
      used_blocks.count(true)
    end

    def delete_file(name)
      found = find_entry(name)
      raise Error, "file not found: #{name}" unless found

      index, entry = found
      blocks =
        case entry.mode
        when MODE_BRD then brd_blocks(entry)
        when MODE_BSD then bsd_blocks(entry)
        else linear_blocks(entry)
        end
      blocks.each { |block| write_block(block, "\xBF".b * (BLOCK_FACTOR * SECTOR_SIZE)) }
      mark_blocks(blocks, false)
      write_directory_entry(index, DirectoryEntry.empty(index))
      entry
    end

    def extract_file(name, output_path)
      found = find_entry(name)
      raise Error, "file not found: #{name}" unless found

      _index, entry = found
      data =
        case entry.mode
        when MODE_BRD then read_brd_data(entry)
        when MODE_BSD then read_bsd_data(entry)
        else read_linear_data(entry)
        end
      File.binwrite(output_path, data.byteslice(0, entry.byte_length))
    end

    def read_directory_entry(index)
      record = DIRECTORY_START_RECORD + (index * DIRECTORY_ENTRY_SIZE / SECTOR_SIZE)
      offset = (index * DIRECTORY_ENTRY_SIZE) % SECTOR_SIZE
      DirectoryEntry.parse(read_record(record).byteslice(offset, DIRECTORY_ENTRY_SIZE), index: index)
    end

    def write_directory_entry(index, entry)
      record = DIRECTORY_START_RECORD + (index * DIRECTORY_ENTRY_SIZE / SECTOR_SIZE)
      offset = (index * DIRECTORY_ENTRY_SIZE) % SECTOR_SIZE
      data = read_record(record)
      data[offset, DIRECTORY_ENTRY_SIZE] = entry.to_bytes
      write_record(record, data)
    end

    def read_record(record)
      track_index, sector = record_to_track_sector(record)
      MZD88.invert(@image.sector_data(track_index, sector))
    end

    def write_record(record, data)
      raise Error, "record data must be #{SECTOR_SIZE} bytes" unless data.bytesize == SECTOR_SIZE

      track_index, sector = record_to_track_sector(record)
      @image.set_sector_data(track_index, sector, MZD88.invert(data))
    end

    private

    def record_to_track_sector(record)
      raise Error, "record out of range: #{record}" unless (0...TOTAL_RECORDS).cover?(record)

      cylinder = record / (HEADS * SECTORS_PER_TRACK)
      in_cylinder = record % (HEADS * SECTORS_PER_TRACK)
      head = in_cylinder < SECTORS_PER_TRACK ? 1 : 0
      sector = (in_cylinder % SECTORS_PER_TRACK) + 1
      track_index = cylinder * HEADS + head
      [track_index, sector]
    end

    def disk_name_string(name)
      name.to_s.encode("ASCII", invalid: :replace, undef: :replace, replace: "?")
    end

    def infer_mode(path)
      case File.extname(path).downcase
      when ".brd"
        MODE_BRD
      when ".obj", ".bin"
        MODE_OBJ
      when ".bsd", ".bas", ".txt"
        MODE_BSD
      when ".btx"
        MODE_BTX
      else
        MODE_BSD
      end
    end

    def bitmap_bytes
      read_record(BITMAP_RECORD)
    end

    def write_bitmap(used)
      data = "\x00".b * SECTOR_SIZE
      data.setbyte(0, 0x01) # volume number for data disk
      data.setbyte(1, DATA_OFFSET_BLOCK)
      MZD88.put_le16(data, 2, DATA_OFFSET_BLOCK + used.count(true))
      MZD88.put_le16(data, 4, TOTAL_BLOCKS)
      data.setbyte(255, BLOCK_FACTOR - 1)
      used.each_with_index do |flag, i|
        next unless flag

        byte_index = 6 + i / 8
        data.setbyte(byte_index, data.getbyte(byte_index) | (1 << (i % 8)))
      end
      write_record(BITMAP_RECORD, data)
    end

    def used_blocks
      data = bitmap_bytes
      DATA_BLOCKS.times.map do |i|
        byte = data.getbyte(6 + i / 8)
        (byte & (1 << (i % 8))) != 0
      end
    end

    def mark_blocks(blocks, used)
      bitmap = used_blocks
      blocks.each do |block|
        index = block - DATA_OFFSET_BLOCK
        raise Error, "block out of data area: #{block}" unless (0...bitmap.length).cover?(index)

        bitmap[index] = used
      end
      write_bitmap(bitmap)
    end

    def find_free_run(block_count)
      bitmap = used_blocks
      run_start = nil
      run_length = 0
      bitmap.each_with_index do |used, i|
        if used
          run_start = nil
          run_length = 0
        else
          run_start ||= i
          run_length += 1
          return DATA_OFFSET_BLOCK + run_start if run_length >= block_count
        end
      end
      nil
    end

    def find_free_blocks(block_count)
      bitmap = used_blocks
      result = []
      bitmap.each_with_index do |used, i|
        result << DATA_OFFSET_BLOCK + i unless used
        return result if result.length == block_count
      end
      nil
    end

    def find_empty_directory_index
      DIRECTORY_ENTRIES.times.find { |i| !read_directory_entry(i).used? && i != 0 }
    end

    def write_linear_data(data)
      block_count = [(data.bytesize + (BLOCK_FACTOR * SECTOR_SIZE) - 1) / (BLOCK_FACTOR * SECTOR_SIZE), 1].max
      start_block = find_free_run(block_count)
      raise Error, "not enough contiguous free space" unless start_block

      payload = data.b.ljust(block_count * BLOCK_FACTOR * SECTOR_SIZE, "\x00")
      block_count.times do |i|
        write_block(start_block + i, payload.byteslice(i * BLOCK_FACTOR * SECTOR_SIZE, BLOCK_FACTOR * SECTOR_SIZE))
      end
      [start_block * BLOCK_FACTOR, block_count.times.map { |i| start_block + i }]
    end

    def read_linear_data(entry)
      block_count = [(entry.byte_length + (BLOCK_FACTOR * SECTOR_SIZE) - 1) / (BLOCK_FACTOR * SECTOR_SIZE), 1].max
      start_block = entry.start_record / BLOCK_FACTOR
      block_count.times.map { |i| read_block(start_block + i) }.join.b
    end

    def linear_blocks(entry)
      block_count = [(entry.byte_length + (BLOCK_FACTOR * SECTOR_SIZE) - 1) / (BLOCK_FACTOR * SECTOR_SIZE), 1].max
      start_block = entry.start_record / BLOCK_FACTOR
      block_count.times.map { |i| start_block + i }
    end

    def write_bsd_data(data)
      record_count = [(data.bytesize + 253) / 254, 1].max
      block_count = [(record_count + BLOCK_FACTOR - 1) / BLOCK_FACTOR, 1].max
      start_block = find_free_run(block_count)
      raise Error, "not enough contiguous free space" unless start_block

      start_record = start_block * BLOCK_FACTOR
      block_count.times { |i| write_block(start_block + i, "\xBF".b * (BLOCK_FACTOR * SECTOR_SIZE)) }

      record_count.times do |i|
        record = start_record + i
        next_record = i == record_count - 1 ? 0 : record + 1
        chunk = data.byteslice(i * 254, 254) || "".b
        record_data = chunk.ljust(SECTOR_SIZE, "\x00")
        MZD88.put_le16(record_data, 254, next_record)
        write_record(record, record_data)
      end

      [start_record, block_count.times.map { |i| start_block + i }]
    end

    def read_bsd_data(entry)
      records = bsd_records(entry)
      records.map { |record| read_record(record).byteslice(0, 254) }.join.b
    end

    def bsd_records(entry)
      records = []
      record = entry.start_record
      expected_records = [(entry.byte_length + 253) / 254, 1].max
      expected_records.times do
        records << record
        data = read_record(record)
        record = MZD88.le16(data, 254)
        break if record.zero?
      end
      records
    end

    def bsd_blocks(entry)
      bsd_records(entry).map { |record| record / BLOCK_FACTOR }.uniq
    end

    def write_brd_data(data)
      chunk_count = [(data.bytesize + 4095) / 4096, 1].max
      data_blocks_needed = chunk_count * 8
      pointer_block = find_free_run(1)
      raise Error, "not enough free space for BRD pointer block" unless pointer_block

      mark_blocks([pointer_block], true)
      chunk_blocks = []
      begin
        chunk_count.times do
          start = find_free_run(8)
          unless start
            fallback = find_free_blocks(8)
            raise Error, "not enough free space for BRD data" unless fallback
            raise Error, "fragmented BRD 4KB chunks are not supported yet" unless fallback.each_cons(2).all? { |a, b| b == a + 1 }
            start = fallback.first
          end
          blocks = 8.times.map { |i| start + i }
          mark_blocks(blocks, true)
          chunk_blocks << start
        end
      rescue
        mark_blocks([pointer_block] + chunk_blocks.flat_map { |b| 8.times.map { |i| b + i } }, false)
        raise
      end

      pointer = "\x00".b * SECTOR_SIZE
      chunk_blocks.each_with_index do |block, i|
        MZD88.put_le16(pointer, i * 2, block * BLOCK_FACTOR)
      end
      write_record(pointer_block * BLOCK_FACTOR, pointer)
      write_record(pointer_block * BLOCK_FACTOR + 1, "\xBF".b * SECTOR_SIZE)

      payload = data.b.ljust(data_blocks_needed * BLOCK_FACTOR * SECTOR_SIZE, "\x00")
      chunk_blocks.each_with_index do |start_block, chunk_index|
        8.times do |i|
          offset = (chunk_index * 8 + i) * BLOCK_FACTOR * SECTOR_SIZE
          write_block(start_block + i, payload.byteslice(offset, BLOCK_FACTOR * SECTOR_SIZE))
        end
      end

      all_blocks = [pointer_block] + chunk_blocks.flat_map { |b| 8.times.map { |i| b + i } }
      [pointer_block * BLOCK_FACTOR, all_blocks]
    end

    def read_brd_data(entry)
      pointer = read_record(entry.start_record)
      out = +"".b
      128.times do |i|
        record = MZD88.le16(pointer, i * 2)
        break if record.zero?

        start_block = record / BLOCK_FACTOR
        8.times { |j| out << read_block(start_block + j) }
      end
      out
    end

    def brd_blocks(entry)
      pointer = read_record(entry.start_record)
      blocks = [entry.start_record / BLOCK_FACTOR]
      128.times do |i|
        record = MZD88.le16(pointer, i * 2)
        break if record.zero?

        start_block = record / BLOCK_FACTOR
        8.times { |j| blocks << start_block + j }
      end
      blocks
    end

    def read_block(block)
      record = block * BLOCK_FACTOR
      read_record(record) + read_record(record + 1)
    end

    def write_block(block, data)
      raise Error, "block data must be #{BLOCK_FACTOR * SECTOR_SIZE} bytes" unless data.bytesize == BLOCK_FACTOR * SECTOR_SIZE

      record = block * BLOCK_FACTOR
      write_record(record, data.byteslice(0, SECTOR_SIZE))
      write_record(record + 1, data.byteslice(SECTOR_SIZE, SECTOR_SIZE))
    end

    def encode_time(time)
      # The MZ directory stores a packed BCD-like timestamp. Exact preservation is
      # not required for file loading, but this keeps entries non-zero and readable.
      year = time.year % 100
      month = time.month
      day = time.day
      hour = time.hour
      min = time.min
      [
        ((year / 10) << 4) | (year % 10),
        ((month / 10) << 4) | (month % 10),
        ((day / 10) << 4) | (day % 10),
        ((hour / 10) << 4) | (hour % 10)
      ].pack("C*")
    end
  end

  class CLI
    def self.run(argv)
      new.run(argv)
    rescue Error => e
      warn "error: #{e.message}"
      exit 1
    end

    def run(argv)
      command = parse_command(argv.shift)
      case command
      when "blank"
        blank(argv)
      when "list", "ls"
        list(argv)
      when "add"
        add(argv)
      when "delete", "del", "rm"
        delete(argv)
      when "rename", "ren", "mv"
        rename(argv)
      when "extract", "get"
        extract(argv)
      else
        usage
        exit(command ? 1 : 0)
      end
    end

    private

    def parse_command(raw_command)
      return nil unless raw_command&.start_with?("-")

      raw_command.sub(/\A-+/, "")
    end

    def blank(argv)
      title = "BLANK"
      opts = OptionParser.new do |o|
        o.on("--title TITLE") { |v| title = v }
      end
      opts.parse!(argv)
      path = argv.fetch(0) { raise Error, "missing output D88 path" }
      Disk.blank(title: title).save(path)
    end

    def list(argv)
      show_free = false
      opts = OptionParser.new do |o|
        o.on("--free") { show_free = true }
      end
      opts.parse!(argv)
      path = argv.fetch(0) { raise Error, "missing D88 path" }
      disk = Disk.load(path)
      puts "idx mode name              bytes  start  load  exec"
      disk.list_entries.each do |index, entry|
        puts "%3d %-4s %-17s %6d  %04X  %04X  %04X" % [
          index, entry.mode_name, entry.name, entry.byte_length,
          entry.start_record, entry.load_addr, entry.exec_addr
        ]
      end
      puts "free: #{disk.free_bytes} bytes (#{disk.free_blocks} blocks)" if show_free
    end

    def add(argv)
      mode = nil
      name = nil
      force = false
      load_addr = nil
      exec_addr = nil
      opts = OptionParser.new do |o|
        o.on("--mode MODE", "bsd, brd, btx, obj") { |v| mode = parse_mode(v) }
        o.on("--name NAME") { |v| name = v }
        o.on("--force") { force = true }
        o.on("--load-addr ADDR") { |v| load_addr = parse_word(v, "--load-addr") }
        o.on("--exec-addr ADDR") { |v| exec_addr = parse_word(v, "--exec-addr") }
      end
      opts.parse!(argv)
      image_path = argv.fetch(0) { raise Error, "missing D88 path" }
      source_paths = argv.drop(1)
      raise Error, "missing source file path" if source_paths.empty?
      raise Error, "--name can be used only when adding one file" if name && source_paths.length > 1
      if (load_addr || exec_addr) && mode && mode != MODE_OBJ
        raise Error, "--load-addr/--exec-addr can be used only with OBJ files"
      end

      disk = File.exist?(image_path) ? Disk.load(image_path) : Disk.blank
      entries = source_paths.map do |source_path|
        source_mode = mode || parse_mode_from_path(source_path)
        if (load_addr || exec_addr) && source_mode != MODE_OBJ
          raise Error, "--load-addr/--exec-addr can be used only with OBJ files"
        end
        disk.add_file(
          source_path,
          disk_name: name,
          mode: source_mode,
          force: force,
          load_addr: load_addr,
          exec_addr: exec_addr
        )
      end
      disk.save(image_path)
      entries.each do |entry|
        puts "added #{entry.name} #{entry.mode_name} #{entry.byte_length} bytes"
      end
    end

    def delete(argv)
      delete_all = false
      opts = OptionParser.new do |o|
        o.on("--all") { delete_all = true }
      end
      opts.parse!(argv)
      image_path = argv.fetch(0) { raise Error, "missing D88 path" }
      names = argv.drop(1)
      disk = Disk.load(image_path)
      entries =
        if delete_all
          raise Error, "--all cannot be combined with file names" unless names.empty?

          disk.delete_all_files
        else
          raise Error, "missing file name" if names.empty?

          names.map { |name| disk.delete_file(name) }
        end
      disk.save(image_path)
      entries.each { |entry| puts "deleted #{entry.name}" }
    end

    def rename(argv)
      image_path = argv.fetch(0) { raise Error, "missing D88 path" }
      old_name = argv.fetch(1) { raise Error, "missing old file name" }
      new_name = argv.fetch(2) { raise Error, "missing new file name" }
      disk = Disk.load(image_path)
      entry = disk.rename_file(old_name, new_name)
      disk.save(image_path)
      puts "renamed #{old_name} -> #{entry.name}"
    end

    def extract(argv)
      image_path = argv.fetch(0) { raise Error, "missing D88 path" }
      name = argv.fetch(1) { raise Error, "missing file name" }
      output_path = argv.fetch(2) { raise Error, "missing output path" }
      Disk.load(image_path).extract_file(name, output_path)
    end

    def parse_mode(value)
      case value.downcase
      when "obj" then MODE_OBJ
      when "btx" then MODE_BTX
      when "bsd", "bas", "txt" then MODE_BSD
      when "brd" then MODE_BRD
      else
        raise Error, "unknown mode: #{value}"
      end
    end

    def parse_mode_from_path(path)
      case File.extname(path).downcase
      when ".obj", ".bin" then MODE_OBJ
      when ".btx" then MODE_BTX
      when ".bsd", ".bas", ".txt" then MODE_BSD
      when ".brd" then MODE_BRD
      else MODE_BSD
      end
    end

    def parse_word(value, option_name)
      text = value.to_s
      number =
        if text.start_with?("0x", "0X")
          Integer(text, 16)
        elsif text.end_with?("h", "H")
          Integer(text[0...-1], 16)
        else
          Integer(text, 10)
        end
      raise Error, "#{option_name} out of range: #{value}" unless (0..0xffff).cover?(number)

      number
    rescue ArgumentError
      raise Error, "invalid #{option_name}: #{value}"
    end

    def usage
      puts <<~USAGE
        usage:
          ruby mzd88.rb -blank OUTPUT.d88 [--title TITLE]
          ruby mzd88.rb -list IMAGE.d88 [--free]
          ruby mzd88.rb -add IMAGE.d88 SOURCE... [--name NAME] [--mode bsd|brd|btx|obj] [--force] [--load-addr ADDR] [--exec-addr ADDR]
          ruby mzd88.rb -extract IMAGE.d88 NAME OUTPUT
          ruby mzd88.rb -delete IMAGE.d88 NAME... | --all
          ruby mzd88.rb -rename IMAGE.d88 OLD_NAME NEW_NAME
      USAGE
    end
  end
end

MZD88::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
