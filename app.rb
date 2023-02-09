require "securerandom"
require "sinatra"
require "sinatra/reloader"
require "slim"
require "sqlite3"
require_relative "api/auth.rb"
require_relative "api/posts.rb"
require "redis"

# **TODO:**
# FUTURE!!
# - CREATE A HELPER FUNCTION THAT CHECKS THE RATELIMITER AND UPDATES the SESSION AUTOMATICALLY AT THE SAME TIME
# COULD BE EXTENSIONS OF THE FORM VALIDATOR CLASS

enable :sessions

REDIS = Redis.new(host: "localhost", port: 6379, db: 0)

def connect_to_db()
  db = SQLite3::Database.new("db/knowledgeManager.db")
  db.results_as_hash = true
  return db
end

helpers do
  def value(key)
    @values&.fetch(key, "")
  end

  def error(key)
    @errors&.fetch(key, "")
  end
end

before do
  protected_routes = ["/test"]

  if protected_routes.include?(request.path_info)
    if session[:user_id] == nil
      redirect("/login")
    end
  end
end

get "/" do
  slim(:index)
end
