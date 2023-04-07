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
def get_posts_for_tag_and_user(tag_id, user_id)
  db = connect_to_db()

  post_results = db.execute(%{
    SELECT
      Post.post_id,
      Post.title,
      Post.content
    FROM
      Post
      INNER JOIN PostTagRel ON Post.post_id = PostTagRel.post_id
      INNER JOIN Tag ON PostTagRel.tag_id = Tag.tag_id
      INNER JOIN UserDatabaseRel ON Post.database_id = UserDatabaseRel.database_id
    WHERE
      PostTagRel.tag_id = ?
      AND UserDatabaseRel.user_id = ?
}.gsub(/\s+/, " ").strip, [tag_id, user_id])

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
}.gsub(/\s+/, " ").strip, post_ids)

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
