# frozen_string_literal: true

class User
  include Searchable

  def as_indexed_json(_options = {})
    {
      sub_type: self.type.downcase,
      slug: self.slug,
      title: self.name,
      body: self.description,
      user_id: self.id,
      deleted: self.es_deleted?
    }
  end

  def es_deleted?
    self.deleted? || self.system?
  end

  def indexed_changed?
    saved_change_to_deleted_at? ||
    saved_change_to_name? ||
    saved_change_to_description?
  end

  def self.prefix_search(term, user: nil, group: nil, repository: nil, limit: 30)
    term = "#{term}%"
    users = User.where(type: "User").without_system
    users = users.where("slug ilike ? or email ilike ? or name ilike ?", term, term, term)
    users = users.where("id != ?", user.id) if user
    users = users.limit(limit).to_a

    following = []

    if user
      following = user.follow_users.without_system.where("slug ilike ? or email ilike ? or name ilike ?", term, term, term)
    end

    users.unshift(*Array(following))
    users.uniq!
    users.compact!

    users.first(limit)
  end
end
