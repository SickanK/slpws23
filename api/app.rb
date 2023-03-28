#!/usr/bin/env ruby
# encoding: utf-8

require "securerandom"
require "sinatra"
require "sinatra/reloader"

require_relative "../models/tag.rb"
require_relative "../models/post.rb"
require_relative "../models/database.rb"

# Before accessing any '/app*' route
#
# This route checks for user authentication and retrieves necessary data for '/app*' routes.
# It sets errors, values, database_tags, and user databases as instance variables.
# If the user is not authenticated, it redirects to the login page.
# If the user is authenticated, it retrieves the user's databases and their tags.
before "/app*" do
  @errors = session.delete(:errors)
  @values = session.delete(:values)

  if session[:user_id].nil?
    redirect("/login")
  end

  @database_tags = get_tags_for_database(session[:user_id])

  databases = get_databases(session[:user_id])
  @databases = databases.map { |database| { "name" => database["name"], "id" => database["database_id"], "posts" => database["posts"], "permission_type" => database["permission_type"] } }
  @open_database = nil
end

# Displays the admin panel
#
# @see get_owned_databases_with_permissions
get("/app/admin_panel") do
  @owned_databases = get_owned_databases_with_permissions(session[:user_id])

  slim(:"routes/app/admin_panel", :layout => :"layouts/app")
end

# Displays the main app page
#
get("/app") do
  slim(:"routes/app/index", :layout => :"layouts/app")
end

# Displays the new post creation page
#
get("/app/post/new") do
  slim(:"routes/app/post/new", :layout => :"layouts/app")
end

# Creates a new post and redirects to the post's page
#
# @param [String] title, The title of the new post
# @param [String] content, The content of the new post
# @param [String] tags, A space-separated list of tags for the new post
# @param [String] database_id, The ID of the database where the new post will be stored
#
# @see Function#new_post
# @see Function#add_tags_to_post_and_database
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

  form.validate(:tags) do |tags|
    raise "Du måste fylla i fältet" if tags.empty?
    raise "Du kan bara använda bokstäver, siffror och mellanslag" if !tags.match(/^[a-zåäöA-ZÅÄÖ0-9 ]+$/)
    raise "Du kan bara använda 10 taggar" if tags.split(" ").length > 10
  end

  form.validate(:database_id) do |database_id|
    raise "Du måste fylla i fältet" if database_id.empty?
  end

  send_response(form, rate_limiter, "/app/post/new") if !form.success?

  new_post_id = new_post(params[:title], params[:content], params[:database_id])
  add_tags_to_post_and_database(new_post_id, params[:database_id], params[:tags].split(" "))

  redirect("/app/#{new_post_id}")
end

# Deletes a post and redirects to the '/app' page
#
# @param [String] post_id, The ID of the post to be deleted
#
# @see Function#delete_post
post("/post/delete") do
  rate_limiter = RateLimiter.new(REDIS, request, 6, 10)
  form = FormValidator.new(params)

  # Validate form
  form.validate(:post_id) do |post_id|
    raise "Hittade inget post id" if post_id.empty?
  end

  send_response(form, rate_limiter, request.referrer) if !form.success?

  delete_post(params[:post_id])

  redirect("/app")
end

# Displays a specific post
#
# @param [Integer] :post_id, the ID of the post
# @see get_post
# @see get_tags_for_post
get("/app/:post_id") do
  @post = get_post(params[:post_id])

  if @post.nil?
    redirect("/app")
  end

  @tags = get_tags_for_post(params[:post_id])

  @open_database = @post["database_id"]
  @open_post = @post["post_id"]

  slim(:"routes/app/post/show", :layout => :"layouts/app")
end

# Displays the edit page for a particular post
#
# @param [Integer] :post_id, the ID of the post to be edited
# @see Model#get_post
# @see Model#get_tags_for_post
get("/app/:post_id/edit") do
  @post = get_post(params[:post_id])
  @tags = get_tags_for_post(params[:post_id])

  slim(:"routes/app/post/edit", :layout => :"layouts/app")
end

# Edits an existing post and redirects to the post's page
#
# @param [String] post_id, The ID of the post to be edited
# @param [String] title, The new title of the post
# @param [String] content, The new content of the post
#
# @see Function#edit_post
post("/post/edit") do
  rate_limiter = RateLimiter.new(REDIS, request, 6, 10)
  form = FormValidator.new(params)

  # Validate form
  form.validate(:post_id) do |post_id|
    raise "Hittade inget post id" if post_id.empty?
  end

  form.validate(:title) do |title|
    raise "Du måste fylla i fältet" if title.empty?
  end

  form.validate(:content) do |content|
    raise "Du måste fylla i fältet" if content.empty?
  end

  send_response(form, rate_limiter, request.referrer) if !form.success?

  edit_post(params[:post_id], params[:title], params[:content])

  redirect("/app/#{params[:post_id]}")
end

# Creates a new database and redirects to the referring page
#
# @param [String] name, The name of the new database
#
# @see Function#new_database
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

# Deletes a post and redirects to the '/app' page
#
# @param [String] post_id, The ID of the post to be deleted
#
# @see Function#delete_post
post("/database/delete") do
  rate_limiter = RateLimiter.new(REDIS, request, 6, 10)
  form = FormValidator.new(params)

  # Validate form
  form.validate(:database_id) do |database_id|
    raise "Hittade inget databas id" if database_id.empty?
  end

  send_response(form, rate_limiter, request.referrer) if !form.success?

  begin
    delete_database(params[:database_id])
  rescue Exception => e
    form.error(:database) { raise ClearField, "Du äger inte denna databasen" if e.message == "userNotOwner" }
  end

  redirect("/app")
end

# New Tag

# Deletes a database and redirects to the '/app' page
#
# @param [String] database_id, The ID of the database to be deleted
#
# @see Function#delete_database
post("/tag/new") do
  rate_limiter = RateLimiter.new(REDIS, request, 6, 10)
  form = FormValidator.new(params)

  # Validate form

  form.validate(:title) do |title|
    raise "Du måste fylla i fältet" if title.empty?
  end

  form.validate(:post_id) do |post_id|
    raise "Hittade inget post id" if post_id.empty?
  end

  form.validate(:database_id) do |database_id|
    raise "Hittade inget databas id" if database_id.empty?
  end

  send_response(form, rate_limiter, request.referrer) if !form.success?

  add_tags_to_post_and_database(params[:post_id], params[:database_id], [params[:title]])

  redirect(request.referrer)
end

# Displays all posts associated with a specific tag
#
# @param [Integer] :tag_id, the ID of the tag
# @see Function#get_tag
# @see Function#get_posts_for_tag
get("/app/tag/:tag_id") do
  @tag = get_tag(params[:tag_id])
  @posts = get_posts_for_tag(params[:tag_id])

  slim(:"routes/app/tag/show", :layout => :"layouts/app")
end

# Deletes a tag and redirects to the '/app' page
#
# @param [String] tag_id, The ID of the tag to be deleted
#
# @see Function#delete_tag
post("/tag/delete") do
  rate_limiter = RateLimiter.new(REDIS, request, 6, 10)
  form = FormValidator.new(params)

  # Validate form
  form.validate(:tag_id) do |tag_id|
    raise "Hittade inget tag id" if tag_id.empty?
  end

  send_response(form, rate_limiter, request.referrer) if !form.success?

  delete_tag(params[:tag_id])

  redirect("/app")
end

# Removes a tag from a post and redirects to the referring page
#
# @param [String] tag_id, The ID of the tag to be removed
# @param [String] post_id, The ID of the post from which the tag will be removed
#
# @see Function#remove_tag_from_post
post("/post/tag/remove") do
  rate_limiter = RateLimiter.new(REDIS, request, 6, 10)
  form = FormValidator.new(params)

  # Validate form
  form.validate(:tag_id) do |tag_id|
    raise "Hittade inget tag id" if tag_id.empty?
  end

  form.validate(:post_id) do |post_id|
    raise "Hittade inget post id" if post_id.empty?
  end

  send_response(form, rate_limiter, request.referrer) if !form.success?

  remove_tag_from_post(params[:tag_id], params[:post_id])

  redirect(request.referrer)
end

# Adds a user to a database by their email and redirects to the referring page
#
# @param [String] database_id, The ID of the database to which the user will be added
# @param [String] email, The email of the user to be added
#
# @see Function#add_user_by_email_to_database
post("/database/user/add") do
  rate_limiter = RateLimiter.new(REDIS, request, 6, 10)
  form = FormValidator.new(params)

  # Validate form
  form.validate(:database_id) do |database_id|
    raise "Hittade inget databas id" if database_id.empty?
  end

  form.validate(:email) do |user_id|
    raise "Hittade inget användar id" if user_id.empty?
  end

  send_response(form, rate_limiter, request.referrer) if !form.success?

  begin
    add_user_by_email_to_database(params[:database_id], params[:email], session[:user_id])
  rescue Exception => e
    form.error(:email) { raise ClearField, "Användare finns inte" if e.message == "userNotExist" }
    form.error(:email) { raise ClearField, "Användaren finns redan i databasen" if e.message == "userAlreadyInDatabase" }
    form.error(:email) { raise ClearField, "Du måste äga databasen för att utföra denna handling" if e.message == "userNotOwner" }

    send_response(form, rate_limiter, request.referrer) if !form.success?
  end

  redirect(request.referrer)
end

# Removes a user from a database and redirects to the referring page
#
# @param [String] database_id, The ID of the database from which the user will be removed
# @param [String] user_id, The ID of the user to be removed from the database
#
# @see Function#remove_user_from_database
post("/database/user/remove") do
  rate_limiter = RateLimiter.new(REDIS, request, 6, 10)
  form = FormValidator.new(params)

  # Validate form
  form.validate(:database_id) do |database_id|
    raise "Hittade inget databas id" if database_id.empty?
  end

  form.validate(:user_id) do |user_id|
    raise "Hittade inget användar id" if user_id.empty?
  end

  send_response(form, rate_limiter, request.referrer) if !form.success?

  remove_user_from_database(params[:database_id], params[:user_id])

  redirect(request.referrer)
end
