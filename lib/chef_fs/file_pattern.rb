require 'chef_fs'
require 'chef_fs/path_utils'

module ChefFS
  class FilePattern
    def initialize(pattern)
      @pattern = pattern
    end

    attr_reader :pattern

    def could_match_children?(path)
      path_parts = ChefFS::PathUtils::split(path)
      # If the pattern is shorter than the path (or same size), children will be larger than the pattern, and will not match.
      return false if regexp_parts.length <= path_parts.length && !has_double_star
      # If the path doesn't match up to this point, children won't match either.
      return false if path_parts.zip(regexp_parts).any? { |part,regexp| !regexp.nil? && !regexp.match(part) }
      # Otherwise, it's possible we could match: the path matches to this point, and the pattern is longer than the path.
      # TODO There is one edge case where the double star comes after some characters like abc**def--we could check whether the next
      # bit of path starts with abc in that case.
      return true
    end

    def exact_child_name_under(path)
      dirs_in_path = ChefFS::PathUtils::split(path).length
      return nil if exact_parts.length <= dirs_in_path
      return exact_parts[dirs_in_path]
    end

    def exact_path
      return nil if has_double_star || exact_parts.any? { |part| part.nil? }
      ChefFS::PathUtils::join(*exact_parts)
    end

    def match?(path)
      !!regexp.match(path)
    end

    def to_s
      pattern
    end

    def self.relative_to(dir, pattern)
      return FilePattern.new(pattern) if pattern =~ /^#{ChefFS::PathUtils::regexp_path_separator}/
      FilePattern.new(ChefFS::PathUtils::join(dir, pattern))
    end

  private

    def regexp
      calculate
      @regexp
    end

    def regexp_parts
      calculate
      @regexp_parts
    end

    def exact_parts
      calculate
      @exact_parts
    end

    def has_double_star
      calculate
      @has_double_star
    end

    def calculate
      if !@regexp
        full_regexp_parts = []
        @regexp_parts = []
        @exact_parts = []
        @has_double_star = false
        ChefFS::PathUtils::split(pattern).each do |part|
          regexp, exact, has_double_star = FilePattern::pattern_to_regexp(part)
          if has_double_star
            @has_double_star = true
          end
          if (exact == '' && full_regexp_parts.length > 0) || exact == '.'
            # Skip // and /./ (pretend it's not there)
          elsif exact == '..'
            # Back up when you see ..
            full_regexp_parts.pop
            if !@has_double_star
              @regexp_parts.pop
              @exact_parts.pop
            end
          else
            full_regexp_parts << regexp
            if !@has_double_star
              @regexp_parts << Regexp.new("^#{regexp}$")
              @exact_parts << exact
            end
          end
        end

        @regexp = Regexp.new("^#{full_regexp_parts.join(ChefFS::PathUtils::regexp_path_separator)}$")
      end
    end

    def self.regexp_special_characters
      if ChefFS::windows?
        @regexp_special_characters ||= /(\*\*|\*|\?|[\*\?\.\|\(\)\[\]\{\}\+\\\\\^\$])/
      else
        # Unix also supports character regexes and backslashes
        @regexp_special_characters ||= /(\\.|\[[^\]]+\]|\*\*|\*|\?|[\*\?\.\|\(\)\[\]\{\}\+\\\\\^\$])/
      end
      @regexp_special_characters
    end

    def self.pattern_to_regexp(pattern)
      regexp = ""
      exact = ""
      has_double_star = false
      pattern.split(regexp_special_characters).each_with_index do |part, index|
        # Odd indexes from the split are symbols.  Even are normal bits.
        if index % 2 == 0
          exact << part if !exact.nil?
          regexp << part
        else
          case part
          # **, * and ? happen on both platforms.
          when '**'
            exact = nil
            has_double_star = true
            regexp << '.*'
          when '*'
            exact = nil
            regexp << '[^\/]*'
          when '?'
            exact = nil
            regexp << '.'
          else
            if part[0] == '\\' && part.length == 2
              # backslash escapes are only supported on Unix, and are handled here by leaving the escape on (it means the same thing in a regex)
              exact << part[1] if !exact.nil?
              regexp << part
            elsif part[0] == '[' && part.length > 1
              # [...] happens only on Unix, and is handled here by *not* backslashing (it means the same thing in and out of regex)
              exact = nil
              regexp << part
            else
              exact += part if !exact.nil?
              regexp << "\\#{part}"
            end
          end
        end
      end
      [regexp, exact, has_double_star]
    end
  end
end