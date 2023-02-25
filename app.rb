require "securerandom"
require "sinatra"
require "sinatra/reloader"
require "slim"
require "sqlite3"
require "redis"

require_relative "api/auth.rb"
require_relative "api/app.rb"

enable :sessions
set :session_secret, "super secret"
set :sessions, :expire_after => 2592000

# Databaser

REDIS = Redis.new(host: "localhost", port: 6379, db: 0)

def connect_to_db()
  db = SQLite3::Database.new("db/knowledgeManager.db")
  db.results_as_hash = true
  return db
end

# Sinatra

helpers do
  # https://stackoverflow.com/questions/28005961/reusable-slim-with-parameters
  def partial(name, register: false, locals: {}, path: "/partials")
    captured_block = block_given? ? yield : nil
    locals.merge!(:children => captured_block)

    # Due to the way sinatra and slim renders layouts, we cannot use global css in layouts if we don't "render" the partials before the style tag.
    locals.merge!(:register => register)

    Slim::Template.new("#{settings.views}#{path}/#{name}.slim").render(self, locals)
  end

  # According the mdn docs, all css should be rendered in the head tag. Otherwise, inline rendering would have worked perfectly fine.
  # https://developer.mozilla.org/en-US/docs/Web/HTML/Element/style
  def css(name = nil, render_inline = false)
    css_content = yield if block_given?
    return if css_content.nil?

    # If no name is given, just return the content regardless of whether it has been rendered before or not or if it should be rendered inline
    if name.nil?
      return css_content
    else
      # If the name is given, add it to the list of partials
      partial_path = "partials/#{name}.css"
      @stylesheet_paths << partial_path unless @stylesheet_paths.include?(partial_path)
    end

    # https://stackoverflow.com/questions/1634750/ruby-function-to-remove-all-white-spaces
    stripped_css_content = css_content.gsub(/\s+/, "").strip

    if @partials_rendered[name]&.include?(stripped_css_content)
      return css_content if render_inline
      return
    end

    # If the content is not rendered yet, add it to the list of rendered content
    @partials_rendered[name] ||= []
    @partials_rendered[name] << stripped_css_content

    # If the content should be rendered inline, return it
    return css_content if render_inline

    # Otherwise, add it to the style tag
    @style += css_content.delete_prefix("<style type=\"text/css\">").delete_suffix("</style>") + "\r\n"
    return ""
  end

  def link_css(path)
    css_path = "#{path}"
    @stylesheet_paths << css_path unless @stylesheet_paths.include?(css_path)
  end

  def value(key)
    @values&.fetch(key, "")
  end

  def error(key)
    @errors&.fetch(key, "")
  end
end

before do
  @partials_rendered = {}
  @style = ""
  @stylesheet_paths = []

  protected_routes = ["/app"]
  if protected_routes.include?(request.path_info)
    if session[:user_id] == nil
      redirect("/login")
    end
  end
end

get "/" do
  slim(:"routes/index")
end
