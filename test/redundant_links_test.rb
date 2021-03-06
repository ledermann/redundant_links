require 'test/unit'

require 'rubygems'
gem 'activerecord', '>= 1.15.4.7794'
require 'active_record'

require "#{File.dirname(__FILE__)}/../init"

ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")

def setup_db
  ActiveRecord::Schema.define(:version => 1) do
    create_table :contacts do |t|
      t.column :name, :string
      t.column :type, :string
    end
    
    create_table :orders do |t|
      t.column :number, :string
      t.column :customer_id, :integer
    end
    
    create_table :notes do |t|
      t.column :object_id, :integer
      t.column :object_type, :string, :limit => 20
      t.column :content, :text
      t.column :type, :string
    end
    
    create_table :redundant_links, :force => true do |t|
      t.string :from_type, :limit => 20, :null => false
      t.integer :from_id, :null => false
      t.string :to_type, :limit => 20, :null => false
      t.integer :to_id, :null => false
    end
  end
end

def teardown_db
  ActiveRecord::Base.connection.tables.each do |table|
    ActiveRecord::Base.connection.drop_table(table)
  end
end

class Contact < ActiveRecord::Base
end
class Customer < Contact
  has_many :orders
  has_many :notes, :as => :object
end
class Order < ActiveRecord::Base
  belongs_to :customer
  has_many :notes, :as => :object
  has_many :derived_notes, :as => :object
end
class Note < ActiveRecord::Base
  belongs_to :object, :polymorphic => true

  has_redundant_links Note => :object, Order => :customer, Contact => nil
end
class DerivedNote < Note
end

class RedundantLinksTest < Test::Unit::TestCase

  def setup
    setup_db
    @customer = Customer.create!
    @order = @customer.orders.create!
    @note = @order.notes.create!
  end

  def teardown
    teardown_db
  end

  def test_count
    assert_equal 2, RedundantLink.count
    assert_equal 1, @customer.redundant_links.count
    assert_equal 1, @order.redundant_links.count
  end
  
  def test_linked_notes
    assert_equal [ @note ], @customer.redundant_linked_notes
    assert_equal [ @note ], @order.redundant_linked_notes
  end

  def test_respond_to
    assert !@customer.respond_to?(:foobar)
    assert !@customer.respond_to?(:redundant_linked_foos)
    assert @customer.respond_to?(:redundant_linked_notes)
  end
  
  def test_method_missing
    assert_raises(NoMethodError) { @customer.foobar }
    assert_raises(NoMethodError) { @customer.redundant_linked_foos }
    assert_nothing_raised { @customer.redundant_linked_notes }
  end
  
  def test_scope
    assert Note.respond_to?(:scope_for_redundant_linked_contact)
    assert Note.respond_to?(:scope_for_redundant_linked_order)
    assert !Note.respond_to?(:scope_for_redundant_linked_note)
    assert !Note.respond_to?(:scope_for_redundant_linked_customer)
  end
  
  def test_change_note
    other_order = @customer.orders.create!
    @note.update_attributes! :object => other_order
    assert_equal 0, @order.redundant_links.count
    assert_equal 1, other_order.redundant_links.count
  end
  
  def test_update_customer
    last_max = RedundantLink.maximum(:id)
    @customer.update_attributes! :name => 'Joe'
    assert_equal last_max, RedundantLink.maximum(:id)
    assert_equal [ @note ], @customer.redundant_linked_notes
  end
  
  def test_change_order_to_other_customer
    last_max = RedundantLink.maximum(:id)
    other_customer = Customer.create!
    @order.update_attributes! :customer => other_customer
    assert_equal 0, @customer.redundant_links.count
    assert_equal 1, other_customer.redundant_links.count
    assert_not_equal last_max, RedundantLink.maximum(:id)
  end

  def test_change_order_to_nil_contact
    last_count = RedundantLink.count
    last_max = RedundantLink.maximum(:id)
    @order.update_attributes! :customer => nil
    assert_equal 0, @customer.redundant_links.count
    assert_not_equal last_max, RedundantLink.maximum(:id)
    assert_equal last_count-1, RedundantLink.count
  end
  
  def test_change_order_other_attribute
    last_max = RedundantLink.maximum(:id)
    @order.update_attributes! :number => 'new number'
    assert_equal 1, @customer.redundant_links.count
    assert_equal last_max, RedundantLink.maximum(:id)
  end
  
  def test_change_empty_order_to_contact
    order = Order.create!
    note = order.notes.create!

    assert !@customer.redundant_linked_notes.include?(note)
    last_count = RedundantLink.count
    order.update_attributes :customer => @customer
    assert @customer.redundant_linked_notes.include?(note)
    assert_equal last_count+1, RedundantLink.count
  end
  
  def test_delete
    @note.destroy
    assert_equal 0, @customer.redundant_links.count
    assert_equal 0, @customer.redundant_linked_notes.count
    assert_equal 0, @order.redundant_links.count
    assert_equal 0, @order.redundant_linked_notes.count
  end
  
  def test_rebuild
    before_count = RedundantLink.count
    RedundantLink.delete_all
    assert_equal 0, RedundantLink.count
    
    Note.rebuild_redundant_links
    assert_equal before_count, RedundantLink.count
    
    Note.rebuild_redundant_links
    assert_equal before_count, RedundantLink.count
  end
  
  def test_sti
    @derived_note = @order.derived_notes.create!
    assert_equal 2, @order.redundant_links.count 
    assert_equal [ @derived_note ], @customer.redundant_linked_derived_notes
    assert_equal [ @note, @derived_note ], @customer.redundant_linked_notes
  end
end