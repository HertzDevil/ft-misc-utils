#! /usr/bin/ruby

# This Source Code Form is subject to the terms of the Mozilla Public License,
# v. 2.0. If a copy of the MPL was not distributed with this file, You can
# obtain one at http://mozilla.org/MPL/2.0/.

require_relative "snmmodule"
require_relative "vgmfile"
require "getoptlong"

module VGM2SNM
  def main(args = {})
    puts "#{args[:input_name]} -> #{args[:output_name]} ..."
    vgm = VGMFile.new args[:input_name]
    snm = SNM::Module.new
    song = snm.songs[0]

    snm.title = vgm.album
    snm.author = vgm.artist
    snm.copyright = vgm.date
    snm.comment = vgm.comment
    song.title = vgm.title

    hz = args[:refresh_rate] || vgm.refresh_rate
    hz = 60 if hz == 0
    snm.refresh_rate = hz.round
    samplerate = args[:samples] || VGMFile::SAMPLE_RATE
    song.speed = 1
    song.tempo = (hz * 2.5).floor

    frame = 0
    row = 0
    tick = 0
    pat = (0...snm.track_count).map {|x| song.get_frame_pattern(frame, x)}
    (0...snm.track_count).each do |x|
      song.tracks[x].fxcount = x == 3 ? 3 : 2
    end
    song.rows = args[:rows] || 256
    bxx = nil

    next_frame = lambda do
      frame += 1
      return false if frame > 128
      song.insert_frame(frame)
      pat = (0...snm.track_count).map do |x|
        song.set_frame_pattern(frame, x, frame)
      end
      true
    end

    vgm.read_cmds(args[:skip]) if args[:skip]

    while true
#      samples = samplerate * (tick + 1) / hz - samplerate * tick / hz
      samples = samplerate / hz
      cmd = vgm.read_cmds(samples)
      if cmd[:halt]
        pat[3].get_note(row).fx[2] = [SNM::EF[:HALT], 0]
        break
      elsif cmd[:loop]
        if bxx
          if row == 0
            frame -= 1
            row = song.rows
          end
          song.get_frame_pattern(frame, 3).rows[row - 1].fx[2] =
            [SNM::EF[:JUMP], bxx]
          break
        else
          if row > 0
            pat[3].rows[row - 1].fx[2] = [SNM::EF[:SKIP], 0]
            break if not next_frame.call
          end
          row = 0
          bxx = frame
        end
      end

      cmd = cmd[:SN76489]

      (0..3).each do |x|
        writes = cmd[x + 1]
        pan_fx = [
          SNM::EF[:SN_CONTROL],
          case writes[:pan]
            when [true, true]; 0x10
            when [true, false]; 0x01
            when [false, true]; 0x1F
            when [false, false]; 0x00
          end,
#          (writes[:pan][0] ? 0x10 : 0) + (writes[:pan][1] ? 0x01 : 0)
        ] if writes[:pan]

        note = if x == 3
          SNM::NoiseNote.new(writes[:rate], writes[:feedback], writes[:vol])
        else
          SNM::SquareNote.new(writes[:period], writes[:vol])
        end
        note.fx[1] = pan_fx if pan_fx
        pat[x].rows[row] = note
      end

      tick += 1
      row += 1
      if row == song.rows
        row = 0
        break if not next_frame.call
      end
    end

    # noise writes all reset lfsr state, VGM files do not lie
    song.get_frame_pattern(0, 3).rows[0].fx[2] = [SNM::EF[:SN_CONTROL], 0xE1]

    snm.save args[:output_name]
  end
  module_function :main
end

USAGE = <<EOF
Usage: vgm2snm [<option>...] <vgmfile>
EOF
HELP = USAGE + <<EOF
Options:
  --help, -?
    Displays this message.
  --version
    Displays the script version.
  --output, -o <snmfile>
    Supplies a custom output module's file name.
  --rate, -r <hertz>
    Overrides the VGM and SNM refresh rate.
  --rows, -R <rows>
    Changes the number of rows per frame. (default 256)
  --samples, -s <rate>
    Changes the number of samples per second. This option actually scales the
    output's tempo. (default 44100)
  --skip, -k <count>
    Ignores the first <count> samples from the VGM.
EOF

args = {}

GetoptLong.new(
  ['--help'   , '-?', GetoptLong::NO_ARGUMENT],
  ['--version',       GetoptLong::NO_ARGUMENT],
  ['--output' , '-o', GetoptLong::REQUIRED_ARGUMENT],
  ['--rate'   , '-r', GetoptLong::REQUIRED_ARGUMENT],
  ['--rows'   , '-R', GetoptLong::REQUIRED_ARGUMENT],
  ['--samples', '-s', GetoptLong::REQUIRED_ARGUMENT],
  ['--skip'   , '-k', GetoptLong::REQUIRED_ARGUMENT],
).each do |opt, arg|
  case opt
  when '--help'
    puts HELP
    exit
  when '--version'
    puts "SNM2VGM 1.0\nHertzDevil\nMozilla Publix License Version 2.0"
    exit
  when '--output'
    args[:output_name] = arg
  when '--rate'
    args[:refresh_rate] = arg.to_f
  when '--rows'
    args[:rows] = arg.to_i
  when '--samples'
    args[:samples] = arg.to_f
  when '--skip'
    args[:skip] = arg.to_i
  end
end

fname = ARGV.shift
if !fname
  puts USAGE
  exit
end
args[:input_name] = fname
args[:output_name] = fname + ".snm" unless args[:output_name]

VGM2SNM.main args
