require 'rubygems'
require 'time'
require 'pp'
require 'mechanize'
require 'google/api_client/client_secrets'
require 'google/apis/calendar_v3'
require 'dotenv'
require 'pit'
require 'active_support'
require 'active_support/core_ext'

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
  def calendar
    return @calendar if @calendar

    Dotenv.load
    client        = Google::Apis::CalendarV3::CalendarService.new
    authorization = Google::APIClient::ClientSecrets.new(
      'web' => {
        client_id:     ENV['CLIENT_ID'],
        client_secret: ENV['CLIENT_SECRET'],
        refresh_token: ENV['REFRESH_TOKEN'],
      }
    ).to_authorization
    client.authorization = authorization

    @calendar = client
  end

  def delete_events_in_range(start_min, start_max, criteria)
    events = calendar.list_events('primary', time_min: start_min.iso8601, time_max: start_max.iso8601, q: criteria[:title])
    events.items.each do |e|
      calendar.delete_event('primary', e.id)
    end 
  end

  def create_event(event)
    event = calendar.insert_event('primary', event)
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

    calendar = GoogleCalendar.new
    start_min = Time.now
    start_max = start_min + 14.days
    calendar.delete_events_in_range(start_min, start_max,  {:title => TITLE})
    bookings.each do |booking|
      e = format_event(booking)
      calendar.create_event(e)
    end
  end

  def format_event(booking)
    start_time = Time.parse("#{booking[:date]} #{booking[:time]}")
    end_time = start_time + 40.minutes
    e = Google::Apis::CalendarV3::Event.new
    e.start = Google::Apis::CalendarV3::EventDateTime.new(date_time: start_time.to_datetime, time_zone: 'Asia/Tokyo')
    e.end   = Google::Apis::CalendarV3::EventDateTime.new(date_time: end_time.to_datetime, time_zone: 'Asia/Tokyo')
    e.summary = TITLE
    e.location = booking[:ls]
    e.description = "#{booking[:date]}\n#{booking[:time]}\n#{booking[:instructor]}\n#{booking[:ls]}\n"
    e
  end
end

s = Sync.new
s.sync

