require 'net/http'
require 'net/https'
require 'uri'
require "rexml/document"

# Get rid of verification messages
class Net::HTTP
  alias_method :old_initialize, :initialize
  def initialize(*args)
    old_initialize(*args)
    @ssl_context = OpenSSL::SSL::SSLContext.new
    @ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
  end
end

PROJECT_ID = "<YOUR PROJECT ID HERE>"
TRACKER_TOKEN = "<YOUR TOKEN HERE>"

API_URL = "https://www.pivotaltracker.com/services/v3/projects/#{PROJECT_ID}"

STORY_QA_TASKS = [
  "[Release Manager] Deployed to staging",
  "[Auto QA] Smoke tests passed on staging",
  "[Auto QA] Automated scripts created",
  "[Auto QA] Automated scripts passed on staging",
  "[Auto QA] Automated regression passed on staging",
  "[Design Team] Styling complete on staging",
  "[QA] Manual QA passed on staging"
]

RELEASE_QA_TASKS = [
  "[Release Manager] Release tagged on staging",
  "[Auto QA] Smoke tests passed on staging",
  "[Auto QA] Automated test suite passed on staging",
  "[QA] Manual QA suite passed on staging",
  "[Management] Release approved for production",
  "[Release Manager] Deployed to production",
  "[Auto QA] Automated test suite passed on production",
  "[QA] Manual QA suite passed on production"
]

def do_request(url, request)
  session = Net::HTTP.new(url.host, url.port)
  session.use_ssl = true

  result = session.start do |http|
    http.request(request)
  end

  result.body
end

stories_url = URI.parse("#{API_URL}/stories?filter=state:unscheduled,unstarted")

stories_request = Net::HTTP::Get.new(stories_url.path)
stories_request.add_field 'X-TrackerToken', TRACKER_TOKEN

response = do_request(stories_url, stories_request)
stories_xml = REXML::Document.new(response).root

stories_xml.elements.each('//story') do |story|
  # Check if it's a release
  unless story.elements['story_type'].text.strip == "release"
    # Get the last task
    if story.elements['tasks/task[last()]']
      if story.elements['tasks/task[last()]/description'].text.strip == STORY_QA_TASKS.last
        puts "Story #{story.elements['id'].text} already set up for QA"
        next
      end
    end

    puts "Adding QA for #{story.elements['id'].text}"

    tasks_url = URI.parse("#{API_URL}/stories/#{story.elements['id'].text.strip}/tasks")

    STORY_QA_TASKS.each do |task|
      task_request = Net::HTTP::Post.new(tasks_url.path)
      task_request.add_field 'X-TrackerToken', TRACKER_TOKEN
      task_request.set_form_data("task[description]" => "#{task}")

      response = do_request(tasks_url, task_request)
    end
  else
    # Skip place-holder releases
    unless story.elements['name'].text.match("^-=")
      # Get the last task
      if story.elements['tasks/task[last()]']
        if story.elements['tasks/task[last()]/description'].text.strip == RELEASE_QA_TASKS.last
          puts "Release #{story.elements['id'].text} already set up for QA"
          next
        end
      end

      puts "Adding QA for release #{story.elements['name'].text}"

      tasks_url = URI.parse("#{API_URL}/stories/#{story.elements['id'].text.strip}/tasks")

      RELEASE_QA_TASKS.each do |task|
        task_request = Net::HTTP::Post.new(tasks_url.path)
        task_request.add_field 'X-TrackerToken', TRACKER_TOKEN
        task_request.set_form_data("task[description]" => "#{task}")

        response = do_request(tasks_url, task_request)
      end
    end
  end
end
