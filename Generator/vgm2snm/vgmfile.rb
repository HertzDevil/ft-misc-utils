#! /usr/bin/ruby

# This Source Code Form is subject to the terms of the Mozilla Public License,
# v. 2.0. If a copy of the MPL was not distributed with this file, You can
# obtain one at http://mozilla.org/MPL/2.0/.

require_relative "snmfile"
require "zlib"

class Array
  if !method_defined? :to_h
    def to_h
      hsh = {}
      self.each {|k, v| hsh[k] = v}
      hsh
    end
  end
end

module VGM2SNM
  class VGMFile
    SAMPLE_RATE = 44100
    SAMPLES_60Hz = SAMPLE_RATE / 60
    SAMPLES_50Hz = SAMPLE_RATE / 50
    CHANNEL_COUNT = {
      SN76489: 4,
    }

    attr_reader :title, :album, :system, :artist,
                :title_jp, :album_jp, :system_jp, :artist_jp,
                :date, :ripper, :comment

    attr_reader :refresh_rate
    attr_reader :last_cmd

    def initialize(filename)
      @clock = {}

      File.open(filename, "rb") do |f|
        bin = f.read
        buffer = ""
        begin
          zstream = Zlib::Inflate.new(16 + Zlib::MAX_WBITS)
          buffer = zstream.inflate(bin)
          zstream.finish
        rescue Zlib::DataError
          buffer = bin
        ensure
          zstream.close
        end

        header_base = buffer[0, 0x24].unpack "a4I<8"
        raise "Not a VGM file" unless
          header_base[0] == "Vgm "
        raise "Invalid VGM file size" unless
          header_base[1] == buffer.length - 4
        raise "Dual chip is not implemented" unless
          (header_base[3] & (1 << 31)) == 0 && (header_base[4] & (1 << 31)) == 0

        @version = header_base[2]
        @clock[:SN76489], @clock[:YM2413] = header_base[3], header_base[4]
        @clock.select! {|k, v| v != 0}

        @cmd_base = @clock.map do |k, v|
          [k, Array.new(CHANNEL_COUNT[k] + 1) { { } }]
        end.to_h
        if @cmd_base[:SN76489]
          @sn76489_latch = 0
          @sn76489_period = [0, 0, 0]
          @sn76489_vol = [0, 0, 0, 0] # no side effects even when always written
        end

        data_start = @version >= 0x150 ?
          (buffer[0x34, 4].unpack("I<")[0] + 0x34) : 0x40
        @total_samples = header_base[6]
        @loop_samples = header_base[8]

        @data = buffer.bytes.drop(data_start)
        @data_ptr = 0
        @loop_ptr = header_base[7] != 0 ?
          (header_base[7] + 0x1C - data_start) : nil
        @wait = 0

        if header_base[5] != 0
          gd_offset = header_base[5] + 0x14
          gd_ident, gd_version, gd_size = buffer[gd_offset, 12].unpack "a4I<I<"
          raise "Invalid GD3 tag" unless gd_ident == "Gd3 "
          gd_buf = buffer[gd_offset + 0x0C, gd_size]
          gd_labels = (0xFF.chr + 0xFE.chr + gd_buf).encode(
            "UTF-8", "UTF-16").split "\x00" rescue Array.new("", 11)
          @title, @title_jp, @album, @album_jp, @system, @system_jp,
            @artist, @artist_jp, @date, @rip, @comment = *gd_labels
        end

        # default is never 50 Hz
        @refresh_rate = @version >= 0x101 ?
          buffer[0x24, 4].unpack("I<")[0] : 0x3C
      end
    end

    def read_cmds(samples)
      @last_cmd = @cmd_base.map do |chip, cmds|
        [chip, Array.new(CHANNEL_COUNT[chip] + 1) { { } }]
      end.to_h

      while true
        if samples > @wait
          samples -= @wait
          @wait = 0
        else
          @wait -= samples
          samples = 0
          break
        end
        byte = next_byte
        @@ACTIONS[byte].bind(self).call(byte)
      end

      @last_cmd
    end

  private
    def next_byte
      byte = @data[@data_ptr]
      @data_ptr += 1
      byte
    end

    def a_gg_stereo(byte)
      cmd = @last_cmd[:SN76489]
      val = next_byte
      (0..3).each do |x|
        cmd[x + 1][:pan] = [(val & (1 << (x + 4))) != 0, (val & (1 << x)) != 0]
      end
    end
    def a_gg_write(byte)
      cmd = @last_cmd[:SN76489]
      case val = next_byte
      when 0x80..0x8F, 0xA0..0xAF, 0xC0..0xCF
        @sn76489_latch = (val - 0x80) >> 5
        per = (@sn76489_period[@sn76489_latch] & 0x3F0) | (val & 0x00F)
        @sn76489_period[@sn76489_latch] = per
        cmd[@sn76489_latch + 1][:period] = per
        # no side effects
        cmd[@sn76489_latch + 1][:vol] = @sn76489_vol[@sn76489_latch]
      when 0xE0..0xEF
        # @sn76489_latch = 3
        cmd[4][:feedback] = ((val & 0x04) >> 2) ^ 0x01
        cmd[4][:rate] = val & 0x03
        cmd[4][:vol] = @sn76489_vol[3] # no side effects
      when 0x90..0x9F, 0xB0..0xBF, 0xD0..0xDF, 0xF0..0xFF
        @sn76489_vol[(val - 0x90) >> 5] = 0xF ^ (val & 0xF)
        cmd[(val - 0x70) >> 5][:vol] = 0xF ^ (val & 0xF)
      else # second byte
        per = (@sn76489_period[@sn76489_latch] & 0x00F) | ((val & 0x3F) << 4)
        @sn76489_period[@sn76489_latch] = per
        cmd[@sn76489_latch + 1][:period] = per
      end
    end

    def a_wait(byte)
      @wait += next_byte
      @wait += next_byte << 8
    end
    def a_wait_60hz(byte)
      @wait += SAMPLES_60Hz
    end
    def a_wait_50hz(byte)
      @wait += SAMPLES_50Hz
    end
    def a_wait_fast(byte)
      @wait += byte - 0x6F
    end
    def a_end(byte)
      @data_ptr = @loop_ptr
      if !@data_ptr
        @wait = Float::INFINITY
        @last_cmd[:halt] = true
      else
        @last_cmd[:loop] = true
      end
    end

    def a_sgen_2a(byte)
      @wait += byte - 0x80
    end

    def a_cmd1(byte)
      next_byte
    end
    def a_cmd2(byte)
      next_byte; next_byte
    end
    def a_cmd3(byte)
      next_byte; next_byte; next_byte
    end
    def a_cmd4(byte)
      next_byte; next_byte; next_byte; next_byte
    end

    def a_invalid(byte)
      raise(sprintf("Unknown command %02X at 0x%X", byte, @data_ptr - 1))
    end
    def a_data_block(byte)
      raise "Invalid data block" unless next_byte == 0x66
      data_type = next_byte
      data_size = next_byte
      data_size += next_byte << 8
      data_size += next_byte << 16
      data_size += next_byte << 24
      # data_buf = @data[@data_ptr, data_size]
      @data_ptr += data_size
    end
    def a_pcm_write(byte)
      raise "Invalid RAM write" unless next_byte == 0x66
      @data_ptr += 10
    end

    def a_st_setup(byte)
      puts "Stream control is not implemented"
      @data_ptr += 4
    end
    def a_st_set(byte)
      puts "Stream control is not implemented"
      @data_ptr += 4
    end
    def a_st_freq(byte)
      puts "Stream control is not implemented"
      @data_ptr += 5
    end
    def a_st_start(byte)
      puts "Stream control is not implemented"
      @data_ptr += 10
    end
    def a_st_stop(byte)
      puts "Stream control is not implemented"
      @data_ptr += 1
    end
    def a_st_fast(byte)
      puts "Stream control is not implemented"
      @data_ptr += 4
    end

    def self.im(x) instance_method(x) end

    @@ACTIONS = [
      # 0x00 - 0x0F
      im(:a_invalid), im(:a_invalid), im(:a_invalid), im(:a_invalid),
      im(:a_invalid), im(:a_invalid), im(:a_invalid), im(:a_invalid),
      im(:a_invalid), im(:a_invalid), im(:a_invalid), im(:a_invalid),
      im(:a_invalid), im(:a_invalid), im(:a_invalid), im(:a_invalid),

      # 0x10 - 0x1F
      im(:a_invalid), im(:a_invalid), im(:a_invalid), im(:a_invalid),
      im(:a_invalid), im(:a_invalid), im(:a_invalid), im(:a_invalid),
      im(:a_invalid), im(:a_invalid), im(:a_invalid), im(:a_invalid),
      im(:a_invalid), im(:a_invalid), im(:a_invalid), im(:a_invalid),

      # 0x20 - 0x2F
      im(:a_invalid), im(:a_invalid), im(:a_invalid), im(:a_invalid),
      im(:a_invalid), im(:a_invalid), im(:a_invalid), im(:a_invalid),
      im(:a_invalid), im(:a_invalid), im(:a_invalid), im(:a_invalid),
      im(:a_invalid), im(:a_invalid), im(:a_invalid), im(:a_invalid),

      # 0x30 - 0x3F
      im(:a_cmd1), im(:a_cmd1), im(:a_cmd1), im(:a_cmd1),
      im(:a_cmd1), im(:a_cmd1), im(:a_cmd1), im(:a_cmd1),
      im(:a_cmd1), im(:a_cmd1), im(:a_cmd1), im(:a_cmd1),
      im(:a_cmd1), im(:a_cmd1), im(:a_cmd1), im(:a_cmd1),

      # 0x40 - 0x4F
      im(:a_cmd1), im(:a_cmd1), im(:a_cmd1), im(:a_cmd1),
      im(:a_cmd1), im(:a_cmd1), im(:a_cmd1), im(:a_cmd1),
      im(:a_cmd1), im(:a_cmd1), im(:a_cmd1), im(:a_cmd1),
      im(:a_cmd1), im(:a_cmd1), im(:a_cmd1), im(:a_gg_stereo),

      # 0x50 - 0x5F
      im(:a_gg_write), im(:a_cmd2), im(:a_cmd2), im(:a_cmd2),
      im(:a_cmd2), im(:a_cmd2), im(:a_cmd2), im(:a_cmd2),
      im(:a_cmd2), im(:a_cmd2), im(:a_cmd2), im(:a_cmd2),
      im(:a_cmd2), im(:a_cmd2), im(:a_cmd2), im(:a_cmd2),

      # 0x60 - 0x6F
      im(:a_invalid), im(:a_wait), im(:a_wait_60hz), im(:a_wait_50hz),
      im(:a_invalid), im(:a_invalid), im(:a_end), im(:a_data_block),
      im(:a_pcm_write), im(:a_invalid), im(:a_invalid), im(:a_invalid),
      im(:a_invalid), im(:a_invalid), im(:a_invalid), im(:a_invalid),

      # 0x70 - 0x7F
      im(:a_wait_fast), im(:a_wait_fast), im(:a_wait_fast), im(:a_wait_fast),
      im(:a_wait_fast), im(:a_wait_fast), im(:a_wait_fast), im(:a_wait_fast),
      im(:a_wait_fast), im(:a_wait_fast), im(:a_wait_fast), im(:a_wait_fast),
      im(:a_wait_fast), im(:a_wait_fast), im(:a_wait_fast), im(:a_wait_fast),

      # 0x80 - 0x8F
      im(:a_sgen_2a), im(:a_sgen_2a), im(:a_sgen_2a), im(:a_sgen_2a),
      im(:a_sgen_2a), im(:a_sgen_2a), im(:a_sgen_2a), im(:a_sgen_2a),
      im(:a_sgen_2a), im(:a_sgen_2a), im(:a_sgen_2a), im(:a_sgen_2a),
      im(:a_sgen_2a), im(:a_sgen_2a), im(:a_sgen_2a), im(:a_sgen_2a),

      # 0x90 - 0x9F
      im(:a_st_setup), im(:a_st_set), im(:a_st_freq), im(:a_st_start),
      im(:a_st_stop), im(:a_st_fast), im(:a_invalid), im(:a_invalid),
      im(:a_invalid), im(:a_invalid), im(:a_invalid), im(:a_invalid),
      im(:a_invalid), im(:a_invalid), im(:a_invalid), im(:a_invalid),

      # 0xA0 - 0xAF
      im(:a_cmd2), im(:a_cmd2), im(:a_cmd2), im(:a_cmd2),
      im(:a_cmd2), im(:a_cmd2), im(:a_cmd2), im(:a_cmd2),
      im(:a_cmd2), im(:a_cmd2), im(:a_cmd2), im(:a_cmd2),
      im(:a_cmd2), im(:a_cmd2), im(:a_cmd2), im(:a_cmd2),

      # 0xB0 - 0xBF
      im(:a_cmd2), im(:a_cmd2), im(:a_cmd2), im(:a_cmd2),
      im(:a_cmd2), im(:a_cmd2), im(:a_cmd2), im(:a_cmd2),
      im(:a_cmd2), im(:a_cmd2), im(:a_cmd2), im(:a_cmd2),
      im(:a_cmd2), im(:a_cmd2), im(:a_cmd2), im(:a_cmd2),

      # 0xC0 - 0xCF
      im(:a_cmd3), im(:a_cmd3), im(:a_cmd3), im(:a_cmd3),
      im(:a_cmd3), im(:a_cmd3), im(:a_cmd3), im(:a_cmd3),
      im(:a_cmd3), im(:a_cmd3), im(:a_cmd3), im(:a_cmd3),
      im(:a_cmd3), im(:a_cmd3), im(:a_cmd3), im(:a_cmd3),

      # 0xD0 - 0xDF
      im(:a_cmd3), im(:a_cmd3), im(:a_cmd3), im(:a_cmd3),
      im(:a_cmd3), im(:a_cmd3), im(:a_cmd3), im(:a_cmd3),
      im(:a_cmd3), im(:a_cmd3), im(:a_cmd3), im(:a_cmd3),
      im(:a_cmd3), im(:a_cmd3), im(:a_cmd3), im(:a_cmd3),

      # 0xE0 - 0xEF
      im(:a_cmd4), im(:a_cmd4), im(:a_cmd4), im(:a_cmd4),
      im(:a_cmd4), im(:a_cmd4), im(:a_cmd4), im(:a_cmd4),
      im(:a_cmd4), im(:a_cmd4), im(:a_cmd4), im(:a_cmd4),
      im(:a_cmd4), im(:a_cmd4), im(:a_cmd4), im(:a_cmd4),

      # 0xF0 - 0xFF
      im(:a_cmd4), im(:a_cmd4), im(:a_cmd4), im(:a_cmd4),
      im(:a_cmd4), im(:a_cmd4), im(:a_cmd4), im(:a_cmd4),
      im(:a_cmd4), im(:a_cmd4), im(:a_cmd4), im(:a_cmd4),
      im(:a_cmd4), im(:a_cmd4), im(:a_cmd4), im(:a_cmd4),
    ]
  end
end
