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
