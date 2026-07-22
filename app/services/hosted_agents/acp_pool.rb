require "set"
require "fileutils"

module HostedAgents
  class AcpPool
    Entry = Data.define(:client, :loaded_projects)

    class << self
      def prompt(hosted_agent, project, text, &on_chunk)
        with_agent_lock(hosted_agent.id) do
          entry = entry_for(hosted_agent)
          session_id = session_for(entry, hosted_agent, project)
          entry.client.prompt(session_id, text, &on_chunk)
          mark_connected(hosted_agent)
        end
      rescue => error
        mark_failed(hosted_agent, error)
        discard(hosted_agent.id)
        raise
      end

      def warm(hosted_agent)
        with_agent_lock(hosted_agent.id) do
          record = hosted_agent.sessions.includes(:project).first
          return clear_connection(hosted_agent) unless record

          entry = entry_for(hosted_agent)
          session_id = session_for(entry, hosted_agent, record.project)
          entry.client.ping(session_id)
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
        def entry_for(hosted_agent)
          mutex.synchronize do
            entry = entries[hosted_agent.id]
            return entry if entry&.client&.alive?

            entry&.client&.close
            entries[hosted_agent.id] = Entry.new(
              client: AcpClient.new(hosted_agent),
              loaded_projects: Set.new
            )
          end
        end

        def session_for(entry, hosted_agent, project)
          record = hosted_agent.sessions.find_by(project: project)
          if record
            return record.external_session_id if entry.loaded_projects.include?(project.id)

            begin
              entry.client.load_session(record.external_session_id)
              entry.loaded_projects.add(project.id)
              return record.external_session_id
            rescue AcpClient::Error
              record.destroy!
            end
          end

          session_id = entry.client.new_session
          hosted_agent.sessions.create!(project: project, external_session_id: session_id)
          entry.loaded_projects.add(project.id)
          session_id
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
