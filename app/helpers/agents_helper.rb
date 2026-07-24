module AgentsHelper
  def agent_session_kind(session)
    {
      "Chat" => "Chat",
      "Task" => "Task",
      "Briefing" => "Briefing"
    }.fetch(session.context_type)
  end

  def agent_session_label(session)
    case session.context
    when Chat
      "Shared project chat"
    when Task, Briefing
      session.context.title
    end
  end

  def agent_session_path(session)
    case session.context
    when Chat
      project_chat_path(session.project)
    when Task
      project_task_path(session.project, session.context)
    when Briefing
      project_briefing_path(session.project, session.context)
    end
  end
end
