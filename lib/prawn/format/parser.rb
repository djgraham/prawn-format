require 'prawn/format/instructions/text'
require 'prawn/format/instructions/tag_open'
require 'prawn/format/instructions/tag_close'
require 'prawn/format/lexer'
require 'prawn/format/line'
require 'prawn/format/state'

module Prawn
  module Format

    # The Parser class is used by the formatting subsystem to take
    # the raw tokens from the Lexer class and wrap them in
    # "instructions", which are then used by the LayoutBuilder to
    # determine how each token should be rendered.
    #
    # The parser also ensures that tags are opened and closed
    # consistently. It is not forgiving at all--if you forget to
    # close a tag, the parser will raise an exception (TagError).
    # 
    # It will also raise an exception if a tag is encountered with
    # no style definition for it.
    class Parser
      # This is the exception that gets raised when the parser cannot
      # process a particular tag.
      class TagError < RuntimeError; end

      attr_reader :document
      attr_reader :styles
      attr_reader :state

      # Creates a new parser associated with the given +document+, and which
      # will parse the given +text+. The +options+ may include either of two
      # optional keys:
      #
      # * :styles is used to specify the hash of tags and their associated
      #   styles. Any tag not specified here will not be recognized by the
      #   parser, and will cause an error if it is encountered in +text+.
      # * :style is the default style for any text not otherwise wrapped by
      #   tags.
      #
      # Example:
      #
      #   parser = Parser.new(@pdf, "...",
      #       :styles => { :b => { :font_weight => :bold } },
      #       :style => { :font_family => "Times-Roman" })
      #
      # See Format::State for a description of the supported style options.
      def initialize(document, text, options={})
        @document = document
        @lexer = Lexer.new(text)
        @styles = options[:styles] || {}

        @state = State.new(document, :style => options[:style])

        @action = :start

        @saved = []
        @tag_stack = []
      end

      # Returns the next instruction from the stream. If there are no more
      # instructions in the stream (e.g., the end has been encountered), this
      # returns +nil+.
      def next
        return @saved.pop if @saved.any?

        case @action
        when :start then start_parse
        when :text  then text_parse
        else raise "BUG: unknown parser action: #{@action.inspect}"
        end
      end

      # "Ungets" the given +instruction+. This makes it so the next call to
      # +next+ will return +instruction+. This is useful for backtracking.
      def push(instruction)
        @saved.push(instruction)
      end

      # This is identical to +next+, except it does not consume the
      # instruction. This means that +peek+ returns the instruction that will
      # be returned by the next call to +next+. It is useful for testing
      # the next instruction in the stream without advancing the stream.
      def peek
        save = self.next
        push(save) if save
        return save
      end

      # Returns +true+ if the end of the stream has been reached. Subsequent
      # calls to +peek+ or +next+ will return +nil+.
      def eos?
        peek.nil?
      end

      private

        def start_parse
          instruction = nil
          while (@token = @lexer.next)
            case @token[:type]
            when :text
              @position = 0
              instruction = text_parse
            when :open
              @tag_stack << @token
              raise TagError, "undefined tag #{@token[:tag]}" unless @styles[@token[:tag]]
              @token[:style] = @styles[@token[:tag]].dup

              if @token[:style][:meta]
                @token[:style][:meta].each do |key, value|
                  @token[:style][value] = @token[:options][key]
                end
              end

              @state = @state.with_style(@token[:style])
              instruction = Instructions::TagOpen.new(@state, @token)
            when :close
              raise TagError, "closing #{@token[:tag]}, but no tags are open" if @tag_stack.empty?
              raise TagError, "closing #{@tag_stack.last[:tag]} with #{@token[:tag]}" if @tag_stack.last[:tag] != @token[:tag]

              instruction = Instructions::TagClose.new(@state, @tag_stack.pop)
              @state = @state.previous
            else
              raise ArgumentError, "[BUG] unknown token type #{@token[:type].inspect} (#{@token.inspect})"
            end

            return instruction if instruction
          end

          return nil
        end

        def text_parse
          if @token[:text][@position]
            @action = :text
            @position += 1
            Instructions::Text.new(@state, @token[:text][@position - 1])
          else
            @action = :start
            start_parse
          end
        end
    end

  end
end
