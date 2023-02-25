#!/usr/bin/env ruby
# encoding: utf-8

require "securerandom"
require "sinatra"
require "sinatra/reloader"

require_relative "../models/post.rb"
require_relative "../models/database.rb"

before "/app*" do
  @errors = session.delete(:errors)
  @values = session.delete(:values)

  if session[:user_id].nil?
    redirect("/login")
  end

  databases = get_databases(session[:user_id])
  @databases = databases.map { |database| { "name" => database["name"], "id" => database["database_id"], "posts" => database["posts"] } }
end

get("/app") do
  slim(:"routes/app/index", :layout => :"layouts/app")
end

# New post

get("/app/new_post") do
  slim(:"routes/app/new_post", :layout => :"layouts/app")
end

post("/post/new") do
  rate_limiter = RateLimiter.new(REDIS, request, 6, 10)
  form = FormValidator.new(params)

  # Validate form

  form.validate(:title) do |title|
    raise "Du måste fylla i fältet" if title.empty?
  end

  form.validate(:content) do |content|
    raise "Du måste fylla i fältet" if content.empty?
  end

  form.validate(:database_id) do |database_id|
    raise "Du måste fylla i fältet" if database_id.empty?
  end

  send_response(form, rate_limiter, "/app/new_post") if !form.success?

  new_post_id = new_post(params[:title], params[:content], params[:database_id])

  redirect("/app/#{new_post_id}")
end

# View post

get("/app/:post_id") do
  @post = get_post(params[:post_id])
  slim(:"routes/app/view_post", :layout => :"layouts/app")
end

# New database

post("/database/new") do
  rate_limiter = RateLimiter.new(REDIS, request, 6, 10)
  form = FormValidator.new(params)

  # Validate form

  form.validate(:name) do |name|
    raise "Du måste fylla i fältet" if name.empty?
  end

  send_response(form, rate_limiter, request.referrer) if !form.success?

  new_database(session[:user_id], params[:name])

  redirect(request.referrer)
end
