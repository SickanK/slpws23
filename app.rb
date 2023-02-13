require "securerandom"
require "sinatra"
require "sinatra/reloader"
require "slim"
require "sqlite3"
require_relative "api/auth.rb"
require_relative "api/app.rb"
require "redis"

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
  def partial(name, locals: {}, path: "/partials")
    captured_block = block_given? ? yield : nil
    locals.merge!(:children => captured_block)
    Slim::Template.new("#{settings.views}#{path}/#{name}.slim").render(self, locals)
  end

  def value(key)
    @values&.fetch(key, "")
  end

  def error(key)
    @errors&.fetch(key, "")
  end
end

before do
  protected_routes = ["/app"]

  if protected_routes.include?(request.path_info)
    if session[:user_id] == nil
      redirect("/login")
    end
  end
end

get "/" do
  slim(:index)
end
