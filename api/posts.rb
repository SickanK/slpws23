require "securerandom"
require "sinatra"
require "sinatra/reloader"

get("/test") do
  slim(:test)
end
