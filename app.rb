require "securerandom"
require "sinatra"
require "sinatra/reloader"
require "slim"
require "sqlite3"
require_relative "api/auth.rb"
require_relative "api/posts.rb"

enable :sessions

DB_PATH = "db/knowledgeManager.db"

helpers do
  def connect_to_db()
    db = SQLite3::Database.new(DB_PATH)
    db.results_as_hash = true
    return db
  end
end

before do
  PROTCTED_ROUTES = ["/test"]

  if PROTECTED_ROUTES.include?(request.path_info)
    if session[:user_id] == nil
      redirect("/login")
    end
  end
end

get "/" do
  slim(:index)
end
