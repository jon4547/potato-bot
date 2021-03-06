require "json"
require "httpclient"

module Potato
  module Bot
    class Client
      URL_TEMPLATE = "https://api.potato.im:8443/%<token>s/".freeze

      autoload :TypedResponse, "potato/bot/client/typed_response"
      extend Initializers
      prepend Async
      prepend Botan::ClientHelpers
      include DebugClient

      require "potato/bot/client/api_helper"
      include ApiHelper

      class << self
        def by_id(id)
          Potato.bots[id]
        end

        # Prepend TypedResponse module.
        def typed_response!
          prepend TypedResponse
        end

        # Encodes nested hashes as json.
        def prepare_body(body)
          body = body.dup
          body.each do |k, val|
            body[k] = val.to_json if val.is_a?(Hash) || val.is_a?(Array)
          end
        end

        def prepare_async_args(action, body = {})
          [action.to_s, Async.prepare_hash(prepare_body(body))]
        end

        def error_for_response(response)
          result = JSON.parse(response.body) rescue nil # rubocop:disable RescueModifier
          return Error.new(response.reason) unless result
          message = result["description"] || "-"
          # This errors are raised only for valid responses from Potato
          case response.status
          when 403 then Forbidden.new(message)
          when 404 then NotFound.new(message)
          else Error.new("#{response.reason}: #{message}")
          end
        end
      end

      attr_reader :client, :token, :username, :base_uri

      def initialize(token = nil, username = nil, **options)
        @client = HTTPClient.new
        @token = token || options[:token]
        @username = username || options[:username]
        @base_uri = format(URL_TEMPLATE, token: self.token)
      end

      def request(action, body = {})
        # if action == 'sendTextMessage' && body.has_key?(:chat_id)
        #   Rails.logger.info("------------request")
        #   Rails.logger.info action
        #   Rails.logger.info "#{base_uri}#{action}"
        #   Rails.logger.info body.inspect
        # end
        header = { 'Content-Type': "application/json; charset=utf-8" }
        send_body = if %W(answerCallbackQuery sendTextMessage getFile).include?(action)
                      response = http_request(
                        "#{base_uri}#{action}",
                        body.to_json,
                        header
                      )
                    else
                      response = http_request(
                        "#{base_uri}#{action}",
                        self.class.prepare_body(body)
                      )
                    end
        raise self.class.error_for_response(response) if response.status >= 300
        JSON.parse(response.body)
      end

      # Endpoint for low-level request. For easy host highjacking & instrumentation.
      # Params are not used directly but kept for instrumentation purpose.
      # You probably don't want to use this method directly.
      def http_request(uri, body, header = nil)
        if header.nil?
          client.post(uri, body)
        else
          client.post(uri, body, header)
        end
      end

      def inspect
        "#<#{self.class.name}##{object_id}(#{@username})>"
      end
    end
  end
end
