module Scorer
  class Story

    attr_accessor :project_id, :follower_ids, :updated_at, :current_state, :name, :comment_ids, :url, :story_type,
                  :label_ids, :description, :requested_by_id, :planned_iteration_number, :external_id, :deadline,
                  :owned_by_id, :owned_by, :created_at, :estimate, :kind, :id, :task_ids, :integration_id, :accepted_at,
                  :comments, :tasks, :attachments, :requested_by, :labels, :notes, :started_at, :status

    def initialize(attributes={})
      update_attributes(attributes)
    end

    def self.fields
      ['url', 'name', 'description', 'story_type',
       'estimate', 'current_state', 'requested_by',
       'owned_by', 'labels', 'integration_id',
       'deadline', 'comments', 'tasks', 'created_at', 'updated_at']
    end

    def self.parse_json_story(json_story, project_id)
      requested_by = json_story[:requested_by][:name] if !json_story[:requested_by].nil?
      story_id = json_story[:id].to_i
      estimate = json_story[:estimate] ? json_story[:estimate].to_i : -1
      current_state = json_story[:current_state]
      parsed_story = new({
        id: story_id,
        url: json_story[:url],
        project_id: project_id,
        created_at: DateTime.parse(json_story[:created_at].to_s).to_s,
        updated_at: DateTime.parse(json_story[:updated_at].to_s).to_s,
        name: json_story[:name],
        description: json_story[:description],
        story_type: json_story[:story_type],
        estimate: estimate,
        current_state: current_state,
        requested_by: requested_by,
        owned_by_id: json_story[:owned_by_id],
        owned_by: json_story[:owned_by],
        labels: parse_labels(json_story[:labels]),
        integration_id: json_story[:integration_id],
        deadline: json_story[:deadline]
      })

      parsed_story.comments = parse_notes(json_story[:comments], json_story)
      parsed_story.tasks = parse_tasks(json_story[:tasks], json_story)
      parsed_story.attachments = []
      parsed_story
    end

    def self.parse_json_stories(json_stories, project_id)
      json_stories.map do |story|
        parse_json_story(story, project_id)
      end
    end

    def self.parse_notes(notes, story)
      (notes || []).map do |note|
        Scorer::Comment.new({
          id: note[:id].to_i,
          text: note[:text],
          author: note[:author],
          created_at: DateTime.parse(note[:created_at].to_s).to_s,
          story: story
        })
      end
    end

    def self.parse_tasks(tasks, story)
      (tasks || []).map do |task|
        Scorer::Task.new({
          id: task[:id].to_i,
          description: task[:description],
          complete: task[:complete],
          created_at: DateTime.parse(task[:created_at].to_s).to_s,
          story: story
        })
      end
    end

    def self.parse_attachments(attachments)
      (attachments || []).map do |file|
        attachment = Scorer::Attachment.new
        attachment.id = file[:id].to_i
        attachment.filename = file[:filename]
        attachment.description = file[:description]
        attachment.uploaded_by = file[:uploaded_by]
        attachment.uploaded_at = file[:uploaded_at]
        attachment.url = file[:url]
        attachment.status = file[:status]
      end
    end

    def self.parse_labels(labels)
      labels.map do |label|
        label[:name]
      end.join(",")
    end

    def self.get_story_started_at(project_id, story_id)
      events = Hash.new
      current_started_at = nil
      current_accepted_at = nil
      activity = PivotalService.activity(project_id, story_id, 40)
      activity.each do |event|
        case event[:highlight]
          when 'started'
            started_at = event[:occurred_at]
            if current_started_at.nil? || current_started_at < started_at || current_accepted_at === started_at
              current_started_at = started_at
              events[:started_at] = current_started_at
            end
          when 'accepted'
            accepted_at = event[:occurred_at]
            if current_accepted_at.nil? || current_accepted_at < accepted_at
              current_accepted_at = accepted_at
              events[:accepted_at] = current_accepted_at
            end
        end
      end
      events
    end

    def self.get_story_status(event_times, points, current_state)
      status = {status: 'ok', hours: -1}
      if !event_times.nil? && !event_times[:started_at].nil? && points > -1 && current_state != 'unstarted'

        # Times
        started_at_time = Time.parse(event_times[:started_at])

        # Due Dates
        due_date = (points.to_i.business_hours.after(started_at_time)).to_datetime
        almost_due_date = ((points - 1).to_i.business_hours.after(started_at_time)).to_datetime

        if current_state == 'accepted' && !event_times[:accepted_at].nil?
          accepted_at = event_times[:accepted_at]
          hours = get_hours_between_times(started_at_time, Time.parse(accepted_at))
          if accepted_at.to_datetime > due_date || hours >= points
            status = {status: 'overdue', hours: hours}
          elsif accepted_at >= almost_due_date || hours == (points - 1)
            status = {status: 'almost_due', hours: hours}
          else
            status = {status: 'ok', hours: hours}
          end
        else
          now = DateTime.now
          hours = get_hours_between_times(started_at_time, Time.parse(now.to_s))
          if now >= due_date || hours >= points
            status = {status: 'overdue', hours: hours}
          elsif now >= almost_due_date || hours == (points - 1)
            status = {status: 'almost_due', hours: hours}
          else
            status = {status: 'ok', hours: hours}
          end
        end

      end
      status
    end

    protected

    def self.get_hours_between_times(time1, time2)

      # Check to see if both times occurred outside of business hours.
      # If so, calculate the total time in between each time
      if Time::roll_forward(time1) == Time::roll_forward(time2)
        return (((time2 - time1) / 60) / 60).round
      end

      ((time1.business_time_until(time2) / 60) / 60).round
    end

    def self.est_time_zone(time)
      time.in_time_zone("Eastern Time (US & Canada)")
    end

    def update_attributes(attrs)
      attrs.each do |key, value|
        self.send("#{key}=", value.is_a?(Array) ? value.join(',') : value )
      end
    end

  end
end