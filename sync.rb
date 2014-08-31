require 'rubygems'
require 'time'
require 'pp'
require 'mechanize'
require 'google_calendar'
require 'pit'

APPNAME = 'gaba-googlecalendar-sync'
TITLE = 'Gaba Lesson'

class Gaba
  LOGIN_URL = "https://my.gaba.jp/auth/login"
  AUTH_ACTION = '/auth/login'
  SCHEDULE_URL = "https://my.gaba.jp/schedule"

  def initialize(user, pass)
    @user = user
    @pass = pass
  end

  def agent
    @agent ||= Mechanize.new
  end

  def is_logged_in?
    @logged_in_user != nil
  end

  def login
    return if is_logged_in?
    agent.get(LOGIN_URL) do |page|
      page.forms_with(:action => AUTH_ACTION).each do |f|
        f.username = @user
        f.password = @pass
        f.submit
      end
    end
    # TODO: The response must be expected page
    @logged_in_user = @user
  end

  def clear_bookings
    @bookings = nil
  end

  def future_bookings
    @bookings ||= _get_bookings
  end

  def _get_bookings
    bookings = []
    agent.get(SCHEDULE_URL) do |page|
      table = page.at('table[@id="futureBookings"]')
      table.search('tr.items').each do |row|
        booking_id = row.attr('_bookingid')
        date = row.at('td[1]').text.strip       # 日付
        time = row.at('td[2]').text.strip       # 開始時刻
        instructor = row.at('td[3]').text.strip # インストラクター
        ls = row.at('td[4]').text.strip         # ラーニングスタジオ
        course = row.at('td[5]').text.strip     # コース

        start_time = Time.parse("#{date} #{time}")
        end_time = Time.at(start_time.to_i + 60 * 40)

        bookings << {
          :id => booking_id,
          :date => date,
          :time => time,
          :instructor => instructor,
          :ls => ls,
          :course => course
        }
      end
    end
    bookings
  end
end

class GoogleCalendar
  def initialize(user, pass, appname)
    @user = user
    @pass = pass
    @appname = appname
  end

  def calendar
    @calendar ||= Google::Calendar.new(
                            :username => @user,
                            :password => @pass,
                            :app_name => @appname)
  end

  def delete_events_in_range(start_min, start_max, criteria)
    events = calendar.find_events_in_range(start_min, start_max)
    events ||= []
    events.each do |e|
      next if /#{criteria[:title]}/ !~ e.title if criteria[:title] != nil
      puts e.title
      puts e.start_time
      calendar.delete_event(e)
    end 
  end

  def create_event(event)
    event = calendar.create_event do |e|
      e.title = event[:title]
      e.where = event[:where]
      e.content = event[:content]
      e.start_time = event[:start_time]
      e.end_time = event[:end_time]
    end
  end
end

class Sync
  APPNAME = 'gaba-googlecalendar-sync'
  TITLE = 'Gaba Lesson'

  def sync
    pit = Pit.get('my.gaba.jp')
    mygaba = Gaba.new(pit['username'], pit['password'])
    mygaba.login
    bookings = mygaba.future_bookings

    pit = Pit.get('google.com')
    calendar = GoogleCalendar.new(pit['username'], pit['password'], APPNAME)
    start_min = Time.now
    start_max = Time.local(start_min.year, start_min.month + 3, 1, 0, 0, 0) - 1
    calendar.delete_events_in_range(start_min, start_max,  {:title => TITLE})
    bookings.each do |booking|
      e = format_event(booking)
      calendar.create_event(e)
    end
  end

  def format_event(booking)
    start_time = Time.parse("#{booking[:date]} #{booking[:time]}")
    end_time = Time.at(start_time.to_i + 60 * 40)
    event = {
      :title => TITLE,
      :where => booking[:ls],
      :content => "#{booking[:date]}\n#{booking[:time]}\n#{booking[:instructor]}\n#{booking[:ls]}\n",
      :start_time => start_time,
      :end_time => end_time
    }
  end
end

s = Sync.new
s.sync

