#! /usr/bin/ruby

# This Source Code Form is subject to the terms of the Mozilla Public License,
# v. 2.0. If a copy of the MPL was not distributed with this file, You can
# obtain one at http://mozilla.org/MPL/2.0/.

module VGM2SNM
  module SNM
    module Chunk
      class Base
        def initialize(name, version, parent)
          @name, @version, @parent = name.to_s, version, parent
        end

        def get_chunk
          data = get_data
          [@name, @version, data.length].pack("a16I<I<") + data
        end
      end

      class Info < Base
        def initialize(parent)
          super "INFO", 1, parent
        end
 
        def get_data
          [@parent.title, @parent.author, @parent.copyright].pack "a32a32a32"
        end
      end

      class Params < Base
        def initialize(parent)
          super "PARAMS", 6, parent
        end

        def get_data
          [
            0,  # expansion chip
            4,  # channel count
            0,  # region
            @parent.refresh_rate == 60 ? 0 : @parent.refresh_rate,
            1,  # vibrato style
            4,  # first highlight
            16, # second highlight
            32, # Fxx split point
          ].pack "CI<7"
        end
      end

      class Header < Base
        def initialize(parent)
          super "HEADER", 3, parent
        end

        def get_data
          songs = @parent.songs
          buf = (songs.length - 1).chr
          buf += songs.map {|x| x.title + "\x00"}.join
          buf += (0...@parent.track_count).map do |x|
            x.chr + (0...songs.length).map do |y|
              songs[y].tracks[x].fxcount - 1
            end.map(&:chr).join
          end.join
        end
      end

      class Instruments < Base
        def initialize(parent)
          super "INSTRUMENTS", 6, parent
        end

        def get_data
          [
            1, # instrument count
            0, # instrument index
            1, # instrument type
            5, # sequence count
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, # sequence enable / index
            5, # instrument name
          ].pack("I<I<CI<C10I<") + "Blank"
        end
      end

      class Sequences < Base
        def initialize(parent)
          super "SEQUENCES", 6, parent
        end

        def get_data
          "\x00" * 4
        end
      end

      class Frames < Base
        def initialize(parent)
          super "FRAMES", 3, parent
        end

        def get_data
          @parent.songs.map(&:get_frame_data).join
        end
      end

      class Patterns < Base
        def initialize(parent)
          super "PATTERNS", 4, parent
        end

        def get_data
          @parent.songs.map.with_index do |song, index|
            song.tracks.map.with_index do |track, i|
              track.patterns.each(&:clean)
              track.patterns.map.with_index do |pat, j|
                pat.empty? ? "" : [index, i, j].pack("I<3") + pat.get_data
              end.join
            end.join
          end.join
        end
      end

      class Comments < Base
        def initialize(parent)
          super "COMMENTS", 1, parent
        end

        def get_data
          [@parent.comment_show ? 1 : 0, @parent.comment].pack("I<a")
        end
      end

    end
  end
end
