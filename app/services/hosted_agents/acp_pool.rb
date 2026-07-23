require "set"
require "fileutils"

module HostedAgents
  class AcpPool
    Entry = Data.define(:client, :loaded_origins)

    class << self
      def prompt(hosted_agent, origin, text, event: nil, &on_chunk)
        with_agent_lock(hosted_agent.id) do
          entry = entry_for(hosted_agent)
          record = session_for(entry, hosted_agent, origin)
          session_id = record.external_session_id
          entry.client.prompt(session_id, text, on_permission: permission_handler(event, entry.client), &on_chunk)
          record.touch(:last_used_at)
          mark_connected(hosted_agent)
        end
      rescue => error
        mark_failed(hosted_agent, error)
        discard(hosted_agent.id)
        raise
      end

      def warm(hosted_agent)
        with_agent_lock(hosted_agent.id) do
          records = hosted_agent.sessions.includes(:origin).order(last_used_at: :desc).to_a
          records.select { |candidate| candidate.origin.nil? }.each(&:destroy!)
          record = records.find { |candidate| candidate.origin.present? }
          return clear_connection(hosted_agent) unless record

          entry = entry_for(hosted_agent)
          record = session_for(entry, hosted_agent, record.origin)
          entry.client.ping(record.external_session_id)
          mark_connected(hosted_agent)
        end
      rescue => error
        mark_failed(hosted_agent, error)
        discard(hosted_agent.id)
        raise
      end

      def discard(hosted_agent_id)
        mutex.synchronize do
          entries.delete(hosted_agent_id)&.client&.close
        end
      end

      def reconcile(active_ids)
        (mutex.synchronize { entries.keys } - active_ids).each { |id| discard(id) }
      end

      private
        # Without an event there is nothing to hang an approval on, so warmups
        # and pings keep declining permissions instead of blocking on a human.
        def permission_handler(event, client)
          return nil unless event

          ->(request_id, params) { AgentApprovals::Gate.await(event, request_id, params, client: client) }
        end

        def entry_for(hosted_agent)
          mutex.synchronize do
            entry = entries[hosted_agent.id]
            return entry if entry&.client&.alive?

            entry&.client&.close
            entries[hosted_agent.id] = Entry.new(
              client: AcpClient.new(hosted_agent),
              loaded_origins: Set.new
            )
          end
        end

        def session_for(entry, hosted_agent, origin)
          key = [ origin.class.polymorphic_name, origin.id ]
          record = hosted_agent.sessions.find_by(origin: origin)
          if record
            return record if entry.loaded_origins.include?(key)

            begin
              entry.client.load_session(record.external_session_id)
              entry.loaded_origins.add(key)
              return record
            rescue AcpClient::Error
              record.destroy!
            end
          end

          session_id = entry.client.new_session
          record = hosted_agent.sessions.create!(origin: origin, external_session_id: session_id)
          entry.loaded_origins.add(key)
          record
        end

        def mark_connected(hosted_agent)
          hosted_agent.update_columns(bridge_connected_at: Time.current, bridge_last_error: nil, updated_at: Time.current)
        end

        def mark_failed(hosted_agent, error)
          hosted_agent.update_columns(
            bridge_connected_at: nil,
            bridge_last_error: error.message.to_s.truncate(500),
            updated_at: Time.current
          )
        end

        def clear_connection(hosted_agent)
          hosted_agent.update_columns(bridge_connected_at: nil, bridge_last_error: nil, updated_at: Time.current)
        end

        def with_agent_lock(hosted_agent_id)
          FileUtils.mkdir_p(lock_directory, mode: 0o700)
          path = File.join(lock_directory, "agent-#{Integer(hosted_agent_id)}.lock")
          File.open(path, File::RDWR | File::CREAT, 0o600) do |file|
            file.flock(File::LOCK_EX)
            yield
          ensure
            file.flock(File::LOCK_UN) rescue nil
          end
        end

        def lock_directory
          Rails.root.join("tmp", "acp-locks")
        end

        def entries
          @entries ||= {}
        end

        def mutex
          @mutex ||= Mutex.new
        end
    end
  end
end
