def new_post(title, content, database_id)
  db = connect_to_db()

  created_at = Time.now.to_i

  db.execute("INSERT INTO Post (title, content, created_at, database_id) VALUES (?, ?, ?, ?)", [title, content, created_at, database_id])
  new_post_id = db.last_insert_row_id

  db.close

  return new_post_id
end

def get_post(post_id)
  db = connect_to_db()

  post = db.execute("SELECT * FROM Post WHERE post_id = ?", [post_id]).first
  db.close

  return post
end

def edit_post(post_id, title, content)
  db = connect_to_db()

  db.execute("UPDATE Post SET title = ?, content = ? WHERE post_id = ?", [title, content, post_id])

  db.close
end

# Tags
def titleize(string)
  string.split.map(&:capitalize).join(" ")
end

def get_tag(tag_id)
  db = connect_to_db()
  tag = db.execute("SELECT * FROM Tag WHERE tag_id = ?", [tag_id]).first
  db.close

  return tag
end

def get_tag_id(tag)
  db = connect_to_db()
  titleized_tag = titleize(tag)
  result = db.execute("SELECT tag_id FROM Tag WHERE title = ?", [titleized_tag])
  db.close

  return result.empty? ? nil : result[0][0]
end

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

# get tags

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

# get all tags for database
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

# get al posts for tag

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

def delete_tag(tag_id)
  db = connect_to_db()
  db.execute("DELETE FROM Tag WHERE tag_id = ?", [tag_id])
  db.execute("DELETE FROM PostTagRel WHERE tag_id = ?", [tag_id])
  db.execute("DELETE FROM TagDatabaseRel WHERE tag_id = ?", [tag_id])
  db.close
end

def delete_post(post_id)
  db = connect_to_db()

  db.execute("DELETE FROM Post WHERE post_id = ?", [post_id])
  db.execute("DELETE FROM PostTagRel WHERE post_id = ?", [post_id])

  db.close
end

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

def remove_tag_from_post(tag_id, post_id)
  db = connect_to_db()

  db.execute("DELETE FROM PostTagRel WHERE tag_id = ? AND post_id = ?", [tag_id, post_id])

  db.close
end

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

def get_owned_databases_with_permissions(user_id)
  owned_databases = get_owned_databases(user_id)

  owned_databases.each do |database|
    database["viewers"] = get_database_viewers(database["database_id"])
  end

  return owned_databases
end

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
