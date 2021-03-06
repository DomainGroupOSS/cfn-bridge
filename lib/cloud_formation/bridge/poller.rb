require 'cloud_formation/bridge/executor'
require 'cloud_formation/bridge/exception_notifier'
require 'cloud_formation/bridge/request'
require 'cloud_formation/bridge/util'

module CloudFormation
  module Bridge
    class Poller

      attr_reader :logger, :running

      def initialize(queue_name, executor = CloudFormation::Bridge::Executor.new, logger = Util::LOGGER)
        @queue_name = queue_name
        @executor = executor
        @logger = logger
      end

      def start
        @running = true
        while @running
          poll
        end
      end

      def stop
        @running = false
      end

      def poll
        message = queue.receive_message({
          :visibility_timeout => 1800
        })

        unless message
          logger.info("No messages found, looping again")
          return
        end

        begin
          logger.info("Received message #{message.id} - #{message.body}")
          body = JSON.parse(message.body)
          request = CloudFormation::Bridge::Request.new(JSON.parse(body["Message"]), logger)
          @executor.execute(request)
          message.delete
          logger.info("Processed message #{message.id}")
          message
        rescue Exception => ex
          logger.info("Failed to process message #{message.id} - #{ex.message}")
          ExceptionNotifier.report_exception(ex,
            message: message.body,
            handle: message.handle,
            id: message.id,
            queue: @queue_name,
          )
        end
      end

      def visible_messages
        queue.visible_messages
      end

      def queue
        @queue ||= sqs.queues.named(@queue_name)
      end

      def sqs
        @sqs ||= AWS::SQS.new
      end

    end
  end
end
