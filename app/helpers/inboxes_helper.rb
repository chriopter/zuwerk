module InboxesHelper
  def inbox_item_title(item)
    case item.trackable
    when Chat then "#{item.project.name} chat"
    when Task then item.trackable.title
    when Briefing then item.trackable.title
    end
  end

  def inbox_item_kind(item)
    case item.trackable
    when Chat then "Chat"
    when Task then "Task"
    when Briefing then "Briefing"
    end
  end

  def inbox_item_excerpt(item)
    truncate(item.latest_activity.summary, length: 180)
  end

  def inbox_item_destination(item)
    case item.trackable
    when Chat
      project_chat_path(item.project, anchor: inbox_activity_anchor(item.latest_activity))
    when Task
      project_task_path(item.project, item.trackable, anchor: inbox_activity_anchor(item.latest_activity))
    when Briefing
      project_briefing_path(item.project, item.trackable, anchor: inbox_activity_anchor(item.latest_activity))
    end
  end

  def inbox_activity_anchor(activity)
    "#{activity.subject_type.underscore}_#{activity.subject_id}"
  end
end
