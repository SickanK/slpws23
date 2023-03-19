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

# Tags
def titleize(string)
  string.split.map(&:capitalize).join(" ")
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
  db.transaction do
    tags.each do |tag|
      tag_id = add_tag_if_not_exist(tag)

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
