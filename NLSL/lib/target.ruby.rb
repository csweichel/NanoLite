module NLSE
  module Target
    module Ruby

      #
      # The runtime module for the Ruby target. This module contains all classes, functions and constants
      # required for transformer generated code to run.
      #
      module Runtime
        include Math

        class Vec2
          attr_accessor :x, :y

          def self.zero
            Vec2.new(0.0, 0.0)
          end

          def initialize(x, y)
            @x = x
            @y = y
          end

          def *(other)
            if other.is_a?(Vec2)
              sqrt((x * other.x) + (y * other.y))
            else
              Vec2.new(x * other, y * other)
            end
          end

          def /(other)
            Vec2.new(x / other, y / other)
          end

          def +(other)
            if other.is_a? Vec2
              Vec2.new(x + other.x, y + other.y)
            end
          end

          def to_a
            [ x, y ]
          end
        end
        class Vec3
          attr_accessor :x, :y, :z

          def self.zero
            Vec3.new(0.0, 0.0, 0.0)
          end

          def initialize(x, y, z = nil)
            if z.nil?
              @x = x.x
              @y = x.y
              @z = y
            else
              @x = x
              @y = y
              @z = z
            end
          end

          def xy
            Vec2.new(@x, @y)
          end

          def *(other)
            if other.is_a?(Vec3)
              sqrt((x * other.x) + (y * other.y) + (z * other.z))
            else
              Vec3.new(x * other, y * other, z * other)
            end
          end

          def /(other)
            Vec3.new(x / other, y / other, z / other)
          end

          def +(other)
            if other.is_a? Vec3
              Vec3.new(x + other.x, y + other.y, z + other.z)
            end
          end

          def to_a
            [ x, y, z ]
          end

        end
        class Vec4
          attr_accessor :x, :y, :z, :w

          def self.zero
            Vec4.new(0.0, 0.0, 0.0, 0.0)
          end

          def initialize(x, y, z = nil, w = nil)
            if z.nil?
              @x = x.x
              @y = x.y
              @z = x.z
              @w = y
            elsif w.nil?
              @x = x.x
              @y = x.y
              @z = y
              @w = z
            else
              @x = x
              @y = y
              @z = z
              @w = w
            end
          end

          def xy
            Vec2.new(@x, @y)
          end
          def xyz
            Vec3.new(@x, @y, @z)
          end

          def *(other)
            if other.is_a?(Vec4)
              sqrt((x * other.x) + (y * other.y) + (z * other.z) + (w * other.w))
            else
              Vec4.new(x * other, y * other, z * other, w * other)
            end
          end

          def +(other)
            if other.is_a? Vec4
              Vec4.new(x + other.x, y + other.y, z + other.z, w + other.w)
            end
          end

          def /(other)
            Vec4.new(x / other, y / other, z / other, w / other)
          end

          def to_a
            [ x, y, z, w ]
          end

        end

        #
        # A matrix class representing values in column wise order. So a matrix
        #   1 0 0
        #   0 0 2
        #   0 3 0
        # is stored as 1 0 0, 0 0 3, 0 2 0 and NOT 1 0 0, 0 0 2, 0 3 0
        #
        class Mat
          attr_reader :m

          def initialize(size, values)
            throw "Not enough values" unless values.length >= size**2

            @size = size
            @m = values
          end

          def [](idx)
            args = @m[(idx * @size)...((idx + 1) * @size)]
            vector_type.send(:new, *args)
          end

          def *(other)
            if other.is_a? vector_type
              trans = transpose
              values = (0...@size).map {|e| self[e] * other }
              vector_type.send(:new, *values)
            elsif other.is_a? Numeric
              @m = @m.map {|e| e * other }
            else
              throw "Cannot multiply a matrix with #{other}"
            end
          end

          def vector_type
            case @size
              when 2 then Vec2
              when 3 then Vec3
              when 4 then Vec4
            end
          end

          def transpose
            newvalues = (0...@size).map {|row| (0...@size).map {|col| @m[(col * @size) + row] } }.flatten
            Mat.new(@size, newvalues)
          end

          def to_s
            (0...@size).map {|row| (0...@size).map {|col| @m[(col * @size) + row] }.join(" ") }.join("\n")
          end

        end


        def vec2(x, y); Vec2.new(x, y); end
        def vec3(x, y, z = nil); Vec3.new(x, y, z); end
        def vec4(x, y, z = nil, w = nil); Vec4.new(x, y, z, w); end
        def mat2(*args); Mat.new(2, args); end
        def mat3(*args); Mat.new(3, args); end
        def mat4(*args); Mat.new(4, args); end
      end

      #
      # Base class for ruby environment shaders
      #
      class Shader

        def initialize(nlse)
          @nlse = nlse
          @compiled = Transformer.new.transform(nlse)
        end

        def bind_uniform(name, value)
          raise "Unknown uniform: #{name}" if @nlse.uniforms[name].nil?
          instance_variable_set("@#{name}", value)
          self.class.__send__(:attr_accessor, name)
          self
        end

      end

      #
      # Serves as interface between geometry shader code and the rest of the world
      #
      class GeometryShader < Shader
        include Runtime

        attr_reader :iGlobalTime, :iResolution, :iFragID, :iFragCount
        attr_writer :nl_FragCoord

        def initialize(nlse)
          super
        end

        def execute(time, resolution, fragCount, fragID)
          @iGlobalTime = time
          @iResolution = resolution
          @iFragCount = fragCount
          @iFragID = fragID

          instance_eval @compiled
          throw "Shader did not set fragment coordinates" if @nl_FragCoord.nil?

          @nl_FragCoord
        end

      end
      
      #
      # Serves as interface between color shader code and the rest of the world
      #
      class ColorShader < Shader
        include Runtime

        attr_reader :iGlobalTime, :iResolution, :iFragCoord
        attr_writer :nl_FragColor

        def initialize(nlse)
          super
        end

        def execute(time, resolution, fragCoord)
          @iGlobalTime = time
          @iResolution = resolution
          @iFragCoord = fragCoord

          instance_eval @compiled
          throw "Shader did not set fragment color" if @nl_FragColor.nil?

          @nl_FragColor
        end
        
      end

      #
      # Generates Ruby code out of NLSE code
      #
      class Transformer

        def transform(element, sep = nil)
          (element.is_a?(Array) ? element : [ element ]).map do |root|
            name = root.class.name.split("::").last
            rule = "transform_#{name.downcase}"
            if respond_to? rule
              send(rule.to_sym, root)
            else
              puts "WARNING: No rule for #{name} (looking for #{rule}(root)"
            end
          end.join sep
        end

        def transform_program(root)
          """
          #{transform root.functions.values.flatten.reject {|e| e.builtin? }}
          main
          """
        end

        def transform_function(root)
          """
          def #{root.name}(#{root.arguments.values.join(", ")})
            #{transform root.body, "\n            "}
          end
          """
        end

        def transform_return(root)
          "#{transform root.value}\n"
        end

        def transform_value(root)
          root.value.to_s
        end

        def transform_variableassignment(root)
          output_variables = [ :nl_FragCoord, :nl_FragColor ]
          prefix = (output_variables.include?(root.name.to_s.to_sym)) ? "@" : ""

          "#{prefix}#{root.name} = #{transform root.value}"
        end

        def transform_componentaccess(root)
          "#{transform root.value}.#{root.component}"
        end

        def transform_matrixcolumnaccess(root)
          "#{transform root.value}[#{root.index}]"
        end

        def transform_functioncall(root)
          "#{root.name}(#{transform root.arguments, ", "})"
        end

        def transform_if(root)
          elze = root.else_body.nil? ? "" : "else\n#{transform root.else_body, "\n"}"

          "if (#{transform root.condition})\n#{transform root.then_body, "\n"}#{elze}\nend"
        end

        def transform_for(root)
          init = transform root.init
          cond = transform root.condition
          iter = transform root.iterator
          body = transform root.body, "\n"

          [
              "if true",
              init,
              "while (#{cond})",
              body,
              iter,
              "end",
              "end"
          ].join("\n")
        end

        def transform_while(root)
          cond = transform root.condition
          body = transform root.body

          "while (#{cond})\n#{body}\nend"
        end

        def transform_scalardivscalar(root)
          "(#{transform root.a} / #{transform root.b})"
        end

        def transform_scalarmulscalar(root)
          "(#{transform root.a} * #{transform root.b})"
        end

        def transform_scalaraddscalar(root)
          "(#{transform root.a} + #{transform root.b})"
        end

        def transform_scalarsubscalar(root)
          "(#{transform root.a} - #{transform root.b})"
        end

        def transform_compeqscalar(root)
          "(#{transform root.a} == #{transform root.b})"
        end

        def transform_compeqvector(root)
          "(#{transform root.a} == #{transform root.b})"
        end

        def transform_complessscalar(root)
          "(#{transform root.a} < #{transform root.b})"
        end

        def transform_complessvector(root)
          "(#{transform root.a} < #{transform root.b})"
        end

        def transform_compgreaterscalar(root)
          "(#{transform root.a} > #{transform root.b})"
        end

        def transform_compgreatervector(root)
          "(#{transform root.a} > #{transform root.b})"
        end

        def transform_vectoraddvector(root)
          "(#{transform root.a} + #{transform root.b})"
        end

        def transform_vectormulscalar(root)
          "(#{transform root.a} * #{transform root.b})"
        end

        def transform_vectorsubvector(root)
          "(#{transform root.a} - #{transform root.b})"
        end

        def transform_vectordivscalar(root)
          "(#{transform root.a} / #{transform root.b})"
        end

        def transform_vectormulvector(root)
          "(#{transform root.a} * #{transform root.b})"
        end

      end

      end
    end
end
