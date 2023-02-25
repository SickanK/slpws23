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
