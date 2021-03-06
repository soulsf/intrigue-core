module Intrigue
module Handler
  class ElasticsearchBulk < Intrigue::Handler::Base

    def self.metadata
      {
        :name => "elasticsearch_bulk",
        :pretty_name => "Export to ElasticSearch (BULK)",
        :type => "export"
      }
    end


    def perform(result_type, result_id, prefix_name=nil)
      result = eval(result_type).first(id: result_id)
      return "Unable to process" unless result.respond_to? "export_json"

      # Write it out
      File.open("#{prefix_name}#{result.name}.bulk", "a") do |file|
        _lock(file) do
          file.write("{ \"index\" : { \"_index\" : \"results\", \"_type\" : \"#{result.task_name}\", \"_id\" : \"#{result.id}\" } }\n")
          file.write(result.export_json)
          file.write "\n"
        end
      end
    end
  end
end
end
