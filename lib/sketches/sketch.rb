#
# Sketches - A Ruby library for live programming and code reloading.
#
# Copyright (c) 2009 Hal Brodigan (postmodern.mod3 at gmail.com)
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
#

require 'sketches/exceptions/editor_not_defined'
require 'sketches/config'
require 'sketches/temp_sketch'

require 'thread'
require 'fileutils'

module Sketches
  class Sketch

    # ID of the sketch
    attr_reader :id

    # Optional name of the sketch
    attr_accessor :name

    # Last modification time of the sketch
    attr_reader :mtime
 
    # command runner
    RUNNER = Kernel.method(:system)

    #
    # Creates a new {Sketch}.
    #
    # @param [Integer] id
    #   The ID of the sketch.
    #
    # @param [Hash] options
    #   Additional options.
    #
    # @option options [Symbol] :name
    #   The optional name of the sketch.
    #
    # @option options [String] :path
    #   The path to the existing sketch.
    #
    def initialize(id,options={})
      @id = id
      @name = options[:name]

      @mtime = Time.now
      @checksum = 0
      @mutex = Mutex.new

      if options[:path]
        @path = options[:path]
        @name ||= File.basename(@path)
      else
        TempSketch.open { |file| @path = file.path }
      end

      reload!
    end

    #
    # Provides thread-safe access to the sketch.
    #
    # @yield []
    #   The given block will be called, when no other threads are accessing
    #   the sketch.
    #
    # @return [nil]
    #
    def synchronize(&block)
      @mutex.synchronize(&block)
      return nil
    end

    #
    # Spawns the {Config.editor} with the path of the sketch.
    #
    def edit
      if Config.editor.nil?
        raise(EditorNotDefined,"no editor has defined via ENV['EDITOR'] or Sketches.config",caller)
      elsif Config.editor.kind_of?(Proc)
        cmd = Config.editor.call(@path)
      else
        cmd = "#{Config.editor} #{@path}"
      end

      if Config.terminal
        if Config.terminal.kind_of?(Proc)
          cmd = Config.terminal.call(cmd)
        else
          cmd = "#{Config.terminal} #{cmd}"
        end
      end

      if Config.background
        Thread.new(cmd,&RUNNER)
      else
        RUNNER.call(cmd)
        self.reload! if Config.eval_after_editor_quit
      end
    end

    #
    # Determines whether the sketch has become stale.
    #
    # @return [Boolean]
    #   Specifies whether the file that contains the sketch has recently
    #   changed.
    #
    def stale?
      if File.file?(@path)
        if File.mtime(@path) > @mtime
          return crc32 != @checksum
        end
      end

      return false
    end

    #
    # Reloads the sketch.
    #
    # @return [Boolean]
    #   Specifies whether the reload was successful.
    #
    def reload!
      if File.file?(@path)
        @mtime = File.mtime(@path)
        @checksum = crc32

        begin
          return load(@path)
        rescue LoadError => e
          STDERR.puts "#{e.class}: #{e.message}"
        end
      end

      return false
    end

    #
    # Saves the sketch.
    #
    # @param [String] path
    #   The file to save the sketch to.
    #
    # @return [Boolean]
    #   Specifies whether the sketch was successfully saved.
    #
    def save(path)
      if (File.file?(@path) && @path != path)
        FileUtils.cp(@path,path)
        return true
      end

      return false
    end

    #
    # Converts the sketch to a human-readable String.
    #
    # @return [String]
    #   The String representation of the sketch.
    #
    def to_s(verbose=false)
      str = "##{@id}"
      str << ": #{@name}" if @name
      str << "\n\n"

      if @path && File.file?(@path)
        File.open(@path, "r") do |file|
          unless verbose
            4.times do
              if file.eof?
                str << "\n" unless str[-1..-1] == "\n"
                str << "  ..."
                break
              end

              str << "  #{file.readline}"
            end
          else
            file.each_line { |line| str << "  #{line}" }
          end

          str << "\n"
        end
      end

      return str
    end

    protected

    #
    # Calculates the CRC32 checksum of the sketch file.
    #
    # @return [Integer]
    #   The CRC32 checksum of the sketch file.
    #
    def crc32
      r = 0xffffffff

      File.open(@path) do |file|
        file.each_byte do |b|
          r ^= b
          8.times { r = ((r >> 1) ^ (0xEDB88320 * (r & 1))) }
        end
      end

      return r ^ 0xffffffff
    end

  end
end
