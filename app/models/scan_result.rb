module Intrigue
  module Model
    class ScanResult

      attr_accessor :id, :name, :tasks, :entities, :log

      def self.key
        "scan_result"
      end

      def key
        Intrigue::Model::ScanResult.key
      end

      def initialize(id,name)
        @id = id
        @name = name
        @timestamp_start = Time.now.getutc.to_s
        @timestamp_end = Time.now.getutc.to_s
        @entity = Entity.new("none",{})
        @lookup_key = "#{key}:#{@id}"
        @task_results = []
        @entities = []
        @log = ScanResultLog.new(id,name)
      end

      def self.find(id)
        s = ScanResult.new("nope","nope")
        s.from_json($intrigue_redis.get(@lookup_key))
        # if we didn't find anything in the db, return nil
        return nil if s.name == "nope"
      s
      end

      def add_task_result(task_result)
        @task_results << task_result
        save
      end

      def add_entity(entity)
        @entities << entity
        save
      end

      def from_json(json)
        begin
          x = JSON.parse(json)
          @id = x["id"]
          @lookup_key = "#{key}:#{@id}"

          @name = x["name"]
          @timestamp_start = x["timestamp_start"]
          @timestamp_end = x["timestamp_end"]

          @entity = Entity.find x["entity_id"]
          @tasks = x["task_result_ids"].map{|y| TaskResult.find y } if x["task_result_ids"]
          @entities = x["entity_ids"].map{|y| Entity.find y } if x["entity_ids"]
          @log = ScanResultLog.find x["log_id"]
          save
        rescue TypeError => e
          return nil
        rescue JSON::ParserError => e
          return nil
        end
      end

      def to_json
        {
          "id" => @id,
          "name" => @name,
          "timestamp_start" => @timestamp_start,
          "timestamp_end" => @timestamp_end,
          "entity_id" => @entity.id,
          "task_result_ids" => @task_results.map{|y| y.id },
          "entity_ids" => @entities.map {|y| y.id },
          "log_id" => @log.id
        }.to_json
      end

      def to_s
        to_json
      end

      def save
        $intrigue_redis.set @lookup_key, to_json
      end

    end
  end
end
