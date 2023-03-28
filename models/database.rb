# Creates a new database and associates it with a user
#
# @param [Integer] user_id The ID of the user creating the database
# @param [String] name The name of the new database
#
# @return [Integer] The ID of the new database
def new_database(user_id, name)
  db = connect_to_db()

  created_at = Time.now.to_i

  db.execute("INSERT INTO Database (name, created_at, owner_id) VALUES (?, ?, ?)", [name, created_at, user_id])
  new_database_id = db.last_insert_row_id
  db.execute("INSERT INTO UserDatabaseRel (user_id, database_id, permission_type) VALUES (?, ?, ?)", [user_id, new_database_id, "owner"])
  db.close

  return new_database_id
end

# Get databases and their posts accessible by a given user
#
# @param [Integer] user_id The ID of the user
#
# @return [Array<Hash>]
#   * :database_id [Integer] The ID of the database
#   * :name [String] The name of the database
#   * :created_at [String] The date and time the database was created
#   * :updated_at [String] The date and time the database was last updated
#   * :permission_type [String] The type of permission the user has for the database
#   * :posts [Array<Hash>] An array of posts in the database
#     * :post_id [Integer] The ID of the post
#     * :title [String] The title of the post
#     * :content [String] The content of the post
def get_databases(user_id)
  db = connect_to_db()

  databases = db.execute(%{
    SELECT
      Database.database_id,
      Database.name,
      Database.created_at,
      Database.updated_at,
      UserDatabaseRel.permission_type
    FROM Database
    INNER JOIN UserDatabaseRel ON Database.database_id = UserDatabaseRel.database_id
    WHERE UserDatabaseRel.user_id = ?
  }.gsub(/\s+/, " ").strip, [user_id])

  # Get posts
  posts = db.execute(%{ 
    SELECT * FROM Post
    INNER JOIN UserDatabaseRel ON Post.database_id = UserDatabaseRel.database_id
    WHERE UserDatabaseRel.user_id = ?
  }.gsub(/\s+/, " ").strip, [user_id])
  db.close

  # Add posts to their respective database (should be done in a single sql query in the future)
  posts.each do |post|
    database = databases.find { |database| database["database_id"] == post["database_id"] }
    database["posts"] = [] if database["posts"].nil?
    database["posts"].push(post)
  end

  return databases
end

# Creates a new post in the database
#
# @param [String] title The title of the post
# @param [String] content The content of the post
# @param [Integer] database_id The ID of the database where the post will be created
#
# @return [Integer] the ID of the newly created post
def new_post(title, content, database_id)
  db = connect_to_db()

  created_at = Time.now.to_i

  db.execute("INSERT INTO Post (title, content, created_at, database_id) VALUES (?, ?, ?, ?)", [title, content, created_at, database_id])
  new_post_id = db.last_insert_row_id

  db.close

  return new_post_id
end

# Get a post from the database
#
# @param [Integer] post_id The ID of the post
#
# @return [Hash]
#   * :post_id [Integer] The ID of the post
#   * :title [String] The title of the post
#   * :content [String] The content of the post
#   * :created_at [DateTime] The date and time when the post was created
#   * :updated_at [DateTime] The date and time when the post was last updated
# @return [nil] if post is not found
def get_post(post_id)
  db = connect_to_db()

  post = db.execute("SELECT * FROM Post WHERE post_id = ?", [post_id]).first
  db.close

  return post
end

# Edits a post
#
# @param [Integer] post_id The ID of the post to edit
# @param [String] title The new title for the post
# @param [String] content The new content for the post
#
# @return [nil]
def edit_post(post_id, title, content)
  db = connect_to_db()

  db.execute("UPDATE Post SET title = ?, content = ? WHERE post_id = ?", [title, content, post_id])

  db.close
end

# Titleizes a string
#
# @param [String] string the string to be titleized
#
# @return [String] the titleized string
def titleize(string)
  string.split.map(&:capitalize).join(" ")
end

# Retrieves a tag from the database based on its ID
#
# @param [Integer] tag_id The ID of the tag to retrieve
#
# @return [Hash]
#   * :tag_id [Integer] The ID of the tag
#   * :name [String] The name of the tag
# @return [nil] if the tag is not found
def get_tag(tag_id)
  db = connect_to_db()
  tag = db.execute("SELECT * FROM Tag WHERE tag_id = ?", [tag_id]).first
  db.close

  return tag
end

# Finds a tag's ID based on its title
#
# @param [String] tag The title of the tag
#
# @return [Integer, nil] The ID of the tag, or nil if not found
def get_tag_id(tag)
  db = connect_to_db()
  titleized_tag = titleize(tag)
  result = db.execute("SELECT tag_id FROM Tag WHERE title = ?", [titleized_tag])
  db.close

  return result.empty? ? nil : result[0][0]
end

# Adds a tag if it does not exist in the database
#
# @param [String] tag the name of the tag to add
# @return [Integer] the ID of the tag that was added or already existed
def add_tag_if_not_exist(tag)
  tag_id = get_tag_id(tag)

  unless tag_id
    db = connect_to_db()
    titleized_tag = titleize(tag)
    db.execute("INSERT INTO Tag (title) VALUES (?)", [titleized_tag])
    tag_id = db.last_insert_row_id
    db.close
  end

  return tag_id
end

# Adds tags to a post and database
#
# @param [Integer] post_id The ID of the post
# @param [Integer] database_id The ID of the database
# @param [Array<String>] tags An array of tags to add
#
# @return [void]
def add_tags_to_post_and_database(post_id, database_id, tags)
  db = connect_to_db()

  tag_ids = tags.map { |tag| add_tag_if_not_exist(tag) }

  db.transaction do
    tag_ids.each_with_index do |tag_id, index|
      db.execute("INSERT OR IGNORE INTO PostTagRel (post_id, tag_id) VALUES (?, ?)", [post_id, tag_id])
      db.execute("INSERT OR IGNORE INTO TagDatabaseRel (database_id, tag_id) VALUES (?, ?)", [database_id, tag_id])
    end
  end

  db.close
end

# Finds all tags for a given post
#
# @param [Integer] post_id The ID of the post to find tags for
#
# @return [Array<Hash>]
#   * :tag_id [Integer] The ID of the tag
#   * :tag_name [String] The name of the tag
def get_tags_for_post(post_id)
  db = connect_to_db()
  tags = db.execute(%{
    SELECT * FROM Tag
    INNER JOIN PostTagRel ON Tag.tag_id = PostTagRel.tag_id
    WHERE PostTagRel.post_id = ?
  }.gsub(/\s+/, " ").strip, [post_id])
  db.close

  return tags
end

# Gets all tags for a user's databases
#
# @param [Integer] user_id The ID of the user
#
# @return [Array<Hash>] An array of hashes representing tags for user's databases
#   * :tag_id [Integer] The ID of the tag
#   * :name [String] The name of the tag
#   * :database_id [Integer] The ID of the database associated with the tag
#   * :database_name [String] The name of the database associated with the tag
def get_tags_for_database(user_id)
  db = connect_to_db()

  tags = db.execute(%{
    SELECT * FROM Tag
    INNER JOIN TagDatabaseRel ON Tag.tag_id = TagDatabaseRel.tag_id
    INNER JOIN Database ON TagDatabaseRel.database_id = Database.database_id
    INNER JOIN UserDatabaseRel ON Database.database_id = UserDatabaseRel.database_id
    WHERE UserDatabaseRel.user_id = ?
  }.gsub(/\s+/, " ").strip, [user_id])
  db.close

  return tags
end

# This method accepts a tag_id as an argument and returns all the posts that are associated with that tag.
# The method first connects to the database and then fetches all the posts that are associated with the given tag.
# It then fetches all the tags associated with each post using a join operation between Post, PostTagRel, and Tag tables.
# The method returns a hash containing all the posts associated with the given tag along with their associated tags.
#
# @param [Integer] tag_id The ID of the tag
#
# @return [Array<Hash>]
#   * :post_id [Integer] The ID of the post
#   * :title [String] The title of the post
#   * :content [String] The content of the post
#   * :tags [Array<Hash>]
#       * :tag_id [Integer] The ID of the tag
#       * :title [String] The title of the tag
def get_posts_for_tag(tag_id)
  db = connect_to_db()

  post_results = db.execute(%{
    SELECT
      Post.post_id,
      Post.title,
      Post.content
    FROM
      Post
      INNER JOIN PostTagRel ON Post.post_id = PostTagRel.post_id
    WHERE
      PostTagRel.tag_id = ?
}, [tag_id])

  posts = {}

  post_results.each do |result|
    post_id = result["post_id"]
    title = result["title"]
    content = result["content"]
    posts[post_id] = { "post_id" => post_id, "title" => title, "content" => content, "tags" => [] }
  end

  post_ids = posts.keys
  placeholders = post_ids.map { "?" }.join(", ")

  tag_results = db.execute(%{
    SELECT
      Post.post_id,
      Tag.tag_id,
      Tag.title as tag_title
    FROM
      Post
      INNER JOIN PostTagRel ON Post.post_id = PostTagRel.post_id
      INNER JOIN Tag ON PostTagRel.tag_id = Tag.tag_id
    WHERE
      Post.post_id IN (#{placeholders})
}, post_ids)

  db.close()

  tag_results.each do |result|
    post_id = result["post_id"]
    tag_id = result["tag_id"]
    tag_title = result["tag_title"]

    posts[post_id]["tags"] << { "tag_id" => tag_id, "title" => tag_title }
  end

  return posts.values
end

# Deletes a tag and all its associations from the database
#
# @param [Integer] tag_id The ID of the tag to delete
#
# @return [nil]
def delete_tag(tag_id)
  db = connect_to_db()
  db.execute("DELETE FROM Tag WHERE tag_id = ?", [tag_id])
  db.execute("DELETE FROM PostTagRel WHERE tag_id = ?", [tag_id])
  db.execute("DELETE FROM TagDatabaseRel WHERE tag_id = ?", [tag_id])
  db.close
end

# Deletes a post and its associated tags from the database
#
# @param [Integer] post_id The ID of the post to delete
#
# @return [nil]
def delete_post(post_id)
  db = connect_to_db()

  db.execute("DELETE FROM Post WHERE post_id = ?", [post_id])
  db.execute("DELETE FROM PostTagRel WHERE post_id = ?", [post_id])

  db.close
end

# Deletes a database and all associated posts and tags
#
# @param [Integer] database_id The ID of the database
# @param [Integer] user_id The ID of the user attempting to delete the database
#
# @return [nil]
#
# @raise [RuntimeError] if user is not the owner of the database
def delete_database(database_id, user_id)
  db = connect_to_db()

  owner = db.execute(%{
    SELECT
      UserDatabaseRel.user_id as owner_id
    FROM
      UserDatabaseRel
    WHERE
      UserDatabaseRel.database_id = ? AND UserDatabaseRel.user_id = ? AND UserDatabaseRel.permissions = 'owner'
  }.gsub(/\s+/, " ").strip, [database_id, user_id]).first

  if owner.nil? || owner.empty? || owner["owner_id"] != user_id
    db.close
    raise "userNotOwner"
  end

  db.execute("DELETE FROM Database WHERE database_id = ?", [database_id])
  db.execute("DELETE FROM UserDatabaseRel WHERE database_id = ?", [database_id])
  db.execute("DELETE FROM TagDatabaseRel WHERE database_id = ?", [database_id])

  # delete all posts
  db.execute("DELETE FROM Post WHERE database_id = ?", [database_id])
  db.execute("DELETE FROM PostTagRel WHERE post_id IN (SELECT post_id FROM Post WHERE database_id = ?)", [database_id])

  db.close
end

# Removes a tag from a post
#
# @param [Integer] tag_id The ID of the tag to remove
# @param [Integer] post_id The ID of the post to remove the tag from
#
# @return [nil]
def remove_tag_from_post(tag_id, post_id)
  db = connect_to_db()

  db.execute("DELETE FROM PostTagRel WHERE tag_id = ? AND post_id = ?", [tag_id, post_id])

  db.close
end

# Gets the databases owned by a user
#
# @param [Integer] user_id The ID of the user
#
# @return [Array<Hash>]
#   * :database_id [Integer] The ID of the database
#   * :name [String] The name of the database
#   * :created_at [String] The creation date of the database
#   * :updated_at [String] The last update date of the database
#   * :permission_type [String] The type of permission the user has (should be 'owner')
#   * :viewers [Array<Hash>]
#     * :user_id [Integer] The ID of the user with viewing permission
#     * :permission_type [String] The type of permission the user has (should be 'viewer')
def get_owned_databases(user_id)
  db = connect_to_db()

  # Fetch databases owned by the user
  owned_databases = db.execute(%{
    SELECT
      Database.database_id,
      Database.name,
      Database.created_at,
      Database.updated_at,
      UserDatabaseRel.permission_type
    FROM
      Database
    INNER JOIN UserDatabaseRel ON Database.database_id = UserDatabaseRel.database_id
    WHERE
      UserDatabaseRel.user_id = ? AND UserDatabaseRel.permission_type = 'owner'
  }.gsub(/\s+/, " ").strip, [user_id])

  db.close

  # Add the viewers for each owned database
  owned_databases.each do |database|
    database["viewers"] = get_database_viewers(database["database_id"])
  end

  return owned_databases
end

# Get all viewers of a database
#
# @param [Integer] database_id The ID of the database
#
# @return [Array<Hash>]
#   * :user_id [Integer] The ID of the viewer user
#   * :email [String] The email of the viewer user
#   * :permission_type [String] The permission type of the viewer user, in this case 'viewer'
# @return [nil] if no viewers are found
def get_database_viewers(database_id)
  db = connect_to_db()

  viewers = db.execute(%{
    SELECT
      User.user_id,
      User.email,
      UserDatabaseRel.permission_type
    FROM
      User
      INNER JOIN UserDatabaseRel ON User.user_id = UserDatabaseRel.user_id
    WHERE
      UserDatabaseRel.database_id = ?
      AND UserDatabaseRel.permission_type = 'viewer'
  }.gsub(/\s+/, " ").strip, [database_id])

  db.close

  return viewers
end

# Gets owned databases with their respective permissions
#
# @param [Integer] user_id The ID of the user who owns the databases
#
# @return [Array<Hash>]
#   * :database_id [Integer] The ID of the database
#   * :name [String] The name of the database
#   * :description [String] The description of the database
#   * :viewers [Array<Integer>] The IDs of users who can view the database
def get_owned_databases_with_permissions(user_id)
  owned_databases = get_owned_databases(user_id)

  owned_databases.each do |database|
    database["viewers"] = get_database_viewers(database["database_id"])
  end

  return owned_databases
end

# Adds a user by email to a database
#
# @param [Integer] database_id The ID of the database
# @param [String] email The email of the user to be added
# @param [Integer] user_id The ID of the user adding the new user
#
# @raise [StandardError] if the user adding the new user is not the owner of the database
# @raise [StandardError] if the user to be added does not exist
# @raise [StandardError] if the user to be added is already in the database
#
# @return [Hash] The user added to the database
def add_user_by_email_to_database(database_id, email, user_id)
  db = connect_to_db()

  owner = db.execute(%{
    SELECT
      UserDatabaseRel.user_id as owner_id FROM UserDatabaseRel
    WHERE
      UserDatabaseRel.database_id = ? AND UserDatabaseRel.user_id = ? AND UserDatabaseRel.permission_type = 'owner'
    }.gsub(/\s+/, " ").strip, [database_id, user_id]).first

  if owner.nil? || owner.empty? || owner["owner_id"] != user_id
    db.close
    raise "userNotOwner"
  end

  user = db.execute("SELECT * FROM User WHERE email = ?", [email]).first

  if user.nil?
    db.close
    raise "userNotExist"
  end

  user_already_exist = db.execute("SELECT * FROM UserDatabaseRel WHERE user_id = ? AND database_id = ?", [user["user_id"], database_id]).first

  if user_already_exist
    db.close
    raise "userAlreadyInDatabase"
  end

  db.execute("INSERT INTO UserDatabaseRel (user_id, database_id, permission_type) VALUES (?, ?, ?)", [user["user_id"], database_id, "viewer"])

  db.close

  return user
end

# Removes a user from a database
#
# @param [Integer] database_id The ID of the database
# @param [Integer] user_id The ID of the user to be removed
#
# @return [nil]
def remove_user_from_database(database_id, user_id)
  db = connect_to_db()

  db.execute(%{
    DELETE UserDatabaseRel
    FROM UserDatabaseRel
    INNER JOIN Database ON UserDatabaseRel.database_id = Database.database_id
    WHERE UserDatabaseRel.user_id = ? AND UserDatabaseRel.permission_type = 'owner'
  }.gsub(/\s+/, " ").strip, [user_id])

  db.close
end

# Get all viewers of a database
#
# @param [Integer] database_id The ID of the database
#
# @return [Array<Hash>]
#   * :user_id [Integer] The ID of the viewer user
#   * :email [String] The email of the viewer user
#   * :permission_type [String] The permission type of the viewer user, in this case 'viewer'
# @return [nil] if no viewers are found
def get_database_viewers(database_id)
  db = connect_to_db()

  viewers = db.execute(%{
    SELECT
      User.user_id,
      User.email,
      UserDatabaseRel.permission_type
    FROM
      User
      INNER JOIN UserDatabaseRel ON User.user_id = UserDatabaseRel.user_id
    WHERE
      UserDatabaseRel.database_id = ?
      AND UserDatabaseRel.permission_type = 'viewer'
  }.gsub(/\s+/, " ").strip, [database_id])

  db.close

  return viewers
end

# Creates a new post in the database
#
# @param [String] title The title of the post
# @param [String] content The content of the post
# @param [Integer] database_id The ID of the database where the post will be created
#
# @return [Integer] the ID of the newly created post
def new_post(title, content, database_id)
  db = connect_to_db()

  created_at = Time.now.to_i

  db.execute("INSERT INTO Post (title, content, created_at, database_id) VALUES (?, ?, ?, ?)", [title, content, created_at, database_id])
  new_post_id = db.last_insert_row_id

  db.close

  return new_post_id
end

# Get a post from the database
#
# @param [Integer] post_id The ID of the post
#
# @return [Hash]
#   * :post_id [Integer] The ID of the post
#   * :title [String] The title of the post
#   * :content [String] The content of the post
#   * :created_at [DateTime] The date and time when the post was created
#   * :updated_at [DateTime] The date and time when the post was last updated
# @return [nil] if post is not found
def get_post(post_id)
  db = connect_to_db()

  post = db.execute("SELECT * FROM Post WHERE post_id = ?", [post_id]).first
  db.close

  return post
end

# Edits a post
#
# @param [Integer] post_id The ID of the post to edit
# @param [String] title The new title for the post
# @param [String] content The new content for the post
#
# @return [nil]
def edit_post(post_id, title, content)
  db = connect_to_db()

  db.execute("UPDATE Post SET title = ?, content = ? WHERE post_id = ?", [title, content, post_id])

  db.close
end

# Titleizes a string
#
# @param [String] string the string to be titleized
#
# @return [String] the titleized string
def titleize(string)
  string.split.map(&:capitalize).join(" ")
end

# Retrieves a tag from the database based on its ID
#
# @param [Integer] tag_id The ID of the tag to retrieve
#
# @return [Hash]
#   * :tag_id [Integer] The ID of the tag
#   * :name [String] The name of the tag
# @return [nil] if the tag is not found
def get_tag(tag_id)
  db = connect_to_db()
  tag = db.execute("SELECT * FROM Tag WHERE tag_id = ?", [tag_id]).first
  db.close

  return tag
end

# Finds a tag's ID based on its title
#
# @param [String] tag The title of the tag
#
# @return [Integer, nil] The ID of the tag, or nil if not found
def get_tag_id(tag)
  db = connect_to_db()
  titleized_tag = titleize(tag)
  result = db.execute("SELECT tag_id FROM Tag WHERE title = ?", [titleized_tag])
  db.close

  return result.empty? ? nil : result[0][0]
end

# Adds a tag if it does not exist in the database
#
# @param [String] tag the name of the tag to add
# @return [Integer] the ID of the tag that was added or already existed
def add_tag_if_not_exist(tag)
  tag_id = get_tag_id(tag)

  unless tag_id
    db = connect_to_db()
    titleized_tag = titleize(tag)
    db.execute("INSERT INTO Tag (title) VALUES (?)", [titleized_tag])
    tag_id = db.last_insert_row_id
    db.close
  end

  return tag_id
end

# Adds tags to a post and database
#
# @param [Integer] post_id The ID of the post
# @param [Integer] database_id The ID of the database
# @param [Array<String>] tags An array of tags to add
#
# @return [void]
def add_tags_to_post_and_database(post_id, database_id, tags)
  db = connect_to_db()

  tag_ids = tags.map { |tag| add_tag_if_not_exist(tag) }

  db.transaction do
    tag_ids.each_with_index do |tag_id, index|
      db.execute("INSERT OR IGNORE INTO PostTagRel (post_id, tag_id) VALUES (?, ?)", [post_id, tag_id])
      db.execute("INSERT OR IGNORE INTO TagDatabaseRel (database_id, tag_id) VALUES (?, ?)", [database_id, tag_id])
    end
  end

  db.close
end

# Finds all tags for a given post
#
# @param [Integer] post_id The ID of the post to find tags for
#
# @return [Array<Hash>]
#   * :tag_id [Integer] The ID of the tag
#   * :tag_name [String] The name of the tag
def get_tags_for_post(post_id)
  db = connect_to_db()
  tags = db.execute(%{
    SELECT * FROM Tag
    INNER JOIN PostTagRel ON Tag.tag_id = PostTagRel.tag_id
    WHERE PostTagRel.post_id = ?
  }.gsub(/\s+/, " ").strip, [post_id])
  db.close

  return tags
end

# Gets all tags for a user's databases
#
# @param [Integer] user_id The ID of the user
#
# @return [Array<Hash>] An array of hashes representing tags for user's databases
#   * :tag_id [Integer] The ID of the tag
#   * :name [String] The name of the tag
#   * :database_id [Integer] The ID of the database associated with the tag
#   * :database_name [String] The name of the database associated with the tag
def get_tags_for_database(user_id)
  db = connect_to_db()

  tags = db.execute(%{
    SELECT * FROM Tag
    INNER JOIN TagDatabaseRel ON Tag.tag_id = TagDatabaseRel.tag_id
    INNER JOIN Database ON TagDatabaseRel.database_id = Database.database_id
    INNER JOIN UserDatabaseRel ON Database.database_id = UserDatabaseRel.database_id
    WHERE UserDatabaseRel.user_id = ?
  }.gsub(/\s+/, " ").strip, [user_id])
  db.close

  return tags
end

# This method accepts a tag_id as an argument and returns all the posts that are associated with that tag.
# The method first connects to the database and then fetches all the posts that are associated with the given tag.
# It then fetches all the tags associated with each post using a join operation between Post, PostTagRel, and Tag tables.
# The method returns a hash containing all the posts associated with the given tag along with their associated tags.
#
# @param [Integer] tag_id The ID of the tag
#
# @return [Array<Hash>]
#   * :post_id [Integer] The ID of the post
#   * :title [String] The title of the post
#   * :content [String] The content of the post
#   * :tags [Array<Hash>]
#       * :tag_id [Integer] The ID of the tag
#       * :title [String] The title of the tag
def get_posts_for_tag(tag_id)
  db = connect_to_db()

  post_results = db.execute(%{
    SELECT
      Post.post_id,
      Post.title,
      Post.content
    FROM
      Post
      INNER JOIN PostTagRel ON Post.post_id = PostTagRel.post_id
    WHERE
      PostTagRel.tag_id = ?
}, [tag_id])

  posts = {}

  post_results.each do |result|
    post_id = result["post_id"]
    title = result["title"]
    content = result["content"]
    posts[post_id] = { "post_id" => post_id, "title" => title, "content" => content, "tags" => [] }
  end

  post_ids = posts.keys
  placeholders = post_ids.map { "?" }.join(", ")

  tag_results = db.execute(%{
    SELECT
      Post.post_id,
      Tag.tag_id,
      Tag.title as tag_title
    FROM
      Post
      INNER JOIN PostTagRel ON Post.post_id = PostTagRel.post_id
      INNER JOIN Tag ON PostTagRel.tag_id = Tag.tag_id
    WHERE
      Post.post_id IN (#{placeholders})
}, post_ids)

  db.close()

  tag_results.each do |result|
    post_id = result["post_id"]
    tag_id = result["tag_id"]
    tag_title = result["tag_title"]

    posts[post_id]["tags"] << { "tag_id" => tag_id, "title" => tag_title }
  end

  return posts.values
end

# Deletes a tag and all its associations from the database
#
# @param [Integer] tag_id The ID of the tag to delete
#
# @return [nil]
def delete_tag(tag_id)
  db = connect_to_db()
  db.execute("DELETE FROM Tag WHERE tag_id = ?", [tag_id])
  db.execute("DELETE FROM PostTagRel WHERE tag_id = ?", [tag_id])
  db.execute("DELETE FROM TagDatabaseRel WHERE tag_id = ?", [tag_id])
  db.close
end

# Deletes a post and its associated tags from the database
#
# @param [Integer] post_id The ID of the post to delete
#
# @return [nil]
def delete_post(post_id)
  db = connect_to_db()

  db.execute("DELETE FROM Post WHERE post_id = ?", [post_id])
  db.execute("DELETE FROM PostTagRel WHERE post_id = ?", [post_id])

  db.close
end

# Deletes a database and all associated posts and tags
#
# @param [Integer] database_id The ID of the database
# @param [Integer] user_id The ID of the user attempting to delete the database
#
# @return [nil]
#
# @raise [RuntimeError] if user is not the owner of the database
def delete_database(database_id, user_id)
  db = connect_to_db()

  owner = db.execute(%{
    SELECT
      UserDatabaseRel.user_id as owner_id
    FROM
      UserDatabaseRel
    WHERE
      UserDatabaseRel.database_id = ? AND UserDatabaseRel.user_id = ? AND UserDatabaseRel.permissions = 'owner'
  }.gsub(/\s+/, " ").strip, [database_id, user_id]).first

  if owner.nil? || owner.empty? || owner["owner_id"] != user_id
    db.close
    raise "userNotOwner"
  end

  db.execute("DELETE FROM Database WHERE database_id = ?", [database_id])
  db.execute("DELETE FROM UserDatabaseRel WHERE database_id = ?", [database_id])
  db.execute("DELETE FROM TagDatabaseRel WHERE database_id = ?", [database_id])

  # delete all posts
  db.execute("DELETE FROM Post WHERE database_id = ?", [database_id])
  db.execute("DELETE FROM PostTagRel WHERE post_id IN (SELECT post_id FROM Post WHERE database_id = ?)", [database_id])

  db.close
end

# Removes a tag from a post
#
# @param [Integer] tag_id The ID of the tag to remove
# @param [Integer] post_id The ID of the post to remove the tag from
#
# @return [nil]
def remove_tag_from_post(tag_id, post_id)
  db = connect_to_db()

  db.execute("DELETE FROM PostTagRel WHERE tag_id = ? AND post_id = ?", [tag_id, post_id])

  db.close
end

# Gets the databases owned by a user
#
# @param [Integer] user_id The ID of the user
#
# @return [Array<Hash>]
#   * :database_id [Integer] The ID of the database
#   * :name [String] The name of the database
#   * :created_at [String] The creation date of the database
#   * :updated_at [String] The last update date of the database
#   * :permission_type [String] The type of permission the user has (should be 'owner')
#   * :viewers [Array<Hash>]
#     * :user_id [Integer] The ID of the user with viewing permission
#     * :permission_type [String] The type of permission the user has (should be 'viewer')
def get_owned_databases(user_id)
  db = connect_to_db()

  # Fetch databases owned by the user
  owned_databases = db.execute(%{
    SELECT
      Database.database_id,
      Database.name,
      Database.created_at,
      Database.updated_at,
      UserDatabaseRel.permission_type
    FROM
      Database
    INNER JOIN UserDatabaseRel ON Database.database_id = UserDatabaseRel.database_id
    WHERE
      UserDatabaseRel.user_id = ? AND UserDatabaseRel.permission_type = 'owner'
  }.gsub(/\s+/, " ").strip, [user_id])

  db.close

  # Add the viewers for each owned database
  owned_databases.each do |database|
    database["viewers"] = get_database_viewers(database["database_id"])
  end

  return owned_databases
end

# Get all viewers of a database
#
# @param [Integer] database_id The ID of the database
#
# @return [Array<Hash>]
#   * :user_id [Integer] The ID of the viewer user
#   * :email [String] The email of the viewer user
#   * :permission_type [String] The permission type of the viewer user, in this case 'viewer'
# @return [nil] if no viewers are found
def get_database_viewers(database_id)
  db = connect_to_db()

  viewers = db.execute(%{
    SELECT
      User.user_id,
      User.email,
      UserDatabaseRel.permission_type
    FROM
      User
      INNER JOIN UserDatabaseRel ON User.user_id = UserDatabaseRel.user_id
    WHERE
      UserDatabaseRel.database_id = ?
      AND UserDatabaseRel.permission_type = 'viewer'
  }.gsub(/\s+/, " ").strip, [database_id])

  db.close

  return viewers
end

# Gets owned databases with their respective permissions
#
# @param [Integer] user_id The ID of the user who owns the databases
#
# @return [Array<Hash>]
#   * :database_id [Integer] The ID of the database
#   * :name [String] The name of the database
#   * :description [String] The description of the database
#   * :viewers [Array<Integer>] The IDs of users who can view the database
def get_owned_databases_with_permissions(user_id)
  owned_databases = get_owned_databases(user_id)

  owned_databases.each do |database|
    database["viewers"] = get_database_viewers(database["database_id"])
  end

  return owned_databases
end

# Adds a user by email to a database
#
# @param [Integer] database_id The ID of the database
# @param [String] email The email of the user to be added
# @param [Integer] user_id The ID of the user adding the new user
#
# @raise [StandardError] if the user adding the new user is not the owner of the database
# @raise [StandardError] if the user to be added does not exist
# @raise [StandardError] if the user to be added is already in the database
#
# @return [Hash] The user added to the database
def add_user_by_email_to_database(database_id, email, user_id)
  db = connect_to_db()

  owner = db.execute(%{
    SELECT
      UserDatabaseRel.user_id as owner_id FROM UserDatabaseRel
    WHERE
      UserDatabaseRel.database_id = ? AND UserDatabaseRel.user_id = ? AND UserDatabaseRel.permission_type = 'owner'
    }.gsub(/\s+/, " ").strip, [database_id, user_id]).first

  if owner.nil? || owner.empty? || owner["owner_id"] != user_id
    db.close
    raise "userNotOwner"
  end

  user = db.execute("SELECT * FROM User WHERE email = ?", [email]).first

  if user.nil?
    db.close
    raise "userNotExist"
  end

  user_already_exist = db.execute("SELECT * FROM UserDatabaseRel WHERE user_id = ? AND database_id = ?", [user["user_id"], database_id]).first

  if user_already_exist
    db.close
    raise "userAlreadyInDatabase"
  end

  db.execute("INSERT INTO UserDatabaseRel (user_id, database_id, permission_type) VALUES (?, ?, ?)", [user["user_id"], database_id, "viewer"])

  db.close

  return user
end

# Removes a user from a database
#
# @param [Integer] database_id The ID of the database
# @param [Integer] user_id The ID of the user to be removed
#
# @return [nil]
def remove_user_from_database(database_id, user_id)
  db = connect_to_db()

  db.execute(%{
    DELETE UserDatabaseRel
    FROM UserDatabaseRel
    INNER JOIN Database ON UserDatabaseRel.database_id = Database.database_id
    WHERE UserDatabaseRel.user_id = ? AND UserDatabaseRel.permission_type = 'owner'
  }.gsub(/\s+/, " ").strip, [user_id])

  db.close
end

# Creates a new post in the database
#
# @param [String] title The title of the post
# @param [String] content The content of the post
# @param [Integer] database_id The ID of the database where the post will be created
#
# @return [Integer] the ID of the newly created post
def new_post(title, content, database_id)
  db = connect_to_db()

  created_at = Time.now.to_i

  db.execute("INSERT INTO Post (title, content, created_at, database_id) VALUES (?, ?, ?, ?)", [title, content, created_at, database_id])
  new_post_id = db.last_insert_row_id

  db.close

  return new_post_id
end

# Get a post from the database
#
# @param [Integer] post_id The ID of the post
#
# @return [Hash]
#   * :post_id [Integer] The ID of the post
#   * :title [String] The title of the post
#   * :content [String] The content of the post
#   * :created_at [DateTime] The date and time when the post was created
#   * :updated_at [DateTime] The date and time when the post was last updated
# @return [nil] if post is not found
def get_post(post_id)
  db = connect_to_db()

  post = db.execute("SELECT * FROM Post WHERE post_id = ?", [post_id]).first
  db.close

  return post
end

# Edits a post
#
# @param [Integer] post_id The ID of the post to edit
# @param [String] title The new title for the post
# @param [String] content The new content for the post
#
# @return [nil]
def edit_post(post_id, title, content)
  db = connect_to_db()

  db.execute("UPDATE Post SET title = ?, content = ? WHERE post_id = ?", [title, content, post_id])

  db.close
end

# Titleizes a string
#
# @param [String] string the string to be titleized
#
# @return [String] the titleized string
def titleize(string)
  string.split.map(&:capitalize).join(" ")
end

# Retrieves a tag from the database based on its ID
#
# @param [Integer] tag_id The ID of the tag to retrieve
#
# @return [Hash]
#   * :tag_id [Integer] The ID of the tag
#   * :name [String] The name of the tag
# @return [nil] if the tag is not found
def get_tag(tag_id)
  db = connect_to_db()
  tag = db.execute("SELECT * FROM Tag WHERE tag_id = ?", [tag_id]).first
  db.close

  return tag
end

# Finds a tag's ID based on its title
#
# @param [String] tag The title of the tag
#
# @return [Integer, nil] The ID of the tag, or nil if not found
def get_tag_id(tag)
  db = connect_to_db()
  titleized_tag = titleize(tag)
  result = db.execute("SELECT tag_id FROM Tag WHERE title = ?", [titleized_tag])
  db.close

  return result.empty? ? nil : result[0][0]
end

# Adds a tag if it does not exist in the database
#
# @param [String] tag the name of the tag to add
# @return [Integer] the ID of the tag that was added or already existed
def add_tag_if_not_exist(tag)
  tag_id = get_tag_id(tag)

  unless tag_id
    db = connect_to_db()
    titleized_tag = titleize(tag)
    db.execute("INSERT INTO Tag (title) VALUES (?)", [titleized_tag])
    tag_id = db.last_insert_row_id
    db.close
  end

  return tag_id
end

# Adds tags to a post and database
#
# @param [Integer] post_id The ID of the post
# @param [Integer] database_id The ID of the database
# @param [Array<String>] tags An array of tags to add
#
# @return [void]
def add_tags_to_post_and_database(post_id, database_id, tags)
  db = connect_to_db()

  tag_ids = tags.map { |tag| add_tag_if_not_exist(tag) }

  db.transaction do
    tag_ids.each_with_index do |tag_id, index|
      db.execute("INSERT OR IGNORE INTO PostTagRel (post_id, tag_id) VALUES (?, ?)", [post_id, tag_id])
      db.execute("INSERT OR IGNORE INTO TagDatabaseRel (database_id, tag_id) VALUES (?, ?)", [database_id, tag_id])
    end
  end

  db.close
end

# Finds all tags for a given post
#
# @param [Integer] post_id The ID of the post to find tags for
#
# @return [Array<Hash>]
#   * :tag_id [Integer] The ID of the tag
#   * :tag_name [String] The name of the tag
def get_tags_for_post(post_id)
  db = connect_to_db()
  tags = db.execute(%{
    SELECT * FROM Tag
    INNER JOIN PostTagRel ON Tag.tag_id = PostTagRel.tag_id
    WHERE PostTagRel.post_id = ?
  }.gsub(/\s+/, " ").strip, [post_id])
  db.close

  return tags
end

# Gets all tags for a user's databases
#
# @param [Integer] user_id The ID of the user
#
# @return [Array<Hash>] An array of hashes representing tags for user's databases
#   * :tag_id [Integer] The ID of the tag
#   * :name [String] The name of the tag
#   * :database_id [Integer] The ID of the database associated with the tag
#   * :database_name [String] The name of the database associated with the tag
def get_tags_for_database(user_id)
  db = connect_to_db()

  tags = db.execute(%{
    SELECT * FROM Tag
    INNER JOIN TagDatabaseRel ON Tag.tag_id = TagDatabaseRel.tag_id
    INNER JOIN Database ON TagDatabaseRel.database_id = Database.database_id
    INNER JOIN UserDatabaseRel ON Database.database_id = UserDatabaseRel.database_id
    WHERE UserDatabaseRel.user_id = ?
  }.gsub(/\s+/, " ").strip, [user_id])
  db.close

  return tags
end

# This method accepts a tag_id as an argument and returns all the posts that are associated with that tag.
# The method first connects to the database and then fetches all the posts that are associated with the given tag.
# It then fetches all the tags associated with each post using a join operation between Post, PostTagRel, and Tag tables.
# The method returns a hash containing all the posts associated with the given tag along with their associated tags.
#
# @param [Integer] tag_id The ID of the tag
#
# @return [Array<Hash>]
#   * :post_id [Integer] The ID of the post
#   * :title [String] The title of the post
#   * :content [String] The content of the post
#   * :tags [Array<Hash>]
#       * :tag_id [Integer] The ID of the tag
#       * :title [String] The title of the tag
def get_posts_for_tag(tag_id)
  db = connect_to_db()

  post_results = db.execute(%{
    SELECT
      Post.post_id,
      Post.title,
      Post.content
    FROM
      Post
      INNER JOIN PostTagRel ON Post.post_id = PostTagRel.post_id
    WHERE
      PostTagRel.tag_id = ?
}, [tag_id])

  posts = {}

  post_results.each do |result|
    post_id = result["post_id"]
    title = result["title"]
    content = result["content"]
    posts[post_id] = { "post_id" => post_id, "title" => title, "content" => content, "tags" => [] }
  end

  post_ids = posts.keys
  placeholders = post_ids.map { "?" }.join(", ")

  tag_results = db.execute(%{
    SELECT
      Post.post_id,
      Tag.tag_id,
      Tag.title as tag_title
    FROM
      Post
      INNER JOIN PostTagRel ON Post.post_id = PostTagRel.post_id
      INNER JOIN Tag ON PostTagRel.tag_id = Tag.tag_id
    WHERE
      Post.post_id IN (#{placeholders})
}, post_ids)

  db.close()

  tag_results.each do |result|
    post_id = result["post_id"]
    tag_id = result["tag_id"]
    tag_title = result["tag_title"]

    posts[post_id]["tags"] << { "tag_id" => tag_id, "title" => tag_title }
  end

  return posts.values
end

# Deletes a tag and all its associations from the database
#
# @param [Integer] tag_id The ID of the tag to delete
#
# @return [nil]
def delete_tag(tag_id)
  db = connect_to_db()
  db.execute("DELETE FROM Tag WHERE tag_id = ?", [tag_id])
  db.execute("DELETE FROM PostTagRel WHERE tag_id = ?", [tag_id])
  db.execute("DELETE FROM TagDatabaseRel WHERE tag_id = ?", [tag_id])
  db.close
end

# Deletes a post and its associated tags from the database
#
# @param [Integer] post_id The ID of the post to delete
#
# @return [nil]
def delete_post(post_id)
  db = connect_to_db()

  db.execute("DELETE FROM Post WHERE post_id = ?", [post_id])
  db.execute("DELETE FROM PostTagRel WHERE post_id = ?", [post_id])

  db.close
end

# Deletes a database and all associated posts and tags
#
# @param [Integer] database_id The ID of the database
# @param [Integer] user_id The ID of the user attempting to delete the database
#
# @return [nil]
#
# @raise [RuntimeError] if user is not the owner of the database
def delete_database(database_id, user_id)
  db = connect_to_db()

  owner = db.execute(%{
    SELECT
      UserDatabaseRel.user_id as owner_id
    FROM
      UserDatabaseRel
    WHERE
      UserDatabaseRel.database_id = ? AND UserDatabaseRel.user_id = ? AND UserDatabaseRel.permissions = 'owner'
  }.gsub(/\s+/, " ").strip, [database_id, user_id]).first

  if owner.nil? || owner.empty? || owner["owner_id"] != user_id
    db.close
    raise "userNotOwner"
  end

  db.execute("DELETE FROM Database WHERE database_id = ?", [database_id])
  db.execute("DELETE FROM UserDatabaseRel WHERE database_id = ?", [database_id])
  db.execute("DELETE FROM TagDatabaseRel WHERE database_id = ?", [database_id])

  # delete all posts
  db.execute("DELETE FROM Post WHERE database_id = ?", [database_id])
  db.execute("DELETE FROM PostTagRel WHERE post_id IN (SELECT post_id FROM Post WHERE database_id = ?)", [database_id])

  db.close
end

# Removes a tag from a post
#
# @param [Integer] tag_id The ID of the tag to remove
# @param [Integer] post_id The ID of the post to remove the tag from
#
# @return [nil]
def remove_tag_from_post(tag_id, post_id)
  db = connect_to_db()

  db.execute("DELETE FROM PostTagRel WHERE tag_id = ? AND post_id = ?", [tag_id, post_id])

  db.close
end

# Gets the databases owned by a user
#
# @param [Integer] user_id The ID of the user
#
# @return [Array<Hash>]
#   * :database_id [Integer] The ID of the database
#   * :name [String] The name of the database
#   * :created_at [String] The creation date of the database
#   * :updated_at [String] The last update date of the database
#   * :permission_type [String] The type of permission the user has (should be 'owner')
#   * :viewers [Array<Hash>]
#     * :user_id [Integer] The ID of the user with viewing permission
#     * :permission_type [String] The type of permission the user has (should be 'viewer')
def get_owned_databases(user_id)
  db = connect_to_db()

  # Fetch databases owned by the user
  owned_databases = db.execute(%{
    SELECT
      Database.database_id,
      Database.name,
      Database.created_at,
      Database.updated_at,
      UserDatabaseRel.permission_type
    FROM
      Database
    INNER JOIN UserDatabaseRel ON Database.database_id = UserDatabaseRel.database_id
    WHERE
      UserDatabaseRel.user_id = ? AND UserDatabaseRel.permission_type = 'owner'
  }.gsub(/\s+/, " ").strip, [user_id])

  db.close

  # Add the viewers for each owned database
  owned_databases.each do |database|
    database["viewers"] = get_database_viewers(database["database_id"])
  end

  return owned_databases
end

# Get all viewers of a database
#
# @param [Integer] database_id The ID of the database
#
# @return [Array<Hash>]
#   * :user_id [Integer] The ID of the viewer user
#   * :email [String] The email of the viewer user
#   * :permission_type [String] The permission type of the viewer user, in this case 'viewer'
# @return [nil] if no viewers are found
def get_database_viewers(database_id)
  db = connect_to_db()

  viewers = db.execute(%{
    SELECT
      User.user_id,
      User.email,
      UserDatabaseRel.permission_type
    FROM
      User
      INNER JOIN UserDatabaseRel ON User.user_id = UserDatabaseRel.user_id
    WHERE
      UserDatabaseRel.database_id = ?
      AND UserDatabaseRel.permission_type = 'viewer'
  }.gsub(/\s+/, " ").strip, [database_id])

  db.close

  return viewers
end

# Gets owned databases with their respective permissions
#
# @param [Integer] user_id The ID of the user who owns the databases
#
# @return [Array<Hash>]
#   * :database_id [Integer] The ID of the database
#   * :name [String] The name of the database
#   * :description [String] The description of the database
#   * :viewers [Array<Integer>] The IDs of users who can view the database
def get_owned_databases_with_permissions(user_id)
  owned_databases = get_owned_databases(user_id)

  owned_databases.each do |database|
    database["viewers"] = get_database_viewers(database["database_id"])
  end

  return owned_databases
end

# Adds a user by email to a database
#
# @param [Integer] database_id The ID of the database
# @param [String] email The email of the user to be added
# @param [Integer] user_id The ID of the user adding the new user
#
# @raise [StandardError] if the user adding the new user is not the owner of the database
# @raise [StandardError] if the user to be added does not exist
# @raise [StandardError] if the user to be added is already in the database
#
# @return [Hash] The user added to the database
def add_user_by_email_to_database(database_id, email, user_id)
  db = connect_to_db()

  owner = db.execute(%{
    SELECT
      UserDatabaseRel.user_id as owner_id FROM UserDatabaseRel
    WHERE
      UserDatabaseRel.database_id = ? AND UserDatabaseRel.user_id = ? AND UserDatabaseRel.permission_type = 'owner'
    }.gsub(/\s+/, " ").strip, [database_id, user_id]).first

  if owner.nil? || owner.empty? || owner["owner_id"] != user_id
    db.close
    raise "userNotOwner"
  end

  user = db.execute("SELECT * FROM User WHERE email = ?", [email]).first

  if user.nil?
    db.close
    raise "userNotExist"
  end

  user_already_exist = db.execute("SELECT * FROM UserDatabaseRel WHERE user_id = ? AND database_id = ?", [user["user_id"], database_id]).first

  if user_already_exist
    db.close
    raise "userAlreadyInDatabase"
  end

  db.execute("INSERT INTO UserDatabaseRel (user_id, database_id, permission_type) VALUES (?, ?, ?)", [user["user_id"], database_id, "viewer"])

  db.close

  return user
end

# Removes a user from a database
#
# @param [Integer] database_id The ID of the database
# @param [Integer] user_id The ID of the user to be removed
#
# @return [nil]
def remove_user_from_database(database_id, user_id)
  db = connect_to_db()

  db.execute(%{
    DELETE UserDatabaseRel
    FROM UserDatabaseRel
    INNER JOIN Database ON UserDatabaseRel.database_id = Database.database_id
    WHERE UserDatabaseRel.user_id = ? AND UserDatabaseRel.permission_type = 'owner'
  }.gsub(/\s+/, " ").strip, [user_id])

  db.close
end

# Creates a new post in the database
#
# @param [String] title The title of the post
# @param [String] content The content of the post
# @param [Integer] database_id The ID of the database where the post will be created
#
# @return [Integer] the ID of the newly created post
def new_post(title, content, database_id)
  db = connect_to_db()

  created_at = Time.now.to_i

  db.execute("INSERT INTO Post (title, content, created_at, database_id) VALUES (?, ?, ?, ?)", [title, content, created_at, database_id])
  new_post_id = db.last_insert_row_id

  db.close

  return new_post_id
end

# Get a post from the database
#
# @param [Integer] post_id The ID of the post
#
# @return [Hash]
#   * :post_id [Integer] The ID of the post
#   * :title [String] The title of the post
#   * :content [String] The content of the post
#   * :created_at [DateTime] The date and time when the post was created
#   * :updated_at [DateTime] The date and time when the post was last updated
# @return [nil] if post is not found
def get_post(post_id)
  db = connect_to_db()

  post = db.execute("SELECT * FROM Post WHERE post_id = ?", [post_id]).first
  db.close

  return post
end

# Edits a post
#
# @param [Integer] post_id The ID of the post to edit
# @param [String] title The new title for the post
# @param [String] content The new content for the post
#
# @return [nil]
def edit_post(post_id, title, content)
  db = connect_to_db()

  db.execute("UPDATE Post SET title = ?, content = ? WHERE post_id = ?", [title, content, post_id])

  db.close
end

# Titleizes a string
#
# @param [String] string the string to be titleized
#
# @return [String] the titleized string
def titleize(string)
  string.split.map(&:capitalize).join(" ")
end

# Retrieves a tag from the database based on its ID
#
# @param [Integer] tag_id The ID of the tag to retrieve
#
# @return [Hash]
#   * :tag_id [Integer] The ID of the tag
#   * :name [String] The name of the tag
# @return [nil] if the tag is not found
def get_tag(tag_id)
  db = connect_to_db()
  tag = db.execute("SELECT * FROM Tag WHERE tag_id = ?", [tag_id]).first
  db.close

  return tag
end

# Finds a tag's ID based on its title
#
# @param [String] tag The title of the tag
#
# @return [Integer, nil] The ID of the tag, or nil if not found
def get_tag_id(tag)
  db = connect_to_db()
  titleized_tag = titleize(tag)
  result = db.execute("SELECT tag_id FROM Tag WHERE title = ?", [titleized_tag])
  db.close

  return result.empty? ? nil : result[0][0]
end

# Adds a tag if it does not exist in the database
#
# @param [String] tag the name of the tag to add
# @return [Integer] the ID of the tag that was added or already existed
def add_tag_if_not_exist(tag)
  tag_id = get_tag_id(tag)

  unless tag_id
    db = connect_to_db()
    titleized_tag = titleize(tag)
    db.execute("INSERT INTO Tag (title) VALUES (?)", [titleized_tag])
    tag_id = db.last_insert_row_id
    db.close
  end

  return tag_id
end

# Adds tags to a post and database
#
# @param [Integer] post_id The ID of the post
# @param [Integer] database_id The ID of the database
# @param [Array<String>] tags An array of tags to add
#
# @return [void]
def add_tags_to_post_and_database(post_id, database_id, tags)
  db = connect_to_db()

  tag_ids = tags.map { |tag| add_tag_if_not_exist(tag) }

  db.transaction do
    tag_ids.each_with_index do |tag_id, index|
      db.execute("INSERT OR IGNORE INTO PostTagRel (post_id, tag_id) VALUES (?, ?)", [post_id, tag_id])
      db.execute("INSERT OR IGNORE INTO TagDatabaseRel (database_id, tag_id) VALUES (?, ?)", [database_id, tag_id])
    end
  end

  db.close
end

# Finds all tags for a given post
#
# @param [Integer] post_id The ID of the post to find tags for
#
# @return [Array<Hash>]
#   * :tag_id [Integer] The ID of the tag
#   * :tag_name [String] The name of the tag
def get_tags_for_post(post_id)
  db = connect_to_db()
  tags = db.execute(%{
    SELECT * FROM Tag
    INNER JOIN PostTagRel ON Tag.tag_id = PostTagRel.tag_id
    WHERE PostTagRel.post_id = ?
  }.gsub(/\s+/, " ").strip, [post_id])
  db.close

  return tags
end

# Gets all tags for a user's databases
#
# @param [Integer] user_id The ID of the user
#
# @return [Array<Hash>] An array of hashes representing tags for user's databases
#   * :tag_id [Integer] The ID of the tag
#   * :name [String] The name of the tag
#   * :database_id [Integer] The ID of the database associated with the tag
#   * :database_name [String] The name of the database associated with the tag
def get_tags_for_database(user_id)
  db = connect_to_db()

  tags = db.execute(%{
    SELECT * FROM Tag
    INNER JOIN TagDatabaseRel ON Tag.tag_id = TagDatabaseRel.tag_id
    INNER JOIN Database ON TagDatabaseRel.database_id = Database.database_id
    INNER JOIN UserDatabaseRel ON Database.database_id = UserDatabaseRel.database_id
    WHERE UserDatabaseRel.user_id = ?
  }.gsub(/\s+/, " ").strip, [user_id])
  db.close

  return tags
end

# This method accepts a tag_id as an argument and returns all the posts that are associated with that tag.
# The method first connects to the database and then fetches all the posts that are associated with the given tag.
# It then fetches all the tags associated with each post using a join operation between Post, PostTagRel, and Tag tables.
# The method returns a hash containing all the posts associated with the given tag along with their associated tags.
#
# @param [Integer] tag_id The ID of the tag
#
# @return [Array<Hash>]
#   * :post_id [Integer] The ID of the post
#   * :title [String] The title of the post
#   * :content [String] The content of the post
#   * :tags [Array<Hash>]
#       * :tag_id [Integer] The ID of the tag
#       * :title [String] The title of the tag
def get_posts_for_tag(tag_id)
  db = connect_to_db()

  post_results = db.execute(%{
    SELECT
      Post.post_id,
      Post.title,
      Post.content
    FROM
      Post
      INNER JOIN PostTagRel ON Post.post_id = PostTagRel.post_id
    WHERE
      PostTagRel.tag_id = ?
}, [tag_id])

  posts = {}

  post_results.each do |result|
    post_id = result["post_id"]
    title = result["title"]
    content = result["content"]
    posts[post_id] = { "post_id" => post_id, "title" => title, "content" => content, "tags" => [] }
  end

  post_ids = posts.keys
  placeholders = post_ids.map { "?" }.join(", ")

  tag_results = db.execute(%{
    SELECT
      Post.post_id,
      Tag.tag_id,
      Tag.title as tag_title
    FROM
      Post
      INNER JOIN PostTagRel ON Post.post_id = PostTagRel.post_id
      INNER JOIN Tag ON PostTagRel.tag_id = Tag.tag_id
    WHERE
      Post.post_id IN (#{placeholders})
}, post_ids)

  db.close()

  tag_results.each do |result|
    post_id = result["post_id"]
    tag_id = result["tag_id"]
    tag_title = result["tag_title"]

    posts[post_id]["tags"] << { "tag_id" => tag_id, "title" => tag_title }
  end

  return posts.values
end

# Deletes a tag and all its associations from the database
#
# @param [Integer] tag_id The ID of the tag to delete
#
# @return [nil]
def delete_tag(tag_id)
  db = connect_to_db()
  db.execute("DELETE FROM Tag WHERE tag_id = ?", [tag_id])
  db.execute("DELETE FROM PostTagRel WHERE tag_id = ?", [tag_id])
  db.execute("DELETE FROM TagDatabaseRel WHERE tag_id = ?", [tag_id])
  db.close
end

# Deletes a post and its associated tags from the database
#
# @param [Integer] post_id The ID of the post to delete
#
# @return [nil]
def delete_post(post_id)
  db = connect_to_db()

  db.execute("DELETE FROM Post WHERE post_id = ?", [post_id])
  db.execute("DELETE FROM PostTagRel WHERE post_id = ?", [post_id])

  db.close
end

# Deletes a database and all associated posts and tags
#
# @param [Integer] database_id The ID of the database
# @param [Integer] user_id The ID of the user attempting to delete the database
#
# @return [nil]
#
# @raise [RuntimeError] if user is not the owner of the database
def delete_database(database_id, user_id)
  db = connect_to_db()

  owner = db.execute(%{
    SELECT
      UserDatabaseRel.user_id as owner_id
    FROM
      UserDatabaseRel
    WHERE
      UserDatabaseRel.database_id = ? AND UserDatabaseRel.user_id = ? AND UserDatabaseRel.permissions = 'owner'
  }.gsub(/\s+/, " ").strip, [database_id, user_id]).first

  if owner.nil? || owner.empty? || owner["owner_id"] != user_id
    db.close
    raise "userNotOwner"
  end

  db.execute("DELETE FROM Database WHERE database_id = ?", [database_id])
  db.execute("DELETE FROM UserDatabaseRel WHERE database_id = ?", [database_id])
  db.execute("DELETE FROM TagDatabaseRel WHERE database_id = ?", [database_id])

  # delete all posts
  db.execute("DELETE FROM Post WHERE database_id = ?", [database_id])
  db.execute("DELETE FROM PostTagRel WHERE post_id IN (SELECT post_id FROM Post WHERE database_id = ?)", [database_id])

  db.close
end

# Removes a tag from a post
#
# @param [Integer] tag_id The ID of the tag to remove
# @param [Integer] post_id The ID of the post to remove the tag from
#
# @return [nil]
def remove_tag_from_post(tag_id, post_id)
  db = connect_to_db()

  db.execute("DELETE FROM PostTagRel WHERE tag_id = ? AND post_id = ?", [tag_id, post_id])

  db.close
end

# Gets the databases owned by a user
#
# @param [Integer] user_id The ID of the user
#
# @return [Array<Hash>]
#   * :database_id [Integer] The ID of the database
#   * :name [String] The name of the database
#   * :created_at [String] The creation date of the database
#   * :updated_at [String] The last update date of the database
#   * :permission_type [String] The type of permission the user has (should be 'owner')
#   * :viewers [Array<Hash>]
#     * :user_id [Integer] The ID of the user with viewing permission
#     * :permission_type [String] The type of permission the user has (should be 'viewer')
def get_owned_databases(user_id)
  db = connect_to_db()

  # Fetch databases owned by the user
  owned_databases = db.execute(%{
    SELECT
      Database.database_id,
      Database.name,
      Database.created_at,
      Database.updated_at,
      UserDatabaseRel.permission_type
    FROM
      Database
    INNER JOIN UserDatabaseRel ON Database.database_id = UserDatabaseRel.database_id
    WHERE
      UserDatabaseRel.user_id = ? AND UserDatabaseRel.permission_type = 'owner'
  }.gsub(/\s+/, " ").strip, [user_id])

  db.close

  # Add the viewers for each owned database
  owned_databases.each do |database|
    database["viewers"] = get_database_viewers(database["database_id"])
  end

  return owned_databases
end

# Get all viewers of a database
#
# @param [Integer] database_id The ID of the database
#
# @return [Array<Hash>]
#   * :user_id [Integer] The ID of the viewer user
#   * :email [String] The email of the viewer user
#   * :permission_type [String] The permission type of the viewer user, in this case 'viewer'
# @return [nil] if no viewers are found
def get_database_viewers(database_id)
  db = connect_to_db()

  viewers = db.execute(%{
    SELECT
      User.user_id,
      User.email,
      UserDatabaseRel.permission_type
    FROM
      User
      INNER JOIN UserDatabaseRel ON User.user_id = UserDatabaseRel.user_id
    WHERE
      UserDatabaseRel.database_id = ?
      AND UserDatabaseRel.permission_type = 'viewer'
  }.gsub(/\s+/, " ").strip, [database_id])

  db.close

  return viewers
end

# Gets owned databases with their respective permissions
#
# @param [Integer] user_id The ID of the user who owns the databases
#
# @return [Array<Hash>]
#   * :database_id [Integer] The ID of the database
#   * :name [String] The name of the database
#   * :description [String] The description of the database
#   * :viewers [Array<Integer>] The IDs of users who can view the database
def get_owned_databases_with_permissions(user_id)
  owned_databases = get_owned_databases(user_id)

  owned_databases.each do |database|
    database["viewers"] = get_database_viewers(database["database_id"])
  end

  return owned_databases
end

# Adds a user by email to a database
#
# @param [Integer] database_id The ID of the database
# @param [String] email The email of the user to be added
# @param [Integer] user_id The ID of the user adding the new user
#
# @raise [StandardError] if the user adding the new user is not the owner of the database
# @raise [StandardError] if the user to be added does not exist
# @raise [StandardError] if the user to be added is already in the database
#
# @return [Hash] The user added to the database
def add_user_by_email_to_database(database_id, email, user_id)
  db = connect_to_db()

  owner = db.execute(%{
    SELECT
      UserDatabaseRel.user_id as owner_id FROM UserDatabaseRel
    WHERE
      UserDatabaseRel.database_id = ? AND UserDatabaseRel.user_id = ? AND UserDatabaseRel.permission_type = 'owner'
    }.gsub(/\s+/, " ").strip, [database_id, user_id]).first

  if owner.nil? || owner.empty? || owner["owner_id"] != user_id
    db.close
    raise "userNotOwner"
  end

  user = db.execute("SELECT * FROM User WHERE email = ?", [email]).first

  if user.nil?
    db.close
    raise "userNotExist"
  end

  user_already_exist = db.execute("SELECT * FROM UserDatabaseRel WHERE user_id = ? AND database_id = ?", [user["user_id"], database_id]).first

  if user_already_exist
    db.close
    raise "userAlreadyInDatabase"
  end

  db.execute("INSERT INTO UserDatabaseRel (user_id, database_id, permission_type) VALUES (?, ?, ?)", [user["user_id"], database_id, "viewer"])

  db.close

  return user
end

# Removes a user from a database
#
# @param [Integer] database_id The ID of the database
# @param [Integer] user_id The ID of the user to be removed
#
# @return [nil]
def remove_user_from_database(database_id, user_id)
  db = connect_to_db()

  db.execute(%{
    DELETE UserDatabaseRel
    FROM UserDatabaseRel
    INNER JOIN Database ON UserDatabaseRel.database_id = Database.database_id
    WHERE UserDatabaseRel.user_id = ? AND UserDatabaseRel.permission_type = 'owner'
  }.gsub(/\s+/, " ").strip, [user_id])

  db.close
end

# Creates a new post in the database
#
# @param [String] title The title of the post
# @param [String] content The content of the post
# @param [Integer] database_id The ID of the database where the post will be created
#
# @return [Integer] the ID of the newly created post
def new_post(title, content, database_id)
  db = connect_to_db()

  created_at = Time.now.to_i

  db.execute("INSERT INTO Post (title, content, created_at, database_id) VALUES (?, ?, ?, ?)", [title, content, created_at, database_id])
  new_post_id = db.last_insert_row_id

  db.close

  return new_post_id
end

# Get a post from the database
#
# @param [Integer] post_id The ID of the post
#
# @return [Hash]
#   * :post_id [Integer] The ID of the post
#   * :title [String] The title of the post
#   * :content [String] The content of the post
#   * :created_at [DateTime] The date and time when the post was created
#   * :updated_at [DateTime] The date and time when the post was last updated
# @return [nil] if post is not found
def get_post(post_id)
  db = connect_to_db()

  post = db.execute("SELECT * FROM Post WHERE post_id = ?", [post_id]).first
  db.close

  return post
end

# Edits a post
#
# @param [Integer] post_id The ID of the post to edit
# @param [String] title The new title for the post
# @param [String] content The new content for the post
#
# @return [nil]
def edit_post(post_id, title, content)
  db = connect_to_db()

  db.execute("UPDATE Post SET title = ?, content = ? WHERE post_id = ?", [title, content, post_id])

  db.close
end

# Titleizes a string
#
# @param [String] string the string to be titleized
#
# @return [String] the titleized string
def titleize(string)
  string.split.map(&:capitalize).join(" ")
end

# Retrieves a tag from the database based on its ID
#
# @param [Integer] tag_id The ID of the tag to retrieve
#
# @return [Hash]
#   * :tag_id [Integer] The ID of the tag
#   * :name [String] The name of the tag
# @return [nil] if the tag is not found
def get_tag(tag_id)
  db = connect_to_db()
  tag = db.execute("SELECT * FROM Tag WHERE tag_id = ?", [tag_id]).first
  db.close

  return tag
end

# Finds a tag's ID based on its title
#
# @param [String] tag The title of the tag
#
# @return [Integer, nil] The ID of the tag, or nil if not found
def get_tag_id(tag)
  db = connect_to_db()
  titleized_tag = titleize(tag)
  result = db.execute("SELECT tag_id FROM Tag WHERE title = ?", [titleized_tag])
  db.close

  return result.empty? ? nil : result[0][0]
end

# Adds a tag if it does not exist in the database
#
# @param [String] tag the name of the tag to add
# @return [Integer] the ID of the tag that was added or already existed
def add_tag_if_not_exist(tag)
  tag_id = get_tag_id(tag)

  unless tag_id
    db = connect_to_db()
    titleized_tag = titleize(tag)
    db.execute("INSERT INTO Tag (title) VALUES (?)", [titleized_tag])
    tag_id = db.last_insert_row_id
    db.close
  end

  return tag_id
end

# Adds tags to a post and database
#
# @param [Integer] post_id The ID of the post
# @param [Integer] database_id The ID of the database
# @param [Array<String>] tags An array of tags to add
#
# @return [void]
def add_tags_to_post_and_database(post_id, database_id, tags)
  db = connect_to_db()

  tag_ids = tags.map { |tag| add_tag_if_not_exist(tag) }

  db.transaction do
    tag_ids.each_with_index do |tag_id, index|
      db.execute("INSERT OR IGNORE INTO PostTagRel (post_id, tag_id) VALUES (?, ?)", [post_id, tag_id])
      db.execute("INSERT OR IGNORE INTO TagDatabaseRel (database_id, tag_id) VALUES (?, ?)", [database_id, tag_id])
    end
  end

  db.close
end

# Finds all tags for a given post
#
# @param [Integer] post_id The ID of the post to find tags for
#
# @return [Array<Hash>]
#   * :tag_id [Integer] The ID of the tag
#   * :tag_name [String] The name of the tag
def get_tags_for_post(post_id)
  db = connect_to_db()
  tags = db.execute(%{
    SELECT * FROM Tag
    INNER JOIN PostTagRel ON Tag.tag_id = PostTagRel.tag_id
    WHERE PostTagRel.post_id = ?
  }.gsub(/\s+/, " ").strip, [post_id])
  db.close

  return tags
end

# Gets all tags for a user's databases
#
# @param [Integer] user_id The ID of the user
#
# @return [Array<Hash>] An array of hashes representing tags for user's databases
#   * :tag_id [Integer] The ID of the tag
#   * :name [String] The name of the tag
#   * :database_id [Integer] The ID of the database associated with the tag
#   * :database_name [String] The name of the database associated with the tag
def get_tags_for_database(user_id)
  db = connect_to_db()

  tags = db.execute(%{
    SELECT * FROM Tag
    INNER JOIN TagDatabaseRel ON Tag.tag_id = TagDatabaseRel.tag_id
    INNER JOIN Database ON TagDatabaseRel.database_id = Database.database_id
    INNER JOIN UserDatabaseRel ON Database.database_id = UserDatabaseRel.database_id
    WHERE UserDatabaseRel.user_id = ?
  }.gsub(/\s+/, " ").strip, [user_id])
  db.close

  return tags
end

# This method accepts a tag_id as an argument and returns all the posts that are associated with that tag.
# The method first connects to the database and then fetches all the posts that are associated with the given tag.
# It then fetches all the tags associated with each post using a join operation between Post, PostTagRel, and Tag tables.
# The method returns a hash containing all the posts associated with the given tag along with their associated tags.
#
# @param [Integer] tag_id The ID of the tag
#
# @return [Array<Hash>]
#   * :post_id [Integer] The ID of the post
#   * :title [String] The title of the post
#   * :content [String] The content of the post
#   * :tags [Array<Hash>]
#       * :tag_id [Integer] The ID of the tag
#       * :title [String] The title of the tag
def get_posts_for_tag(tag_id)
  db = connect_to_db()

  post_results = db.execute(%{
    SELECT
      Post.post_id,
      Post.title,
      Post.content
    FROM
      Post
      INNER JOIN PostTagRel ON Post.post_id = PostTagRel.post_id
    WHERE
      PostTagRel.tag_id = ?
}, [tag_id])

  posts = {}

  post_results.each do |result|
    post_id = result["post_id"]
    title = result["title"]
    content = result["content"]
    posts[post_id] = { "post_id" => post_id, "title" => title, "content" => content, "tags" => [] }
  end

  post_ids = posts.keys
  placeholders = post_ids.map { "?" }.join(", ")

  tag_results = db.execute(%{
    SELECT
      Post.post_id,
      Tag.tag_id,
      Tag.title as tag_title
    FROM
      Post
      INNER JOIN PostTagRel ON Post.post_id = PostTagRel.post_id
      INNER JOIN Tag ON PostTagRel.tag_id = Tag.tag_id
    WHERE
      Post.post_id IN (#{placeholders})
}, post_ids)

  db.close()

  tag_results.each do |result|
    post_id = result["post_id"]
    tag_id = result["tag_id"]
    tag_title = result["tag_title"]

    posts[post_id]["tags"] << { "tag_id" => tag_id, "title" => tag_title }
  end

  return posts.values
end

# Deletes a tag and all its associations from the database
#
# @param [Integer] tag_id The ID of the tag to delete
#
# @return [nil]
def delete_tag(tag_id)
  db = connect_to_db()
  db.execute("DELETE FROM Tag WHERE tag_id = ?", [tag_id])
  db.execute("DELETE FROM PostTagRel WHERE tag_id = ?", [tag_id])
  db.execute("DELETE FROM TagDatabaseRel WHERE tag_id = ?", [tag_id])
  db.close
end

# Deletes a post and its associated tags from the database
#
# @param [Integer] post_id The ID of the post to delete
#
# @return [nil]
def delete_post(post_id)
  db = connect_to_db()

  db.execute("DELETE FROM Post WHERE post_id = ?", [post_id])
  db.execute("DELETE FROM PostTagRel WHERE post_id = ?", [post_id])

  db.close
end

# Deletes a database and all associated posts and tags
#
# @param [Integer] database_id The ID of the database
# @param [Integer] user_id The ID of the user attempting to delete the database
#
# @return [nil]
#
# @raise [RuntimeError] if user is not the owner of the database
def delete_database(database_id, user_id)
  db = connect_to_db()

  owner = db.execute(%{
    SELECT
      UserDatabaseRel.user_id as owner_id
    FROM
      UserDatabaseRel
    WHERE
      UserDatabaseRel.database_id = ? AND UserDatabaseRel.user_id = ? AND UserDatabaseRel.permissions = 'owner'
  }.gsub(/\s+/, " ").strip, [database_id, user_id]).first

  if owner.nil? || owner.empty? || owner["owner_id"] != user_id
    db.close
    raise "userNotOwner"
  end

  db.execute("DELETE FROM Database WHERE database_id = ?", [database_id])
  db.execute("DELETE FROM UserDatabaseRel WHERE database_id = ?", [database_id])
  db.execute("DELETE FROM TagDatabaseRel WHERE database_id = ?", [database_id])

  # delete all posts
  db.execute("DELETE FROM Post WHERE database_id = ?", [database_id])
  db.execute("DELETE FROM PostTagRel WHERE post_id IN (SELECT post_id FROM Post WHERE database_id = ?)", [database_id])

  db.close
end

# Removes a tag from a post
#
# @param [Integer] tag_id The ID of the tag to remove
# @param [Integer] post_id The ID of the post to remove the tag from
#
# @return [nil]
def remove_tag_from_post(tag_id, post_id)
  db = connect_to_db()

  db.execute("DELETE FROM PostTagRel WHERE tag_id = ? AND post_id = ?", [tag_id, post_id])

  db.close
end

# Gets the databases owned by a user
#
# @param [Integer] user_id The ID of the user
#
# @return [Array<Hash>]
#   * :database_id [Integer] The ID of the database
#   * :name [String] The name of the database
#   * :created_at [String] The creation date of the database
#   * :updated_at [String] The last update date of the database
#   * :permission_type [String] The type of permission the user has (should be 'owner')
#   * :viewers [Array<Hash>]
#     * :user_id [Integer] The ID of the user with viewing permission
#     * :permission_type [String] The type of permission the user has (should be 'viewer')
def get_owned_databases(user_id)
  db = connect_to_db()

  # Fetch databases owned by the user
  owned_databases = db.execute(%{
    SELECT
      Database.database_id,
      Database.name,
      Database.created_at,
      Database.updated_at,
      UserDatabaseRel.permission_type
    FROM
      Database
    INNER JOIN UserDatabaseRel ON Database.database_id = UserDatabaseRel.database_id
    WHERE
      UserDatabaseRel.user_id = ? AND UserDatabaseRel.permission_type = 'owner'
  }.gsub(/\s+/, " ").strip, [user_id])

  db.close

  # Add the viewers for each owned database
  owned_databases.each do |database|
    database["viewers"] = get_database_viewers(database["database_id"])
  end

  return owned_databases
end

# Get all viewers of a database
#
# @param [Integer] database_id The ID of the database
#
# @return [Array<Hash>]
#   * :user_id [Integer] The ID of the viewer user
#   * :email [String] The email of the viewer user
#   * :permission_type [String] The permission type of the viewer user, in this case 'viewer'
# @return [nil] if no viewers are found
def get_database_viewers(database_id)
  db = connect_to_db()

  viewers = db.execute(%{
    SELECT
      User.user_id,
      User.email,
      UserDatabaseRel.permission_type
    FROM
      User
      INNER JOIN UserDatabaseRel ON User.user_id = UserDatabaseRel.user_id
    WHERE
      UserDatabaseRel.database_id = ?
      AND UserDatabaseRel.permission_type = 'viewer'
  }.gsub(/\s+/, " ").strip, [database_id])

  db.close

  return viewers
end

# Gets owned databases with their respective permissions
#
# @param [Integer] user_id The ID of the user who owns the databases
#
# @return [Array<Hash>]
#   * :database_id [Integer] The ID of the database
#   * :name [String] The name of the database
#   * :description [String] The description of the database
#   * :viewers [Array<Integer>] The IDs of users who can view the database
def get_owned_databases_with_permissions(user_id)
  owned_databases = get_owned_databases(user_id)

  owned_databases.each do |database|
    database["viewers"] = get_database_viewers(database["database_id"])
  end

  return owned_databases
end

# Adds a user by email to a database
#
# @param [Integer] database_id The ID of the database
# @param [String] email The email of the user to be added
# @param [Integer] user_id The ID of the user adding the new user
#
# @raise [StandardError] if the user adding the new user is not the owner of the database
# @raise [StandardError] if the user to be added does not exist
# @raise [StandardError] if the user to be added is already in the database
#
# @return [Hash] The user added to the database
def add_user_by_email_to_database(database_id, email, user_id)
  db = connect_to_db()

  owner = db.execute(%{
    SELECT
      UserDatabaseRel.user_id as owner_id FROM UserDatabaseRel
    WHERE
      UserDatabaseRel.database_id = ? AND UserDatabaseRel.user_id = ? AND UserDatabaseRel.permission_type = 'owner'
    }.gsub(/\s+/, " ").strip, [database_id, user_id]).first

  if owner.nil? || owner.empty? || owner["owner_id"] != user_id
    db.close
    raise "userNotOwner"
  end

  user = db.execute("SELECT * FROM User WHERE email = ?", [email]).first

  if user.nil?
    db.close
    raise "userNotExist"
  end

  user_already_exist = db.execute("SELECT * FROM UserDatabaseRel WHERE user_id = ? AND database_id = ?", [user["user_id"], database_id]).first

  if user_already_exist
    db.close
    raise "userAlreadyInDatabase"
  end

  db.execute("INSERT INTO UserDatabaseRel (user_id, database_id, permission_type) VALUES (?, ?, ?)", [user["user_id"], database_id, "viewer"])

  db.close

  return user
end

# Removes a user from a database
#
# @param [Integer] database_id The ID of the database
# @param [Integer] user_id The ID of the user to be removed
#
# @return [nil]
def remove_user_from_database(database_id, user_id)
  db = connect_to_db()

  db.execute(%{
    DELETE UserDatabaseRel
    FROM UserDatabaseRel
    INNER JOIN Database ON UserDatabaseRel.database_id = Database.database_id
    WHERE UserDatabaseRel.user_id = ? AND UserDatabaseRel.permission_type = 'owner'
  }.gsub(/\s+/, " ").strip, [user_id])

  db.close
end
