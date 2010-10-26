module DataForge
  # Converts the following DSL:
  #
  # class MyModel < ActiveRecord::Base
  #   structure do
  #     my_field DataForge::Paragraph
  #    end
  # end
  # into a schema on that model class by calling method_missing(my_field)
  # and deciding what the best schema type is for the user's requiredments
  class Schema
    attr_accessor :indexes

    def initialize  
      @columns = Hash.new
      @indexes = Array.new
    end      

    def define_structure(&block)      
      # Runs method_missing on columns given in the model "structure" DSL
      self.instance_eval(&block) if block_given?
    end
    
    def add_associations(associations)
      associations.each do |association|
        case association.macro
          when :belongs_to
            if association.options[:polymorphic]
              @columns[(association.name.to_s+'_type').to_sym] = DataType::Polymorphic.new 
              @indexes << [(association.name.to_s+'_type').to_sym, association.options[:foreign_key] || (association.name.to_s+'_id').to_sym]
            end
            @columns[association.options[:foreign_key] || (association.name.to_s+'_id').to_sym] = DataType::ForeignKey.new
            @indexes << (association.name.to_s+'_id').to_sym
        end
      end
    end
    
    def columns
      @columns.collect {|field, data| [field, data.column] } # All that needs to be migrated
    end
    
    # This is where we decide what the best schema is based on the structure requirements
    # The output of this is essentially a formatted schema hash that is processed 
    # on each model by DataForge::MigrationGenerator
    def method_missing(*args, &block)
      field = args.slice!(0)
      data_type = (args.first.nil?)? DataType::String : args.slice!(0)
      options = args.extract_options!

      # Add index if explicitly asked
      @indexes << field if options.delete(:index) || data_type.class.to_s == 'Hash' && data_type.delete(:index)

      # Matches: description DataType::Paragraph, :index => true
      if data_type.is_a?(Class) && data_type.respond_to?(:migration_data_example)
        @columns[field] = data_type.new(options)
      # Matches: description :index => true, :unique => true
      else
        begin
          # Eg. "My field" -> String -> DataType::String
          @columns[field] = "DataType::#{data_type.class.to_s}".constantize.new(options.merge(:value => data_type))
        rescue NameError
          # We don't have a matching type, throw a warning and default to string
          puts "MIGRATION WARNING: No migration implementation for class #{data_type.class.to_s} on field '#{field}', defaulting to string..."
          @columns[field] = DataType::Base.new(options)
        end
      end
      puts [":#{field}", "#{@columns[field].class}", "#{options.inspect}"].collect { |s| s.ljust(25) }.join if ENV['DEBUG']
    end
  end
  
  class InheritedSchema
    attr_accessor :columns, :indexes, :parent_schema
    
    def initialize(parent_schema)
      @parent_schema = parent_schema
      @columns = Array.new
      @indexes = Array.new
    end
  end
end
