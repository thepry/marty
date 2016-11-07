class Marty::Event < Marty::Base

  class EventValidator < ActiveModel::Validator
    def validate(event)
      event.errors[:base] = "Must have promise_id or start_dt" unless
        event.promise_id || event.start_dt
    end
  end

  validates_presence_of :klass, :subject_id, :enum_event_operation

  belongs_to :promise

  validates_with EventValidator

  after_validation(on: [:create, :update]) do
    self.comment = self.comment.truncate(255) if self.comment
  end

  BASE_QUERY = "SELECT ev.id,
                   ev.klass,
                   ev.subject_id,
                   ev.enum_event_operation,
                   ev.comment,
                   coalesce(pr.start_dt, ev.start_dt) start_dt,
                   coalesce(pr.end_dt, ev.end_dt) end_dt,
                   expire_secs
                FROM marty_events ev
                LEFT JOIN marty_promises pr ON ev.promise_id = pr.id "

  def self.running_query(time_now_s)
    "SELECT * FROM
       (#{BASE_QUERY}
        WHERE coalesce(pr.start_dt, ev.start_dt, '1900-1-1') >=
                   '#{time_now_s}'::timestamp - interval '24 hours') sub
     WHERE (end_dt IS NULL or end_dt > '#{time_now_s}'::timestamp)
       AND (expire_secs IS NULL
        OR expire_secs > EXTRACT (EPOCH FROM '#{time_now_s}'::timestamp - start_dt))
      ORDER BY start_dt"
  end


  def self.op_is_running?(klass, subject_id, operation)
    all_running.detect do |pm|
      pm["klass"] == klass && pm["subject_id"].to_i == subject_id.to_i &&
        pm["enum_event_operation"] == operation
    end
  end

  def self.create_event(klass,
                        subject_id,
                        operation,
                        start_dt,
                        expire_secs,
                        comment=nil)

    # use lookup_event instead of all_running which is throttled
    evs = self.lookup_event(klass, subject_id, operation)
    running = evs.detect do
      |ev|
      next if ev["end_dt"]
      next true unless ev["expire_secs"]
      (Time.zone.now - ev["start_dt"]).truncate < ev["expire_secs"]
    end

    raise "#{operation} is already running for #{klass}/#{subject_id}" if
      running

    self.create!(klass:                klass,
                 subject_id:           subject_id,
                 enum_event_operation: operation,
                 start_dt:             start_dt,
                 expire_secs:          expire_secs,
                 comment:              comment,
                )
  end

  def self.lookup_event(klass, subject_id, operation)
    get_data(BASE_QUERY +
             " WHERE klass = '#{klass}'
                AND subject_id = #{subject_id}
                and enum_event_operation = '#{operation}'")

    #For now we return a bare hash
    #Marty::Event.find_by_id(hash["id"])
  end

  def self.finish_event(klass, subject_id, operation, comment=nil)
    time_now_s = Time.zone.now.strftime('%Y-%m-%d %H:%M:%S.%6N')

    event = get_data(running_query(time_now_s)).detect do |ev|
      ev["klass"] == klass && ev["subject_id"] == subject_id.to_i &&
        ev["enum_event_operation"] == operation
    end
    raise "event #{klass}/#{subject_id}/#{operation} not found" unless
      event

    ev = Marty::Event.find_by_id(event["id"])
    raise "can't explicitly finish a promise event" if ev.promise_id
    ev.end_dt = Time.zone.now
    ev.comment = comment if comment
    ev.save!
  end

  def self.last_event(klass, subject_id, operation=nil)
    hash = all_running.select do |pm|
      pm["klass"] == klass && pm["subject_id"] == subject_id.to_i &&
        (operation.nil? || pm["enum_event_operation"] == operation)
    end.sort { |a, b| b["start_dt"] <=> a["start_dt"] }.first

    return hash if hash

    op_sql = "AND enum_event_operation = '#{operation}'" if operation

    get_data("SELECT * FROM (#{BASE_QUERY}) sub
              WHERE klass = '#{klass}'
                AND subject_id = #{subject_id} #{op_sql}
             ORDER BY start_dt desc").first
  end

  def self.currently_running(klass, subject_id)
    all_running.select do |pm|
      pm["klass"] == klass && pm["subject_id"] == subject_id.to_i
    end.map { |e| e["enum_event_operation"] }
  end

  def self.update_comment(hash, comment)
    hid = hash.is_a?(Hash) ? hash['id'] : hash
    e = Marty::Event.find_by_id(hid)
    e.comment = comment
    e.save!
  end

  def self.pretty_op(hash)
    d = hash['enum_event_operation'].downcase.capitalize

    #&& !(hash['comment'] =~ /^ERROR/)
    hash['end_dt'] ? d.sub(/ing/, 'ed') : d
  end

  def self.compact_end_dt(hash)
    hash['end_dt'] ? hash['end_dt'].strftime("%H:%M") : '---'
  end

  def self.get_data(sql)
    ActiveRecord::Base.connection.execute(sql).to_a.map do |h|
      h["id"]          = h["id"].to_i
      h["subject_id"]  = h["subject_id"].to_i
      h["start_dt"]    = Time.zone.parse(h["start_dt"]) if h["start_dt"]
      h["end_dt"]      = Time.zone.parse(h["end_dt"]) if h["end_dt"]
      h["expire_secs"] = h["expire_secs"].to_i if h["expire_secs"]
      h["comment"]     = h["comment"]
      h
    end
  end
  private_class_method :get_data

  def self.clear_cache
    @poll_secs = @all_running = @all_finished = nil
  end

  def self.all_running
    @all_running ||= { timestamp: 0, data: [] }
    @poll_secs ||= Marty::Config['MARTY_EVENT_POLL_SECS'] || 0
    time_now = Time.zone.now
    time_now_i = time_now.to_i
    time_now_s = time_now.strftime('%Y-%m-%d %H:%M:%S.%6N')
    if time_now_i - @all_running[:timestamp] > @poll_secs
      @all_running[:data] = get_data(running_query(time_now_s))
      @all_running[:timestamp] = time_now_i
    end
    @all_running[:data]
  end
  private_class_method :all_running

  def self.all_finished
    @all_finished ||= {
      data:      {},
      timestamp: Time.zone.parse('1970-1-1 00:00:00').to_i,
    }
    @poll_secs ||= Marty::Config['MARTY_EVENT_POLL_SECS'] || 0
    time_now_i = Time.zone.now.to_i
    cutoff = Time.zone.at(@all_finished[:timestamp]).
             strftime('%Y-%m-%d %H:%M:%S.%6N')

    if time_now_i - @all_finished[:timestamp] > @poll_secs
      raw = get_data(
        "SELECT * FROM
            (SELECT ROW_NUMBER() OVER (PARTITION BY klass,
                                                    subject_id,
                                                    enum_event_operation
                                       ORDER BY end_dt DESC) rownum, *
             FROM (#{BASE_QUERY}) sub2
             WHERE end_dt IS NOT NULL and end_dt > '#{cutoff}') sub1
         WHERE rownum = 1"
      )
      @all_finished[:timestamp] = time_now_i
      raw.each_with_object(@all_finished[:data]) do |ev, hash|
        subhash = hash[[ev["klass"], ev["subject_id"]]] ||= {}
        subhash[ev["enum_event_operation"]] =
          ev["end_dt"].strftime("%Y-%m-%d %H:%M:%S")
      end
    end
    @all_finished[:data]
  end

  def self.get_finished(klass, id)
    all_finished[[klass, id]]
  end
end
