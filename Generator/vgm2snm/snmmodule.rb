#! /usr/bin/ruby

# This Source Code Form is subject to the terms of the Mozilla Public License,
# v. 2.0. If a copy of the MPL was not distributed with this file, You can
# obtain one at http://mozilla.org/MPL/2.0/.

require_relative "snmfile"

CPU_RATE = 630000000.0 / 176.0

PERIODS = (0..95).map do |x|
  period = CPU_RATE / 32.0 / (440.0 * 2.0 ** ((x - 45.0) / 12.0))
  period > 0x3FF ? 0x3FF : period.round
end

LOOKUP = (0..1023).map do |period|
  n = Math.log2(CPU_RATE / 32.0 / period / 440.0) * 12.0 + 45.0
  n = n > 95 ? 95 : (n < 21 ? 21 : n.round)
  real_period = PERIODS[n]
  [n % 12 + 1, n / 12, real_period - period]
end

module VGM2SNM
  module SNM
    EF = {
      NONE: 0,
      SPEED: 1,
      JUMP: 2,
      SKIP: 3,
      HALT: 4,
      VOLUME: 5,
      PORTAMENTO: 6,
      ARPEGGIO: 10,
      VIBRATO: 11,
      TREMOLO: 12,
      PITCH: 13,
      DELAY: 14,
      PORTA_UP: 16,
      PORTA_DOWN: 17,
      DUTY_CYCLE: 18,
      SLIDE_UP: 20,
      SLIDE_DOWN: 21,
      VOLUME_SLIDE: 22,
      NOTE_CUT: 23,
      SN_CONTROL: 24,
    }

    class NoteBase
      attr_reader :note, :octave, :inst, :vol
      attr_reader :fx

      def initialize
        @note, @octave, @inst, @vol = 0, 0, 0x40, 0x10
        @fx = Array.new(4) { [0, 0] }
      end

      def empty?(fxcount = 4)
        @note == 0 && @inst == 0x40 && @vol == 0x10 &&
          @fx.take(fxcount).all? {|x| x[0] == 0}
      end

      def get_data(fxcount = 4)
        @fx.take(fxcount).reduce(
          [@note, @octave, @inst, @vol], &:+).map(&:chr).join
      end
    end

    class HaltNote < NoteBase
      def initialize
        super
        @note = 14
      end
    end

    class SquareNote < NoteBase
      def initialize(period = nil, vol = nil)
        super()
        if period
          period = LOOKUP[period]
          @note = period[0]
          @octave = period[1]
          @fx[0] = [EF[:PITCH], 0x80 + period[2]]
        end
        @inst = 0 if period
        @vol = vol if vol
      end
    end

    class NoiseNote < NoteBase
      def initialize(shift = nil, fb = nil, vol = nil)
        super()
        @note = ((2 - shift) & 0x03) + 1 if shift
        @fx[0] = [EF[:DUTY_CYCLE], fb & 0x01] if fb
        @inst = 0 if shift
        @vol = vol if vol
      end
    end

    class Pattern
      attr_reader :rows
      attr_accessor :fxcount

      def initialize(fxcount)
        @rows = []
        @fxcount = fxcount
      end

      def empty?
        @rows.count {|x| x} == 0
      end

      def get_note(row)
        @rows[row] = NoteBase.new if !@rows[row]
        @rows[row]
      end

      def clean
        @rows.each_with_index do |v, k|
          @rows[k] = nil if v && v.empty?
        end
      end

      def get_data
        @rows.map.with_index do |v, k|
          v ? [k].pack("I<") + v.get_data(@fxcount) : ""
        end.reduce([@rows.count {|x| x}].pack("I<"), &:+)
      end
    end

    class Track
      attr_reader :patterns
      attr_reader :fxcount

      def initialize
        @patterns = []
      end

      def get_pattern(index)
        @patterns[index] = Pattern.new(@fxcount) if !@patterns[index]
        @patterns[index]
      end

      def fxcount=(fxcount)
        @fxcount = fxcount
        @patterns.each {|x| x.fxcount = fxcount if x}
      end
    end

    class Song
      attr_accessor :tempo, :speed, :title, :rows
      attr_reader :frames
      attr_reader :tracks

      def initialize(track_count)
        @title = "New song"
        @tempo = 150
        @speed = 6
        @rows = 64
        @frames = 1
        @frame_list = [Array.new(track_count, 0)]
        @tracks = Array.new(track_count) {Track.new}
      end

      def insert_frame(pos)
        @frames += 1
        @frame_list.insert pos, Array.new(@frame_list[0].length, 0)
      end

      def get_frame_pattern(frame, track)
        index = @frame_list[frame][track]
        @tracks[track].get_pattern(index)
      end

      def set_frame_pattern(frame, track, pattern)
        @frame_list[frame][track] = pattern
        @tracks[track].get_pattern(pattern)
      end

      def get_frame_data
        [@frames, @speed, @tempo, @rows].pack("I<4") +
          @frame_list.flatten.map(&:chr).join
      end
    end

    class Module
      attr_accessor :title, :author, :copyright
      attr_accessor :refresh_rate
      attr_reader :track_count
      attr_accessor :comment, :comment_show
      attr_reader :songs

      def initialize(track_count = 4)
        @title, @author, @copyright = "", "", ""
        @refresh_rate = 60
        @track_count = track_count
        @comment, @comment_show = "", false
        @songs = [Song.new(track_count)]
      end

      def save(filename)
        File.open(filename, "wb") do |f|
          f.write "SnevenTracker Module\x40\x04\x00\x00"

          [
            "Params", "Info", "Header", "Instruments", "Sequences",
            "Frames", "Patterns", "Comments",
          ].each do |name|
            f.write Chunk.const_get(name).new(self).get_chunk
          end

          f.write "END"
        end
      end
    end
  end
end
