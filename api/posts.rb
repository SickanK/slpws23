require 'securerandom'
require 'sinatra'
require 'sinatra/reloader'

get('/posts') do
    slim(:posts)
end