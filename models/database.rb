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
      UserDatabaseRel.database_id = ? AND UserDatabaseRel.user_id = ? AND UserDatabaseRel.permission_type = 'owner'
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
def remove_user_from_database(database_id, user_id, owner_id)
  db = connect_to_db()

  db.execute(%{
  DELETE FROM UserDatabaseRel
  WHERE
    UserDatabaseRel.user_id = ? AND UserDatabaseRel.database_id = ? AND UserDatabaseRel.permission_type = 'viewer' AND
    EXISTS (
      SELECT 1 FROM UserDatabaseRel owner_relation
      WHERE
        owner_relation.user_id = ? AND owner_relation.database_id = ? AND owner_relation.permission_type = 'owner'
    )
  }.gsub(/\s+/, " ").strip, [user_id, database_id, owner_id, database_id])

  db.close
end

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
