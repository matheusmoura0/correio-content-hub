class CreateContentHub < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email, null: false, default: ""
      t.string :encrypted_password, null: false, default: ""
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at
      t.timestamps
    end
    add_index :users, :email, unique: true
    add_index :users, :reset_password_token, unique: true

    create_table :sites do |t|
      t.string :name, null: false
      t.string :domain, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :sites, :domain, unique: true

    create_table :categories do |t|
      t.references :site, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.timestamps
    end
    add_index :categories, [:site_id, :slug], unique: true

    create_table :feeds do |t|
      t.references :site, foreign_key: true
      t.references :category, foreign_key: true
      t.string :name, null: false
      t.string :url, null: false
      t.boolean :active, null: false, default: true
      t.datetime :last_imported_at
      t.timestamps
    end
    add_index :feeds, :url, unique: true

    create_table :articles do |t|
      t.references :feed, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.text :content
      t.string :image_url
      t.string :author
      t.string :source_url, null: false
      t.string :guid
      t.datetime :published_at
      t.string :status, null: false, default: "imported"
      t.timestamps
    end
    add_index :articles, :source_url, unique: true
    add_index :articles, [:feed_id, :guid], unique: true, where: "guid IS NOT NULL"
    add_index :articles, :status

    create_table :site_articles do |t|
      t.references :site, null: false, foreign_key: true
      t.references :article, null: false, foreign_key: true
      t.references :category, foreign_key: true
      t.string :status, null: false, default: "draft"
      t.datetime :published_at
      t.timestamps
    end
    add_index :site_articles, [:site_id, :article_id], unique: true
  end
end
