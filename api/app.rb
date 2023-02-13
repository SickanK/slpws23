require "securerandom"
require "sinatra"
require "sinatra/reloader"

get("/app") do
  slim(:app)
end
