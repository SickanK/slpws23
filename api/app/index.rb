#!/usr/bin/env ruby
# encoding: utf-8

require "securerandom"
require "sinatra"
require "sinatra/reloader"
require "bcrypt"
require_relative "../models/auth.rb"

# app

get("/test") do
  slim(:test)
end
